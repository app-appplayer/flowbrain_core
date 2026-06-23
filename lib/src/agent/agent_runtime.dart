/// FlowBrain Core — AgentRuntime.
///
/// LLM call orchestration + provider router + Manager Router + Reviewer
/// Engine. See:
///
///   - `os/core/flowbrain/docs/03_DDD/13-agent-runtime.md`
///   - FR-FBCORE-AGT-020..026, INF-009
library;

import 'dart:async';
import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart'
    show
        FactRecord,
        FeedbackEvent,
        FeedbackOutcome,
        InterventionPoint,
        LlmPort,
        LlmRequest,
        LlmMessage,
        LlmTool,
        MultiLayerContext,
        PhilosophyEvaluationContext,
        PipelineContext,
        Tension;
import 'package:mcp_knowledge/mcp_knowledge.dart' show KnowledgeEventBus;

import '../system/knowledge_system.dart' show KnowledgeSystem;
import 'agent_config.dart';
import 'agent_event.dart';
import 'agent_exception.dart';
import 'agent_lifecycle_fact.dart';
import 'agent_models.dart';
import 'agent_registry.dart';
import 'conversation_store.dart';
import 'fork_engine.dart';
import 'growth_tracker.dart';
import 'manager_router.dart';
import 'reviewer_engine.dart';

class AgentRuntime {
  AgentRuntime({
    required AgentRegistry registry,
    required ConversationStore conversationStore,
    required ForkEngine forkEngine,
    required AgentConfig config,
    required KnowledgeEventBus eventBus,
    LlmPort? defaultLlm,
    Map<String, LlmPort>? llmProviders,
    GrowthTracker? growthTracker,
    ManagerRouter managerRouter = const ManagerRouter(),
    ReviewerEngine reviewerEngine = const ReviewerEngine(),
  })  : _registry = registry,
        _conversationStore = conversationStore,
        // ignore: unused_field
        _forkEngine = forkEngine,
        _config = config,
        _eventBus = eventBus,
        _defaultLlm = defaultLlm,
        _llmProviders = llmProviders ?? const {},
        _growthTracker =
            growthTracker ?? GrowthTracker(registry: registry, config: config),
        _managerRouter = managerRouter,
        _reviewerEngine = reviewerEngine;

  final AgentRegistry _registry;
  final ConversationStore _conversationStore;
  final ForkEngine _forkEngine;
  final AgentConfig _config;
  final KnowledgeEventBus _eventBus;
  final LlmPort? _defaultLlm;
  final Map<String, LlmPort> _llmProviders;
  final GrowthTracker _growthTracker;
  final ManagerRouter _managerRouter;
  final ReviewerEngine _reviewerEngine;

  AgentRegistry get registry => _registry;
  ConversationStore get conversationStore => _conversationStore;
  ForkEngine get forkEngine => _forkEngine;
  GrowthTracker get growthTracker => _growthTracker;

  // ── LLM port resolution (FR-FBCORE-INF-009) ─────────────────────────────

  LlmPort _resolveLlmFor(ModelSpec model) {
    final fromPool = _llmProviders[model.provider];
    if (fromPool != null) return fromPool;
    final fallback = _defaultLlm;
    if (fallback != null) return fallback;
    throw StateError(
      'No LlmPort wired for provider \'${model.provider}\' — '
      'set infraPorts.llmProviders[\'${model.provider}\'] or infraPorts.llm.',
    );
  }

  // ── ask / stream ────────────────────────────────────────────────────────

