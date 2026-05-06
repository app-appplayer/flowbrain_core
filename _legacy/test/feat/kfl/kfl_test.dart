import 'package:test/test.dart';
import 'package:mcp_bundle/mcp_bundle.dart'
    show
        LlmPort,
        LlmRequest,
        LlmResponse,
        LlmUsage,
        LlmCapabilities,
        FactRecord,
        FactQuery,
        SummaryRecord,
        CandidateRecord,
        StubMetricPort,
        StubFactsPort,
        StubSummariesPort,
        StubCandidatesPort;
import 'package:mcp_knowledge/mcp_knowledge.dart' show KnowledgeEventBus;

import 'package:flowbrain_core/src/feat/kfl/escalation_policy.dart';
import 'package:flowbrain_core/src/feat/kfl/knowledge_first_llm_adapter.dart';
import 'package:flowbrain_core/src/feat/kfl/learning_loop.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// LlmPort that records calls and returns configurable responses.
class _MockLlmPort extends LlmPort {
  final List<LlmRequest> calls = [];
  LlmResponse nextResponse;

  _MockLlmPort({LlmResponse? response})
      : nextResponse = response ??
            const LlmResponse(
              content: 'mock response',
              usage: LlmUsage(inputTokens: 10, outputTokens: 20),
              model: 'test-model',
            );

  @override
  LlmCapabilities get capabilities => const LlmCapabilities.minimal();

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    calls.add(request);
    return nextResponse;
  }
}

/// FactsPort that returns configurable results with confidence.
class _ConfidentFactsPort extends StubFactsPort {
  final List<FactRecord> results;
  const _ConfidentFactsPort(this.results);

  @override
  Future<List<FactRecord>> queryFacts(FactQuery query) async => results;
}

/// SummariesPort that returns a configurable summary.
class _ConfidentSummariesPort extends StubSummariesPort {
  final SummaryRecord? result;
  const _ConfidentSummariesPort(this.result);

  @override
  Future<SummaryRecord?> getSummary(
    String entityId,
    String summaryType, {
    period,
  }) async =>
      result;
}

/// CandidatesPort that records stored candidates.
class _RecordingCandidatesPort extends StubCandidatesPort {
  final List<CandidateRecord> stored = [];

  @override
  Future<List<String>> createCandidates(
    List<CandidateRecord> candidates,
  ) async {
    stored.addAll(candidates);
    return candidates.map((c) => c.id).toList();
  }
}

/// MetricPort that records emitted metrics.
class _RecordingMetricPort extends StubMetricPort {
  final List<({String name, double value, Map<String, String>? tags})>
      recorded = [];

