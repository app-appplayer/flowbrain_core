/// Knowledge-first LLM adapter implementing 4-tier escalation.
///
/// Wraps an inner [LlmPort] and intercepts `complete()` calls:
///
///   1. Query knowledge (Facts, Summaries, Patterns) in parallel.
///   2. Aggregate confidence and classify via [EscalationPolicy].
///   3. Dispatch:
///      - **Tier.hit**     — deterministic template response (0 LLM calls).
///      - **Tier.partial** — cheap model + injected knowledge context.
///      - **Tier.miss**    — primary model; response stored via learning loop.
///   4. On any failure    — propagate error + emit KflEscalationEvent(failed).
library;

import 'dart:async';

import 'package:logging/logging.dart';
import 'package:mcp_bundle/mcp_bundle.dart'
    show
        LlmPort,
        LlmRequest,
        LlmResponse,
        LlmCapabilities,
        LlmChunk,
        FactsPort,
        FactRecord,
        FactQuery,
        PatternsPort,
        PatternRecord,
        PatternQuery,
        SummariesPort,
        SummaryRecord,
        CandidatesPort,
        MetricPort;
import 'package:mcp_knowledge/mcp_knowledge.dart' show KnowledgeEventBus;

import '../../events/flowbrain_events.dart';
import 'escalation_policy.dart';
import 'learning_loop.dart';

final _log = Logger('flowbrain.kfl.adapter');

/// Aggregated knowledge retrieved from the three knowledge ports.
class KnowledgeBundle {
  /// Best-matching facts.
  final List<FactRecord> facts;

  /// Best-matching summary (may be null).
  final SummaryRecord? summary;

  /// Best-matching patterns.
  final List<PatternRecord> patterns;

  /// Aggregated confidence score across all sources.
  final double confidence;

  const KnowledgeBundle({
    this.facts = const [],
    this.summary,
    this.patterns = const [],
    required this.confidence,
  });
}

/// Decorator over [LlmPort] that queries knowledge before calling the LLM.
class KnowledgeFirstLlmAdapter extends LlmPort {
  /// Inner LLM to delegate to when knowledge is insufficient.
  final LlmPort innerLlm;

  /// Optional fact store.
  final FactsPort? facts;

  /// Optional pattern store.
  final PatternsPort? patterns;

  /// Optional summary store.
  final SummariesPort? summaries;

  /// Optional candidate store for learning loop.
  final CandidatesPort? candidates;

  /// Optional metric sink.
  final MetricPort? metrics;

  /// Escalation thresholds and model configuration.
  final EscalationPolicy policy;

  /// Optional event bus for escalation events.
  final KnowledgeEventBus? eventBus;

  /// Internal learning loop instance.
  late final LearningLoop _learningLoop;

  KnowledgeFirstLlmAdapter({
    required this.innerLlm,
    this.facts,
    this.patterns,
    this.summaries,
    this.candidates,
    this.metrics,
    required this.policy,
    this.eventBus,
  }) {
    _learningLoop = LearningLoop(candidates: candidates);
  }

  @override
  LlmCapabilities get capabilities => innerLlm.capabilities;

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    // Straight-through when no knowledge ports are configured.
    if (facts == null && patterns == null && summaries == null) {
      return innerLlm.complete(request);
    }

    final prompt = request.effectivePrompt;
    final knowledge = await _queryKnowledge(prompt);
    final tier = policy.classify(knowledge.confidence);

    _emitEscalation(tier, knowledge);