  /// Single-turn dialog. Loads history, builds prompt, calls LLM, appends
  /// the new turn, emits `AgentInvokedEvent`. When [tools] is supplied the
  /// LLM may respond with structured tool invocations carried back in
  /// [AgentReply.toolCalls].
  /// [resetContext] = true wipes the conversation history before
  /// composing the prompt. Use for manager agents whose every turn
  /// should be treated as fresh (avoids unbounded context growth +
  /// stale prior-turn pollution that weakens current directive). The
  /// post-ask turn is still appended — the reset is one-shot.
  Future<AgentReply> ask(
    String agentId,
    String message, {
    Map<String, Object?>? context,
    List<LlmTool>? tools,
    bool resetContext = false,
  }) async {
    final agent = await _registry.get(agentId);
    if (agent == null) throw AgentNotFoundException(agentId);

    if (resetContext) {
      await _conversationStore.clear(agentId);
    }
    final history = await _safeLoadHistory(agentId);
    final llm = _resolveLlmFor(agent.model);

    // Compose the agent's assigned 4 axes (profile · philosophy · skill ·
    // facts) into the system prompt so the provider actually sees them —
    // profile/skill confine the agent to its specialty and philosophy
    // surfaces its operating constitution (values/prohibitions) every turn
    // (spec 12 §2). Base persona first, then the assigned-knowledge block.
    // None assigned → base only.
    final assignedKnowledge = await _composeAssignedAxes(agentId);
    final base = agent.systemPrompt;
    final effectiveSystemPrompt = assignedKnowledge == null
        ? base
        : (base == null || base.isEmpty
            ? assignedKnowledge
            : '$base\n\n$assignedKnowledge');

    final stopwatch = Stopwatch()..start();
    final request = LlmRequest(
      systemPrompt: effectiveSystemPrompt,
      messages: _buildMessages(history, message, context),
      model: agent.model.model,
      maxTokens: agent.model.maxTokens ?? _config.defaultModel?.maxTokens,
      temperature:
          agent.model.temperature ?? _config.defaultModel?.temperature,
      tools: tools,
    );

    bool success = false;
    String content = '';
    TokenUsage? tokenUsage;
    List<AgentToolCall>? toolCalls;
    String? finishReason;
    Object? thrown;

    try {
      final response = await llm.complete(request);
      content = response.content;
      finishReason = response.finishReason;
      final usage = response.usage;
      tokenUsage = usage != null
          ? TokenUsage(
              promptTokens: usage.inputTokens,
              completionTokens: usage.outputTokens,
              totalTokens: usage.totalTokens,
            )
          : null;
      final rawCalls = response.toolCalls;
      if (rawCalls != null && rawCalls.isNotEmpty) {
        toolCalls = rawCalls
            .map((c) => AgentToolCall(
                  id: c.id,
                  name: c.name,
                  arguments: Map<String, Object?>.from(c.arguments),
                ))
            .toList(growable: false);
      }
      success = true;
    } catch (e) {
      thrown = e;
    } finally {
      stopwatch.stop();
    }

    // Philosophy work-time intervention (spec 12 §3): when the agent has an
    // assigned philosophy, the constitution gates the output *before*
    // delivery — a hard prohibition blocks the turn (not appended, surfaced
    // to the caller), modifications adjust it. Opt-in: no assigned philosophy
    // or no engine → skipped. Fails open on engine error so a philosophy
    // hiccup never breaks an otherwise-good turn.
    if (success) {
      try {
        content = await _interveneIfPhilosophy(agentId, content);
      } on AgentPhilosophyBlockedException catch (e) {
        success = false;
        thrown = e;
      }
    }

    final timestamp = DateTime.now();

    if (success) {
      final turn = ConversationTurn(
        userMessage: message,
        assistantReply: content,
        model: agent.model.model,
        tokenUsage: tokenUsage,
        timestamp: timestamp,
        extra: context,
      );
      await _conversationStore.append(agentId, turn);
    }

    _eventBus.emit(AgentInvokedEvent(
      agentId: agentId,
      model: agent.model.toString(),
      turnIndex: history.length,
      success: success,
      duration: stopwatch.elapsed,
      tokenUsage: tokenUsage,
      timestamp: timestamp,
    ));

    // Mirror the invocation into the workspace FactGraph (observability).
    if (_config.recordLifecycleAsFacts) {
      try {
        final ks = _registry.knowledgeSystemRef() as KnowledgeSystem;
        final fact = const AgentLifecycleFactBuilder().agentInvoked(
          agentId: agentId,
          workspaceId: agent.workspaceId,
          model: agent.model.toString(),
          turnIndex: history.length,
          success: success,
          duration: stopwatch.elapsed,
          tokenUsage: tokenUsage,
          timestamp: timestamp,
        );
        await ks.facts.writeFacts([fact]);
      } catch (e) {
        _eventBus.emit(AgentLifecycleFactFailedEvent(
          agentId: agentId,
          factType: AgentLifecycleFactType.agentInvoked,
          error: e.toString(),
          timestamp: DateTime.now(),
        ));
      }
    }

    if (thrown != null) {
      throw thrown;
    }

    return AgentReply(
      id: '',
      agentId: agentId,
      content: content,
      model: agent.model.model,
      timestamp: timestamp,
      tokenUsage: tokenUsage,
      toolCalls: toolCalls,
      finishReason: finishReason,
    );
  }