  @override
  Future<void> record(
    String metricName,
    double value, {
    Map<String, String>? tags,
  }) async {
    recorded.add((name: metricName, value: value, tags: tags));
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('EscalationPolicy', () {
    test('default thresholds: hit=0.85, partial=0.5', () {
      final policy = EscalationPolicy();
      expect(policy.hitThreshold, 0.85);
      expect(policy.partialThreshold, 0.5);
    });

    test('classify returns Tier.hit when confidence >= hitThreshold', () {
      final policy = EscalationPolicy();
      expect(policy.classify(0.85), Tier.hit);
      expect(policy.classify(0.90), Tier.hit);
      expect(policy.classify(1.0), Tier.hit);
    });

    test('classify returns Tier.partial when confidence >= partialThreshold',
        () {
      final policy = EscalationPolicy();
      expect(policy.classify(0.5), Tier.partial);
      expect(policy.classify(0.7), Tier.partial);
      expect(policy.classify(0.84), Tier.partial);
    });

    test('classify returns Tier.miss when confidence < partialThreshold', () {
      final policy = EscalationPolicy();
      expect(policy.classify(0.0), Tier.miss);
      expect(policy.classify(0.3), Tier.miss);
      expect(policy.classify(0.49), Tier.miss);
    });

    test('custom thresholds are respected', () {
      final policy = EscalationPolicy(
        hitThreshold: 0.9,
        partialThreshold: 0.6,
      );
      expect(policy.classify(0.85), Tier.partial);
      expect(policy.classify(0.55), Tier.miss);
      expect(policy.classify(0.95), Tier.hit);
    });
  });

  group('KnowledgeFirstLlmAdapter', () {
    test('null ports → straight-through to inner LLM', () async {
      final inner = _MockLlmPort();
      final adapter = KnowledgeFirstLlmAdapter(
        innerLlm: inner,
        policy: EscalationPolicy(),
      );

      final request = LlmRequest.simple('hello');
      final response = await adapter.complete(request);

      expect(response.content, 'mock response');
      expect(inner.calls.length, 1);
    });

    test('high confidence → Tier.hit, no LLM call', () async {
      final inner = _MockLlmPort();
      final facts = _ConfidentFactsPort([
        FactRecord(
          id: 'f1',
          workspaceId: 'default',
          type: 'general',
          content: {'text': 'The answer is 42'},
          confidence: 0.95,
          createdAt: DateTime.now(),
        ),
      ]);
      final summaries = _ConfidentSummariesPort(
        SummaryRecord(
          id: 's1',
          entityId: 'default',
          type: 'general',
          content: 'Summary of knowledge',
          confidence: 0.9,
          createdAt: DateTime.now(),
        ),
      );

      final adapter = KnowledgeFirstLlmAdapter(
        innerLlm: inner,
        facts: facts,
        summaries: summaries,
        policy: EscalationPolicy(),
      );

      final response = await adapter.complete(LlmRequest.simple('question'));

      // No LLM calls — template response used
      expect(inner.calls.length, 0);
      expect(response.content, isNotEmpty);
      expect(response.metadata?['source'], 'kfl.template');
    });

    test('low confidence → Tier.miss, calls primary LLM', () async {
      final inner = _MockLlmPort();
      final facts = _ConfidentFactsPort([]); // No facts → low confidence
      final adapter = KnowledgeFirstLlmAdapter(
        innerLlm: inner,
        facts: facts,
        policy: EscalationPolicy(),
      );

      final response = await adapter.complete(LlmRequest.simple('question'));

      expect(inner.calls.length, 1);
      expect(response.content, 'mock response');
    });

    test('medium confidence → Tier.partial, calls cheap model', () async {
      final inner = _MockLlmPort();
      final facts = _ConfidentFactsPort([
        FactRecord(
          id: 'f1',
          workspaceId: 'default',
          type: 'general',
          content: {'text': 'partial info'},
          confidence: 0.6,
          createdAt: DateTime.now(),
        ),
      ]);

      final policy = EscalationPolicy(
        cheapModel: 'cheap-model',
        primaryModel: 'primary-model',
      );

      final adapter = KnowledgeFirstLlmAdapter(
        innerLlm: inner,
        facts: facts,
        policy: policy,
      );

      final response = await adapter.complete(LlmRequest.simple('question'));

      expect(inner.calls.length, 1);
      // The request should target the cheap model
      expect(inner.calls.first.model, 'cheap-model');
      expect(response.content, 'mock response');
    });

    test('learning on miss — stores to CandidatesPort', () async {
      final inner = _MockLlmPort();
      final facts = _ConfidentFactsPort([]);
      final candidates = _RecordingCandidatesPort();

      final adapter = KnowledgeFirstLlmAdapter(
        innerLlm: inner,
        facts: facts,
        candidates: candidates,
        policy: EscalationPolicy(),
      );

      await adapter.complete(LlmRequest.simple('learn this'));

      expect(candidates.stored.length, 1);
      expect(candidates.stored.first.content['text'], 'mock response');
    });

    test('metric emission on each tier', () async {
      final inner = _MockLlmPort();
      final facts = _ConfidentFactsPort([]);
      final metrics = _RecordingMetricPort();

      final adapter = KnowledgeFirstLlmAdapter(
        innerLlm: inner,
        facts: facts,
        metrics: metrics,
        policy: EscalationPolicy(),
      );

      await adapter.complete(LlmRequest.simple('test'));

      // Should have emitted tier count metric
      final tierMetrics = metrics.recorded
          .where((m) => m.name.startsWith('flowbrain.llm.tier.'));
      expect(tierMetrics, isNotEmpty);
    });

    test('capabilities delegated from innerLlm', () {
      final inner = _MockLlmPort();
      final adapter = KnowledgeFirstLlmAdapter(
        innerLlm: inner,
        policy: EscalationPolicy(),
      );
      expect(adapter.capabilities, inner.capabilities);
    });

    test('KflEscalationEvent emitted on miss when eventBus present', () async {
      final inner = _MockLlmPort();
      final facts = _ConfidentFactsPort([]);
      final eventBus = KnowledgeEventBus();
      final events = <Object>[];
      eventBus.stream.listen(events.add);

      final adapter = KnowledgeFirstLlmAdapter(
        innerLlm: inner,
        facts: facts,
        policy: EscalationPolicy(),
        eventBus: eventBus,
      );

      await adapter.complete(LlmRequest.simple('test'));
      // Allow stream to propagate
      await Future<void>.delayed(Duration.zero);

      expect(events, isNotEmpty);
      await eventBus.close();
    });
  });

  group('LearningLoop', () {
    test('stores LLM response as CandidateRecord', () async {
      final candidates = _RecordingCandidatesPort();
      final loop = LearningLoop(candidates: candidates);

      final response = LlmResponse(
        content: 'learned content',
        usage: const LlmUsage(inputTokens: 5, outputTokens: 10),
        model: 'test-model',
      );

      await loop.store(
        prompt: 'what is X',
        response: response,
        workspaceId: 'ws1',
      );

      expect(candidates.stored.length, 1);
      expect(candidates.stored.first.workspaceId, 'ws1');
      expect(candidates.stored.first.content['text'], 'learned content');
    });

    test('no-op when candidates port is null', () async {
      final loop = LearningLoop();
      // Should not throw
      await loop.store(
        prompt: 'test',
        response: const LlmResponse(content: 'ok'),
      );
    });
  });
}
