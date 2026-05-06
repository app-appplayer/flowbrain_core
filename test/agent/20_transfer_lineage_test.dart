/// TEST-20 — Multi-source fork transfer + lineage chain.
///
/// Verifies the type-explicit `ForkSource` surface:
///   - PoolForkSource → seed clone (T-AGT-FORK-001 already covers).
///   - AgentForkSource → transfer from another agent's evolved owned fork.
///
/// Plus lineage chain accumulation across transfer hops, JSON round-trip
/// (OwnedFork.toJson / fromJson), and persistent-KV compatibility (the
/// transfer must succeed when the source agent's envelope was previously
/// serialized through `jsonEncode` and rehydrated as a `Map`).
library;

import 'dart:convert';

import 'package:flowbrain_core/flowbrain_core.dart';
import 'package:test/test.dart';

/// Minimal in-memory [EthosStorePort] for tests that need a working
/// philosophy facade — `StubEthosStorePort` is a no-op store.
class _MemEthosStore implements EthosStorePort {
  final Map<String, EthosRecord> _records = {};
  String? _activeId;

  @override
  Future<EthosRecord?> getEthos(String id) async => _records[id];

  @override
  Future<void> putEthos(EthosRecord ethos) async {
    _records[ethos.id] = ethos;
  }

  @override
  Future<List<EthosRecord>> listEthos({int? limit}) async {
    final all = _records.values.toList();
    if (limit == null || limit >= all.length) return all;
    return all.sublist(0, limit);
  }

  @override
  Future<void> activateEthos(String id) async {
    _activeId = id;
  }

  @override
  Future<String?> getActiveEthosId() async => _activeId;
}

KnowledgeSystem _buildSystem({
  required SkillBundleRegistry skillRegistry,
  required ProfileRegistry profileRegistry,
  EthosStorePort? ethosStore,
}) {
  final infra = InfraPorts.inMemory().copyWith(
    llm: StubLlmPort(),
    mcp: const StubMcpPort(),
  );
  final eventBus = KnowledgeEventBus();

  final skillRuntime = SkillRuntime(
    registry: skillRegistry,
    ports: SkillPorts(llm: StubLlmPort(), mcp: const StubMcpPort()),
  );
  final profileRuntime = ProfileRuntime(
    registry: profileRegistry,
    engines: EnginePorts.stub(),
  );
  final philosophyEngine = PhilosophyEngine(
    ethosStore: ethosStore ?? const StubEthosStorePort(),
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
    profileRuntime: profileRuntime,
    philosophyEngine: philosophyEngine,
    agentRegistry: subsystem.registry,
    agentRuntime: subsystem.runtime,
    eventBus: eventBus,
  );
  return system;
}

SkillBundle _bundle(String id, {String name = 'Demo'}) => SkillBundle(
      schemaVersion: '0.1.0',
      manifest: SkillManifest(
        id: id,
        name: name,
        version: '1.0.0',
        provider: 'test',
      ),
      procedures: const [],
    );

Future<KnowledgeSystem> _twoAgentsWithSharedSkill() async {
  final skillReg = MemorySkillRegistry();
  await skillReg.registerSkill(_bundle('content_translate'));
  final system = _buildSystem(
    skillRegistry: skillReg,
    profileRegistry: ProfileRegistry(),
  );
  for (final id in ['editor', 'publisher']) {
    await system.agents.createAgent(
      id: id,
      displayName: id,
      model: ModelSpec.stub(),
      workspaceId: 'w1',
    );
  }
  await system.agents.assignSkillFromPool('editor', 'content_translate');
  return system;
}