  /// Token streaming variant. Falls back to a single-emit stream when the
  /// adapter does not support streaming. [tools] is forwarded to the
  /// underlying `ask` call.
  Stream<AgentToken> stream(
    String agentId,
    String message, {
    Map<String, Object?>? context,
    List<LlmTool>? tools,
  }) async* {
    final reply =
        await ask(agentId, message, context: context, tools: tools);
    yield AgentToken(agentId: agentId, delta: reply.content, isFinal: true);
  }

  // ── route ──────────────────────────────────────────────────────────────

  Future<RoutingDecision> route(
    String managerId,
    String request, {
    List<String>? candidateAgentIds,
  }) async {
    if (!_config.enableManagerRouting) {
      throw StateError(
        'Manager routing is disabled (AgentConfig.enableManagerRouting=false)',
      );
    }
    final manager = await _registry.get(managerId);
    if (manager == null) throw AgentNotFoundException(managerId);
    if (manager.role != AgentRole.manager) {
      throw AgentRoleMismatchException(
        agentId: managerId,
        expectedRole: AgentRole.manager,
        actualRole: manager.role,
      );
    }
    final candidates = candidateAgentIds != null
        ? await _resolveCandidates(candidateAgentIds)
        : await _registry.list();
    final filtered =
        candidates.where((a) => a.id != managerId).toList(growable: false);

    final prompt = _managerRouter.buildPrompt(
      manager: manager,
      request: request,
      candidates: filtered,
    );

    final llm = _resolveLlmFor(manager.model);
    final response = await llm.complete(LlmRequest(
      systemPrompt: manager.systemPrompt,
      prompt: prompt,
      model: manager.model.model,
    ));
    final decision = _managerRouter.parseDecision(response.content);

    _eventBus.emit(ManagerRoutedEvent(
      managerId: managerId,
      targetAgentId: decision.targetAgentId,
      confidence: decision.confidence,
      reason: decision.reason,
      timestamp: DateTime.now(),
    ));

    return decision;
  }

  // ── review ─────────────────────────────────────────────────────────────

  Future<ReviewResult> review(String reviewerId, AgentReply targetReply) async {
    if (!_config.enableReviewer) {
      throw StateError(
        'Reviewer is disabled (AgentConfig.enableReviewer=false)',
      );
    }
    final reviewer = await _registry.get(reviewerId);
    if (reviewer == null) throw AgentNotFoundException(reviewerId);
    if (reviewer.role != AgentRole.reviewer) {
      throw AgentRoleMismatchException(
        agentId: reviewerId,
        expectedRole: AgentRole.reviewer,
        actualRole: reviewer.role,
      );
    }
    final prompt = _reviewerEngine.buildPrompt(
      reviewer: reviewer,
      targetReply: targetReply,
    );
    final llm = _resolveLlmFor(reviewer.model);
    final response = await llm.complete(LlmRequest(
      systemPrompt: reviewer.systemPrompt,
      prompt: prompt,
      model: reviewer.model.model,
    ));
    final result = _reviewerEngine.parseResult(response.content);
    _eventBus.emit(ReviewerVerifiedEvent(
      reviewerId: reviewerId,
      targetAgentId: targetReply.agentId,
      verdict: result.verdict,
      severity: result.severity,
      timestamp: DateTime.now(),
    ));

    // §4 (outcome → knowledge): feed the review verdict back as a Philosophy
    // FeedbackEvent so the constitution can *propose* an evolution. The
    // proposal is human-gated and never auto-applied (the facade only emits
    // an EvolutionProposedEvent). Opt-in (target agent has assigned
    // philosophy + engine evolution enabled); fails open.
    await _proposeFeedbackFromReview(targetReply.agentId, result);

    // §4 (skill refinement): a deficient verdict is an outcome signal that
    // the agent's procedure (skill) may need refinement — record a skill
    // variation *candidate* (the existing human-gated accumulator).
    await _proposeSkillRefinementFromReview(targetReply.agentId, result);

    // §3 (Philosophy as drift-anchor): a review verdict is the outcome that
    // drives a fork's non-philosophy axes to evolve. At that boundary, ask
    // Philosophy to detect tensions between the agent's evolving state and
    // the constitution so a drift signal is surfaced (event, not auto-revert).
    await _detectForkTensions(targetReply.agentId);

    return result;
  }

