/// TEST-22 — Multi-ethos workspace fork (per-id philosophy).
///
/// Verifies the [EthosStorePort] wired through `KnowledgeSystem.ethosStore`
/// gives `ForkEngine` per-id ethos resolution. Without the store
/// `assignPhilosophyFromPool('any')` would always return the single
/// active ethos of `PhilosophyFacade`; with it, each agent can be
/// seeded from a different ethos record on the same workspace.
library;

import 'package:flowbrain_core/flowbrain_core.dart';
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
  Future<List<EthosRecord>> listEthos({int? limit}) async {
    final out = _records.values.toList();
    if (limit != null && out.length > limit) {
      return out.sublist(0, limit);
    }
    return out;
  }

  @override
  Future<void> activateEthos(String id) async {
    if (_records.containsKey(id)) _activeId = id;
  }

  @override
  Future<String?> getActiveEthosId() async => _activeId;
}

EthosRecord _ethosRecord(String id, {String? name}) {
  final ethos = Ethos(
    id: id,
    name: name ?? id,
    valuePriorities: const [],
    prohibitions: const [],
    metadata: EthosMetadata(
      version: '1.0.0',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    ),
  );
  return EthosRecord(
    id: id,
    name: ethos.name,
    version: '1',
    payload: ethos.toJson(),
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

KnowledgeSystem _build({EthosStorePort? store}) {
  final infra = InfraPorts.inMemory().copyWith(
    llm: StubLlmPort(),
    mcp: const StubMcpPort(),
    ethosStore: store,
  );
  final eventBus = KnowledgeEventBus();

  final skillRuntime = SkillRuntime(
    registry: MemorySkillRegistry(),
    ports: SkillPorts(llm: StubLlmPort(), mcp: const StubMcpPort()),
  );
  final philosophyEngine = PhilosophyEngine(
    ethosStore: store ?? const StubEthosStorePort(),
  );

  late final KnowledgeSystem system;
  final subsystem = AgentSubsystem.create(
    knowledgeSystemRef: () => system,
    infraPorts: infra,
    eventBus: eventBus,
    config: AgentConfig.defaults,
  );
  system = KnowledgeSystem(
    config: KnowledgeConfig.defaults,
    infraPorts: infra,
    skillRuntime: skillRuntime,
    philosophyEngine: philosophyEngine,
    agentRegistry: subsystem.registry,
    agentRuntime: subsystem.runtime,
    eventBus: eventBus,
  );
  return system;
}

void main() {
  group('Multi-ethos workspace — per-id philosophy fork', () {
    test('T-AGT-ETHOS-001 — listIntegrated enumerates every store entry',
        () async {
      final store = _InMemoryEthosStore();
      await store.putEthos(_ethosRecord('ads-core'));
      await store.putEthos(_ethosRecord('editorial-core'));
      final system = _build(store: store);

      final entries =
          await system.agents.listIntegrated('w1', AgentAxis.philosophy);
      final pool = entries.where((e) => e.isPool).toList();

      expect(pool.length, 2);
      final ids = pool.map((e) => e.source.encode()).toSet();
      expect(ids, containsAll([
        'pool:ads-core',
        'pool:editorial-core',
      ]));
    });

    test('T-AGT-ETHOS-002 — different agents fork different ethos by id',
        () async {
      final store = _InMemoryEthosStore();
      await store.putEthos(_ethosRecord('ads-core', name: 'Ads'));
      await store.putEthos(
        _ethosRecord('editorial-core', name: 'Editorial'),
      );
      final system = _build(store: store);

      await system.agents.createAgent(
        id: 'ads_ops',
        displayName: 'ads_ops',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      await system.agents.createAgent(
        id: 'editor',
        displayName: 'editor',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );

      await system.agents.assignPhilosophyFromPool('ads_ops', 'ads-core');
      await system.agents
          .assignPhilosophyFromPool('editor', 'editorial-core');

      // Each agent's owned philosophy fork derives from a distinct
      // ethos id — surfaces in listIntegrated as agent-owned entries
      // whose lineage chain points at different pool seeds.
      final entries =
          await system.agents.listIntegrated('w1', AgentAxis.philosophy);
      final owned = entries.where((e) => e.isAgentOwned).toList();
      expect(owned.length, 2);
      final lineageById = {
        for (final e in owned) e.ownerAgentId: e.lineage.first,
      };
      expect(lineageById['ads_ops'], 'pool:ads-core');
      expect(lineageById['editor'], 'pool:editorial-core');
    });

    test(
      'T-AGT-ETHOS-003 — store miss falls back to active ethos',
      () async {
        final store = _InMemoryEthosStore();
        await store.putEthos(_ethosRecord('ads-core'));
        final system = _build(store: store);

        await system.agents.createAgent(
          id: 'a1',
          displayName: 'a1',
          model: ModelSpec.stub(),
          workspaceId: 'w1',
        );

        // Unknown id — payload should not throw; fallback to active
        // ethos resolution path keeps the assignment best-effort.
        await system.agents.assignPhilosophyFromPool('a1', 'unknown-ethos');
        // No exception means the fallback path worked. The owned
        // entry is still recorded with the requested poolId so the
        // operator can see what they asked for in lineage.
        final entries =
            await system.agents.listIntegrated('w1', AgentAxis.philosophy);
        final owned = entries.firstWhere((e) => e.isAgentOwned);
        expect(owned.lineage.first, 'pool:unknown-ethos');
      },
    );
  });
}