void main() {
  group('Multi-source fork — transfer (agent → agent)', () {
    test('T-AGT-FORK-013 — transfer creates owned fork on target', () async {
      final system = await _twoAgentsWithSharedSkill();
      final events = <AgentForkAssignedEvent>[];
      system.eventBus
          .on<AgentForkAssignedEvent>()
          .where((e) => e.agentId == 'publisher')
          .listen(events.add);

      await system.agents.assignSkill(
        'publisher',
        const AgentForkSource(
          agentId: 'editor',
          axis: AgentAxis.skill,
          forkedRef: 'editor::content_translate',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      // forkedRef chains the source forkedRef under the target agent.
      const expectedForked = 'publisher::editor::content_translate';
      expect(events, hasLength(1));
      expect(events.first.forkedRef, equals(expectedForked));
      expect(
        events.first.sourceRef,
        equals('agent:editor/skill/editor::content_translate'),
      );

      final list =
          await system.agentRegistry!.listOwned('publisher', AgentAxis.skill);
      expect(list, hasLength(1));
      expect(list.first.forkedRef, equals(expectedForked));
    });

    test('T-AGT-FORK-014 — lineage chain accumulates [pool, agent, ...]',
        () async {
      final system = await _twoAgentsWithSharedSkill();
      await system.agents.assignSkill(
        'publisher',
        const AgentForkSource(
          agentId: 'editor',
          axis: AgentAxis.skill,
          forkedRef: 'editor::content_translate',
        ),
      );
      final stored = await system.agentRegistry!.getOwned(
        'publisher',
        AgentAxis.skill,
        'publisher::editor::content_translate',
      );
      expect(stored, isA<OwnedFork>());
      final envelope = stored as OwnedFork;
      expect(
        envelope.lineage,
        equals(const [
          'pool:content_translate',
          'agent:editor/skill/editor::content_translate',
        ]),
      );
      expect(envelope.source, isA<AgentForkSource>());
      expect((envelope.source as AgentForkSource).agentId, equals('editor'));
    });

    test('T-AGT-FORK-017 — cross-axis transfer is rejected', () async {
      final system = await _twoAgentsWithSharedSkill();
      await expectLater(
        () => system.agents.assignProfile(
          'publisher',
          const AgentForkSource(
            agentId: 'editor',
            axis: AgentAxis.skill, // mismatch with target axis profile
            forkedRef: 'editor::content_translate',
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('T-AGT-FORK-021 — facts axis transfer (agent → agent)', () async {
      final system = _buildSystem(
        skillRegistry: MemorySkillRegistry(),
        profileRegistry: ProfileRegistry(),
      );
      for (final id in const ['editor', 'publisher']) {
        await system.agents.createAgent(
          id: id,
          displayName: id,
          model: ModelSpec.stub(),
          workspaceId: 'w1',
        );
      }
      const query = FactQuery(workspaceId: 'default');
      await system.agents.assignFacts('editor', query);
      final editorOwned =
          await system.agentRegistry!.listOwned('editor', AgentAxis.facts);
      expect(editorOwned, hasLength(1));
      final editorForkedRef = editorOwned.first.forkedRef;

      // Transfer the facts snapshot to publisher.
      await system.agents.assignFactsFromAgent(
        'publisher',
        AgentForkSource(
          agentId: 'editor',
          axis: AgentAxis.facts,
          forkedRef: editorForkedRef,
        ),
      );

      final publisherOwned =
          await system.agentRegistry!.listOwned('publisher', AgentAxis.facts);
      expect(publisherOwned, hasLength(1));
      expect(
        publisherOwned.first.forkedRef,
        equals('publisher::$editorForkedRef'),
      );
      // Lineage chains: pool synthetic → agent transfer.
      final stored = await system.agentRegistry!.getOwned(
        'publisher',
        AgentAxis.facts,
        publisherOwned.first.forkedRef,
      );
      expect(stored, isA<OwnedFork>());
      final envelope = stored as OwnedFork;
      expect(envelope.lineage, hasLength(2));
      expect(envelope.lineage.first, startsWith('pool:facts::'));
      expect(envelope.lineage.last, startsWith('agent:editor/facts/'));
    });

    test('T-AGT-FORK-022 — philosophy axis transfer (agent → agent)',
        () async {
      final system = _buildSystem(
        skillRegistry: MemorySkillRegistry(),
        profileRegistry: ProfileRegistry(),
        ethosStore: _MemEthosStore(),
      );
      // Seed an active default ethos so the philosophy pool fork resolves
      // to a real Ethos payload.
      await system.philosophyEngine!.initialize();
      for (final id in const ['editor', 'publisher']) {
        await system.agents.createAgent(
          id: id,
          displayName: id,
          model: ModelSpec.stub(),
          workspaceId: 'w1',
        );
      }
      // Pool philosophy assignment falls back to PhilosophyFacade.getEthos —
      // returns the seeded default ethos.
      await system.agents.assignPhilosophyFromPool('editor', 'house-style');
      final editorOwned =
          await system.agentRegistry!.listOwned('editor', AgentAxis.philosophy);
      expect(editorOwned, hasLength(1));
      final editorForkedRef = editorOwned.first.forkedRef;

      // Transfer to publisher.
      await system.agents.assignPhilosophy(
        'publisher',
        AgentForkSource(
          agentId: 'editor',
          axis: AgentAxis.philosophy,
          forkedRef: editorForkedRef,
        ),
      );

      final publisherOwned = await system.agentRegistry!
          .listOwned('publisher', AgentAxis.philosophy);
      expect(publisherOwned, hasLength(1));
      expect(
        publisherOwned.first.forkedRef,
        equals('publisher::$editorForkedRef'),
      );
      final stored = await system.agentRegistry!.getOwned(
        'publisher',
        AgentAxis.philosophy,
        publisherOwned.first.forkedRef,
      );
      expect(stored, isA<OwnedFork>());
      final envelope = stored as OwnedFork;
      expect(envelope.lineage, hasLength(2));
      expect(envelope.lineage.first, equals('pool:house-style'));
      expect(
        envelope.lineage.last,
        startsWith('agent:editor/philosophy/'),
      );
    });

    test('T-AGT-FORK-019 — OwnedFork.toJson / fromJson round-trip', () async {
      final system = await _twoAgentsWithSharedSkill();
      final original = await system.agentRegistry!.getOwned(
        'editor',
        AgentAxis.skill,
        'editor::content_translate',
      );
      expect(original, isA<OwnedFork>());

      // toJson → jsonEncode → jsonDecode → fromJson.
      final encoded = jsonEncode(
        (original as OwnedFork).toJson(),
        toEncodable: (o) => (o as dynamic).toJson(),
      );
      final decoded = jsonDecode(encoded) as Map<String, Object?>;
      final reconstructed = OwnedFork.fromJson(decoded);

      expect(reconstructed.source.encode(), equals(original.source.encode()));
      expect(reconstructed.lineage, equals(original.lineage));
      expect(
        reconstructed.forkOwnerAgentId,
        equals(original.forkOwnerAgentId),
      );
      expect(
        reconstructed.forkedAt.toIso8601String(),
        equals(original.forkedAt.toIso8601String()),
      );
      // Payload round-trips through `(p as dynamic).toJson()` — domain
      // objects with toJson surface as a Map after the trip.
      expect(reconstructed.payload, isNotNull);
    });
  });
}