  /// Turn a reviewer verdict into a Philosophy [FeedbackEvent] proposal
  /// (spec 12 §4). No-op when the target has no assigned philosophy or the
  /// engine is unavailable. Never throws into the caller (fail open).
  Future<void> _proposeFeedbackFromReview(
      String targetAgentId, ReviewResult result) async {
    try {
      final refs = await _registry.listOwned(targetAgentId, AgentAxis.philosophy);
      if (refs.isEmpty) return;
      final ks = _registry.knowledgeSystemRef();
      if (ks is! KnowledgeSystem || !ks.philosophy.isAvailable) return;
      final ethos = await ks.philosophy.getEthos();
      final (outcome, score) = switch (result.verdict) {
        ReviewVerdict.pass => (FeedbackOutcome.positive, 1.0),
        ReviewVerdict.fail => (FeedbackOutcome.negative, 0.0),
        ReviewVerdict.revise => (FeedbackOutcome.mixed, 0.5),
      };
      await ks.philosophy.proposeFeedback(FeedbackEvent(
        id: 'feedback/$targetAgentId/${DateTime.now().microsecondsSinceEpoch}',
        actionId: 'review:$targetAgentId',
        ethosId: ethos.id,
        outcome: outcome,
        outcomeScore: score,
        outcomeDescription: 'reviewer verdict: ${result.verdict.name}',
        occurredAt: DateTime.now(),
      ));
    } catch (_) {
      // Fail open — a feedback-proposal hiccup must not break review.
    }
  }

  /// §4 skill-refinement path. A deficient review verdict (`fail` / `revise`)
  /// is an outcome signal that the agent's procedure (skill) may need
  /// refinement, so record a skill *variation candidate* per assigned skill
  /// fork via [GrowthTracker.trackVariation] (`GrowthKind.variation` →
  /// `skillCandidateCount`, the existing human-gated accumulator + FactGraph
  /// timeline + `AgentForkEvolvedEvent`). A `pass` verdict means the skill
  /// worked as-is → no candidate. Opt-in (target has an assigned skill);
  /// never throws into the caller (fail open).
  Future<void> _proposeSkillRefinementFromReview(
      String targetAgentId, ReviewResult result) async {
    if (result.verdict == ReviewVerdict.pass) return;
    try {
      final refs = await _registry.listOwned(targetAgentId, AgentAxis.skill);
      for (final ref in refs) {
        await _growthTracker.trackVariation(
          agentId: targetAgentId,
          forkedRef: ref.forkedRef,
        );
      }
    } catch (_) {
      // Fail open — a skill-refinement hiccup must not break review.
    }
  }