    try {
      switch (tier) {
        case Tier.hit:
          return _buildTemplateResponse(knowledge);
        case Tier.partial:
          return await _callCheap(request, knowledge);
        case Tier.miss:
          return await _callPrimary(request, knowledge);
      }
    } catch (e) {
      _emitEscalation(Tier.miss, knowledge, failed: true);
      rethrow;
    }
  }

  @override
  Stream<LlmChunk> completeStream(LlmRequest request) {
    return innerLlm.completeStream(request);
  }

  @override
  Future<List<double>> embed(String text) => innerLlm.embed(text);

  // ---------------------------------------------------------------------------
  // Knowledge query
  // ---------------------------------------------------------------------------

  /// Query all available knowledge ports in parallel and aggregate confidence.
  Future<KnowledgeBundle> _queryKnowledge(String prompt) async {
    List<FactRecord> factResults = [];
    SummaryRecord? summaryResult;
    List<PatternRecord> patternResults = [];

    final futures = <Future<void>>[];

    if (facts != null) {
      futures.add(
        facts!
            .queryFacts(const FactQuery(workspaceId: 'default', limit: 5))
            .then((r) => factResults = r)
            .catchError((Object e) {
          _log.warning('Facts query failed, continuing: $e');
          return factResults;
        }),
      );
    }

    if (summaries != null) {
      futures.add(
        summaries!
            .getSummary('default', 'general')
            .then((r) => summaryResult = r)
            .catchError((Object e) {
          _log.warning('Summaries query failed, continuing: $e');
          return summaryResult;
        }),
      );
    }

    if (patterns != null) {
      futures.add(
        patterns!
            .queryPatterns(const PatternQuery(workspaceId: 'default', limit: 5))
            .then((r) => patternResults = r)
            .catchError((Object e) {
          _log.warning('Patterns query failed, continuing: $e');
          return patternResults;
        }),
      );
    }

    await Future.wait(futures);

    final confidence = _aggregateConfidence(
      factResults,
      summaryResult,
      patternResults,
    );

    return KnowledgeBundle(
      facts: factResults,
      summary: summaryResult,
      patterns: patternResults,
      confidence: confidence,
    );
  }

  /// Combine confidence from all knowledge sources into one score.
  double _aggregateConfidence(
    List<FactRecord> factResults,
    SummaryRecord? summaryResult,
    List<PatternRecord> patternResults,
  ) {
    double total = 0;
    int count = 0;

    for (final f in factResults) {
      if (f.confidence != null) {
        total += f.confidence!;
        count++;
      }
    }

    if (summaryResult != null) {
      total += summaryResult.confidence;
      count++;
    }

    for (final p in patternResults) {
      total += p.confidence;
      count++;
    }

    if (count == 0) return 0.0;
    return total / count;
  }

  // ---------------------------------------------------------------------------
  // Tier dispatchers
  // ---------------------------------------------------------------------------

  /// Tier.hit — build a deterministic template response from knowledge.
  LlmResponse _buildTemplateResponse(KnowledgeBundle knowledge) {
    final parts = <String>[];

    for (final f in knowledge.facts) {
      final text = f.content['text'];
      if (text is String && text.isNotEmpty) {
        parts.add(text);
      }
    }

    if (knowledge.summary != null && knowledge.summary!.content.isNotEmpty) {
      parts.add(knowledge.summary!.content);
    }

    final content =
        parts.isNotEmpty ? parts.join('\n\n') : 'No detailed information found.';

    return LlmResponse(
      content: content,
      metadata: {
        'source': 'kfl.template',
        'confidence': knowledge.confidence,
        'tier': 'hit',
      },
    );
  }

  /// Tier.partial — call cheap model with knowledge context injected.
  Future<LlmResponse> _callCheap(
    LlmRequest request,
    KnowledgeBundle knowledge,
  ) async {
    final enrichedRequest = LlmRequest(
      prompt: request.prompt,
      messages: request.messages,
      systemPrompt: _buildKnowledgeContext(knowledge, request.systemPrompt),
      model: policy.cheapModel,
      temperature: request.temperature,
      maxTokens: request.maxTokens,
      responseFormat: request.responseFormat,
      tools: request.tools,
      options: request.options,
    );

    return innerLlm.complete(enrichedRequest);
  }

  /// Tier.miss — call primary model; store response in learning loop.
  Future<LlmResponse> _callPrimary(
    LlmRequest request,
    KnowledgeBundle knowledge,
  ) async {
    final enrichedRequest = LlmRequest(
      prompt: request.prompt,
      messages: request.messages,
      systemPrompt: request.systemPrompt,
      model: policy.primaryModel,
      temperature: request.temperature,
      maxTokens: request.maxTokens,
      responseFormat: request.responseFormat,
      tools: request.tools,
      options: request.options,
    );

    final response = await innerLlm.complete(enrichedRequest);

    if (policy.learningEnabled) {
      await _learningLoop.store(
        prompt: request.effectivePrompt,
        response: response,
      );
    }

    return response;
  }

  /// Build a system prompt enriched with knowledge context.
  String _buildKnowledgeContext(KnowledgeBundle k, String? existingSystem) {
    final buffer = StringBuffer();

    if (existingSystem != null && existingSystem.isNotEmpty) {
      buffer.writeln(existingSystem);
      buffer.writeln();
    }

    buffer.writeln('--- Knowledge Context ---');

    for (final f in k.facts) {
      final text = f.content['text'];
      if (text is String) {
        buffer.writeln('Fact: $text');
      }
    }

    if (k.summary != null && k.summary!.content.isNotEmpty) {
      buffer.writeln('Summary: ${k.summary!.content}');
    }

    for (final p in k.patterns) {
      buffer.writeln('Pattern: ${p.description}');
    }

    return buffer.toString();
  }

  // ---------------------------------------------------------------------------
  // Metrics and events
  // ---------------------------------------------------------------------------

  /// Emit tier-level metrics and an escalation event.
  void _emitEscalation(
    Tier tier,
    KnowledgeBundle knowledge, {
    bool failed = false,
  }) {
    // Record tier counter metric.
    final tierName = tier.name;
    metrics?.record(
      'flowbrain.llm.tier.$tierName.count',
      1.0,
      tags: {'tier': tierName},
    );

    // Emit escalation event to bus.
    eventBus?.emit(KflEscalationEvent(
      tier: tierName,
      confidence: knowledge.confidence,
      failed: failed,
      timestamp: DateTime.now(),
    ));
  }
}
