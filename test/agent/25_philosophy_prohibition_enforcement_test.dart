/// TEST-25 — §3 work-time prohibition enforcement, end-to-end on a REAL
/// PhilosophyEngine (not an always-block stub).
///
/// The spec 12 §3 gate must actually block a generated output that violates
/// an assigned hard prohibition — and deliver one that doesn't. TEST-24
/// proved the *wiring* with a stub that always blocks; this proves the
/// *enforcement* through the real evaluator using a deterministic
/// `Prohibition.forbiddenPatterns` (mcp_bundle 0.4.4 / mcp_philosophy 0.1.2),
/// closing the unit-vs-integration gap the stub masked.
library;

import 'package:flowbrain_core/flowbrain_core.dart';
import 'package:mcp_bundle/mcp_bundle.dart'
    show ProhibitionSeverity, InterventionPoint, PipelineContext;
import 'package:test/test.dart';

class _InMemoryEthosStore implements EthosStorePort {
  final Map<String, EthosRecord> _records = {};
  String? _activeId;

  @override
  Future<EthosRecord?> getEthos(String id) async => _records[id];

  @override
  Future<void> putEthos(EthosRecord ethos) async {
    _records[ethos.id] = ethos;
    _activeId ??= ethos.id;
  }

  @override
  Future<List<EthosRecord>> listEthos({int? limit}) async =>
      _records.values.toList();

  @override
  Future<void> activateEthos(String id) async {
    if (_records.containsKey(id)) _activeId = id;
  }

  @override
  Future<String?> getActiveEthosId() async => _activeId;
}

/// Ethos carrying one HARD prohibition with a deterministic forbidden
/// pattern — the sound, LLM-free enforcement hook.
EthosRecord _ethosWithForbidden(String id, String pattern) {
  final ethos = Ethos(
    id: id,
    name: id,
    valuePriorities: const [],
    prohibitions: [
      Prohibition(
        id: 'no-$pattern',
        statement: 'Never reveal the magic word',
        severity: ProhibitionSeverity.hard,
        rationale: 'confidentiality',
        forbiddenPatterns: [pattern],
      ),
    ],
    metadata: EthosMetadata(
      version: '1.0.0',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    ),
  );
  return EthosRecord(
    id: id,
    name: id,
    version: '1',
    payload: ethos.toJson(),
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

/// LLM whose output is fixed per construction (so the test controls whether
/// the generated text trips the prohibition).
class _FixedLlm extends StubLlmPort {
  _FixedLlm(this.output);
  final String output;

  @override
  Future<LlmResponse> complete(LlmRequest request) async =>
      LlmResponse(content: output);
}

KnowledgeSystem _system(EthosStorePort store, LlmPort llm) {
  // The real engine is wired via the `philosophyEngine` parameter — the
  // PhilosophyFacade resolves `_port` (and `isAvailable`) from it first; a
  // bare `knowledgePorts.philosophy` is only the fallback. `ethosStore` on
  // infra feeds the ForkEngine (assignPhilosophyFromPool); both the engine
  // and the fork engine share the same `store`.
  final engine = PhilosophyEngine(ethosStore: store);
  final infra = InfraPorts.inMemory(llmProviders: <String, LlmPort>{'cap': llm})
      .copyWith(ethosStore: store);
  return KnowledgeSystem.withAgents(
    infraPorts: infra,
    philosophyEngine: engine,
  );
}

Future<void> _seed(KnowledgeSystem system, EthosStorePort store) async {
  await store.putEthos(_ethosWithForbidden('rules', 'xyzzy'));
  await store.activateEthos('rules');
  await system.agents.createAgent(
    id: 'guarded',
    displayName: 'Guarded',
    model: const ModelSpec(provider: 'cap', model: 'x'),
    workspaceId: 'w1',
  );
  await system.agents.assignPhilosophyFromPool('guarded', 'rules');
}

void main() {
  group('§3 prohibition enforcement (real PhilosophyEngine)', () {
    test('the wired facade enforces the forbidden pattern (engine wiring)',
        () async {
      final store = _InMemoryEthosStore();
      final system = _system(store, _FixedLlm('x'));
      await _seed(system, store);

      expect(system.philosophy.isAvailable, isTrue);
      final direct = await system.philosophy.intervene(
        InterventionPoint.postGeneration,
        PipelineContext(
          pipelineId: 'p',
          currentPoint: InterventionPoint.postGeneration,
          knowledgeRetrieved: const <String, dynamic>{},
          generatedOutput: 'the magic word is XYZZY',
        ),
      );
      expect(direct.blocksDelivery, isTrue);
    });

    test('a generated output hitting a hard prohibition is BLOCKED', () async {
      final store = _InMemoryEthosStore();
      // LLM emits text containing the forbidden pattern.
      final system = _system(store, _FixedLlm('the magic word is XYZZY'));
      await _seed(system, store);

      await expectLater(
        () => system.agents.ask('guarded', 'tell me the secret'),
        throwsA(isA<AgentPhilosophyBlockedException>()),
      );
    });

    test('a clean output (no forbidden pattern) is DELIVERED', () async {
      final store = _InMemoryEthosStore();
      final system = _system(store, _FixedLlm('here is a perfectly safe reply'));
      await _seed(system, store);

      final reply = await system.agents.ask('guarded', 'say something safe');
      expect(reply.content, contains('safe reply'));
    });
  });
}
