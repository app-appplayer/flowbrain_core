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
    show FactRecord, LlmPort, LlmRequest, LlmMessage, LlmTool;
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

    // Compose the agent's assigned knowledge (facts) into the system
    // prompt so the provider actually sees it. Base persona first, then
    // the assigned-knowledge section. No assigned facts → base only.
    final assignedFacts = await _composeAssignedFacts(agentId);
    final base = agent.systemPrompt;
    final effectiveSystemPrompt = assignedFacts == null
        ? base
        : (base == null || base.isEmpty
            ? assignedFacts
            : '$base\n\n$assignedFacts');

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
    return result;
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