  /// Detect tensions between an agent's evolving non-philosophy axes
  /// (profile / knowledge / state) and the active constitution, at the
  /// fork-evolution boundary (spec 12 §3 — Philosophy is the only axis that
  /// governs the others). Opt-in: only agents with an assigned philosophy
  /// are governed. Emits [AgentForkTensionDetectedEvent] when tensions are
  /// found; never throws into the caller (fail open). No-op when the adapter
  /// does not support `detectTensions`.
  Future<void> _detectForkTensions(String agentId) async {
    try {
      final philoRefs = await _registry.listOwned(agentId, AgentAxis.philosophy);
      if (philoRefs.isEmpty) return;
      final ks = _registry.knowledgeSystemRef();
      if (ks is! KnowledgeSystem || !ks.philosophy.isAvailable) return;

      final profileState = await _axisStateMap(agentId, AgentAxis.profile);
      final knowledgeProvenance = await _factsProvenance(agentId);
      final tensions = await ks.philosophy.detectTensions(MultiLayerContext(
        philosophyContext: PhilosophyEvaluationContext(
          contextId: 'fork:$agentId',
          profileState: profileState,
        ),
        profileState: profileState,
        knowledgeProvenance: knowledgeProvenance,
      ));
      if (tensions.isEmpty) return;

      _eventBus.emit(AgentForkTensionDetectedEvent(
        agentId: agentId,
        tensionCount: tensions.length,
        maxSeverity: _maxTensionSeverity(tensions),
        descriptions: tensions
            .take(_maxComposedAxisItems)
            .map((t) => t.description)
            .toList(),
        timestamp: DateTime.now(),
      ));
    } on UnsupportedError {
      // Adapter does not implement detectTensions — nothing to do.
    } catch (_) {
      // Fail open — tension detection is advisory, never breaks review.
    }
  }

  /// Merge an axis's assigned owned forks into a single state map (the
  /// shape `detectTensions` reasons over). Empty map when none assigned.
  Future<Map<String, dynamic>> _axisStateMap(
      String agentId, AgentAxis axis) async {
    final refs = await _registry.listOwned(agentId, axis);
    final state = <String, dynamic>{};
    for (final ref in refs) {
      final raw = await _registry.getOwned(agentId, axis, ref.forkedRef);
      final map = _payloadMap(_ownedPayload(raw));
      if (map != null) state.addAll(map);
    }
    return state;
  }

  /// Derive a knowledge-provenance signal from the agent's assigned facts —
  /// record count + average confidence — so the tension detector reasons
  /// over real signals rather than a placeholder.
  Future<Map<String, dynamic>> _factsProvenance(String agentId) async {
    final refs = await _registry.listOwned(agentId, AgentAxis.facts);
    var count = 0;
    var confidenceSum = 0.0;
    var confidenceN = 0;
    for (final ref in refs) {
      final payload =
          _ownedPayload(await _registry.getOwned(agentId, AgentAxis.facts, ref.forkedRef));
      if (payload is! List) continue;
      for (final fact in payload) {
        count++;
        final c = fact is FactRecord
            ? fact.confidence
            : (fact is Map ? (fact['confidence'] as num?)?.toDouble() : null);
        if (c != null) {
          confidenceSum += c;
          confidenceN++;
        }
      }
    }
    return <String, dynamic>{
      'record_count': count,
      if (confidenceN > 0) 'trust_score': confidenceSum / confidenceN,
    };
  }

  /// Highest [TensionSeverity] name among [tensions] (critical > high >
  /// medium > low). Returns `unknown` when the list is empty.
  String _maxTensionSeverity(List<Tension> tensions) {
    const order = <String>['unknown', 'low', 'medium', 'high', 'critical'];
    var best = 'unknown';
    for (final t in tensions) {
      final name = t.severity.name;
      if (order.indexOf(name) > order.indexOf(best)) best = name;
    }
    return best;
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────

  Future<void> shutdown() async {
    await _conversationStore.shutdown();
  }

  // ── Internals ──────────────────────────────────────────────────────────

  Future<List<ConversationTurn>> _safeLoadHistory(String agentId) async {
    try {
      return await _conversationStore.load(agentId);
    } on ConversationStoreUnavailableException {
      rethrow;
    } catch (e) {
      throw ConversationStoreUnavailableException(
        'failed to load history for agent \'$agentId\': $e',
      );
    }
  }

  /// Max assigned facts rendered into a prompt (budget guard).
  static const int _maxComposedFacts = 50;

  /// Render the agent's assigned FACTS (set via `assignFacts`) into a
  /// system-prompt section, or null when none are assigned.
  ///
  /// Facts are stored eager as `OwnedFork` envelopes under
  /// [AgentAxis.facts]; in-memory KV surfaces the live `OwnedFork`
  /// (payload = `List<FactRecord>`), persistent KV surfaces its JSON
  /// (`{'payload': [ {fact json} ]}`). Both are handled.
  Future<String?> _composeAssignedFacts(String agentId) async {
    final refs = await _registry.listOwned(agentId, AgentAxis.facts);
    if (refs.isEmpty) return null;
    final lines = <String>[];
    for (final ref in refs) {
      final raw =
          await _registry.getOwned(agentId, AgentAxis.facts, ref.forkedRef);
      final payload = _ownedPayload(raw);
      if (payload is! List) continue;
      for (final fact in payload) {
        final text = _factLine(fact);
        if (text != null && text.isNotEmpty) lines.add('- $text');
        if (lines.length >= _maxComposedFacts) break;
      }
      if (lines.length >= _maxComposedFacts) break;
    }
    if (lines.isEmpty) return null;
    return <String>['## Assigned knowledge (facts)', ...lines].join('\n');
  }

  /// Extract the payload list from a stored owned envelope (live
  /// `OwnedFork` or its JSON `Map`). Lazy envelopes have no resolved
  /// payload here and yield null.
  Object? _ownedPayload(Object? raw) {
    if (raw is OwnedFork) return raw.payload;
    if (raw is Map && raw['payload'] != null) return raw['payload'];
    return null;
  }

  /// One readable line for a fact (live `FactRecord` or its JSON `Map`).
  String? _factLine(Object? fact) {
    if (fact is FactRecord) return _factText(fact.type, fact.content);
    if (fact is Map) {
      final content = fact['content'];
      return _factText(
        fact['type'] as String?,
        content is Map ? content.cast<String, dynamic>() : null,
      );
    }
    return null;
  }

  String? _factText(String? type, Map<String, dynamic>? content) {
    if (content == null || content.isEmpty) return type;
    final v = content['value'] ??
        content['text'] ??
        content['statement'] ??
        content['body'];
    final body = v is String && v.isNotEmpty ? v : jsonEncode(content);
    return type != null && type.isNotEmpty ? '$type: $body' : body;
  }

  /// Max items rendered per non-facts axis (budget guard).
  static const int _maxComposedAxisItems = 20;

  /// Compose all 4 assigned axes into one system-prompt block, or null when
  /// none are assigned. Order: profile (persona) → philosophy (guardrails)
  /// → skill → facts. (spec 12 §2.)
  Future<String?> _composeAssignedAxes(String agentId) async {
    final sections = <String>[];
    final profile = await _composeAxis(
        agentId, AgentAxis.profile, 'Profile (persona / role)');
    if (profile != null) sections.add(profile);
    final philosophy = await _composeAxis(agentId, AgentAxis.philosophy,
        'Operating philosophy (values · prohibitions)');
    if (philosophy != null) sections.add(philosophy);
    final skill = await _composeAxis(agentId, AgentAxis.skill, 'Assigned skills');
    if (skill != null) sections.add(skill);
    final facts = await _composeAssignedFacts(agentId);
    if (facts != null) sections.add(facts);
    if (sections.isEmpty) return null;
    return sections.join('\n\n');
  }

  /// Render a non-facts axis's assigned owned forks into a labeled section.
  /// The payload is generic (a live domain object exposing `toJson`, or its
  /// JSON `Map`) — rendered defensively from readable fields so no hidden
  /// Knowledge-Subsystem domain type is imported here.
  Future<String?> _composeAxis(
      String agentId, AgentAxis axis, String label) async {
    final refs = await _registry.listOwned(agentId, axis);
    if (refs.isEmpty) return null;
    final lines = <String>[];
    for (final ref in refs) {
      final raw = await _registry.getOwned(agentId, axis, ref.forkedRef);
      final payload = _ownedPayload(raw);
      final text = _axisLine(payload) ?? ref.forkedRef;
      if (text.isNotEmpty) lines.add('- $text');
      if (lines.length >= _maxComposedAxisItems) break;
    }
    if (lines.isEmpty) return null;
    return <String>['## $label', ...lines].join('\n');
  }

  /// Best-effort one-line summary of a non-facts axis payload.
  String? _axisLine(Object? payload) {
    final map = _payloadMap(payload);
    if (map == null) return payload?.toString();
    final name = map['name'] ?? map['title'] ?? map['id'];
    final desc = map['description'] ??
        map['summary'] ??
        map['statement'] ??
        map['persona'] ??
        map['role'];
    final values = map['values'] ?? map['valuePriorities'];
    final prohibitions = map['prohibitions'];
    final parts = <String>[];
    if (name is String && name.isNotEmpty) parts.add(name);
    if (desc is String && desc.isNotEmpty) parts.add(desc);
    if (values != null) parts.add('values: ${_compact(values)}');
    if (prohibitions != null) parts.add('prohibitions: ${_compact(prohibitions)}');
    if (parts.isEmpty) return _compact(map);
    return parts.join(' — ');
  }

  /// Coerce a payload to a JSON map — directly if a `Map`, else via a
  /// best-effort `toJson()`. Returns null when neither applies.
  Map<String, dynamic>? _payloadMap(Object? payload) {
    if (payload is Map) return payload.cast<String, dynamic>();
    try {
      final json = (payload as dynamic).toJson();
      if (json is Map) return json.cast<String, dynamic>();
    } catch (_) {
      // Payload has no toJson — fall through to null (caller uses toString).
    }
    return null;
  }

  /// Compact, length-capped JSON for embedding a value in a prompt line.
  String _compact(Object? value) {
    final s = jsonEncode(value);
    return s.length > 200 ? '${s.substring(0, 200)}…' : s;
  }

  /// Apply the agent's assigned Philosophy to a generated output before
  /// delivery (spec 12 §3). No assigned philosophy or unavailable engine →
  /// returns [content] unchanged. A hard prohibition throws
  /// [AgentPhilosophyBlockedException]; soft modifications adjust the text.
  /// Fails open (returns [content]) on any engine error — a philosophy
  /// hiccup must not break an otherwise-good turn.
  Future<String> _interveneIfPhilosophy(String agentId, String content) async {
    final refs = await _registry.listOwned(agentId, AgentAxis.philosophy);
    if (refs.isEmpty) return content;
    final ks = _registry.knowledgeSystemRef();
    if (ks is! KnowledgeSystem) return content;
    if (!ks.philosophy.isAvailable) return content;
    try {
      final result = await ks.philosophy.intervene(
        InterventionPoint.postGeneration,
        PipelineContext(
          pipelineId: agentId,
          currentPoint: InterventionPoint.postGeneration,
          knowledgeRetrieved: const <String, dynamic>{},
          generatedOutput: content,
        ),
      );
      if (result.blocksDelivery) {
        throw AgentPhilosophyBlockedException(
          agentId: agentId,
          violationIds: result.prohibitionViolationIds,
        );
      }
      final adjusted = result.modifications?['output'];
      return adjusted is String && adjusted.isNotEmpty ? adjusted : content;
    } on AgentPhilosophyBlockedException {
      rethrow;
    } catch (_) {
      return content;
    }
  }

  List<LlmMessage> _buildMessages(
    List<ConversationTurn> history,
    String userMessage,
    Map<String, Object?>? context,
  ) {
    final messages = <LlmMessage>[];
    for (final turn in history) {
      messages.add(LlmMessage(role: 'user', content: turn.userMessage));
      messages.add(
          LlmMessage(role: 'assistant', content: turn.assistantReply));
    }
    final framedUser = context == null || context.isEmpty
        ? userMessage
        : '$userMessage\n\n[context: $context]';
    messages.add(LlmMessage(role: 'user', content: framedUser));
    return messages;
  }

  Future<List<Agent>> _resolveCandidates(List<String> ids) async {
    final result = <Agent>[];
    for (final id in ids) {
      final agent = await _registry.get(id);
      if (agent != null) result.add(agent);
    }
    return result;
  }
}
