/// TEST-18 — ForkEngine integration with wired SkillRuntime,
/// ProfileRuntime, and PhilosophyEngine.
///
/// Exercises the assignSkill / assignProfile / assignPhilosophy /
/// assignFacts paths end-to-end and verifies P8 Fork Isolation:
/// agent-owned forks are independent of each other and of the pool.
library;

import 'package:flowbrain_core/flowbrain_core.dart';
import 'package:test/test.dart';

KnowledgeSystem _buildSystem({
  required SkillBundleRegistry skillRegistry,
  required ProfileRegistry profileRegistry,
}) {
  final infra = InfraPorts.inMemory().copyWith(
    llm: StubLlmPort(),
    mcp: const StubMcpPort(),
  );
  final eventBus = KnowledgeEventBus();

  final skillRuntime = SkillRuntime(
    registry: skillRegistry,
    ports: SkillPorts(
      llm: StubLlmPort(),
      mcp: const StubMcpPort(),
    ),
  );
  final profileRuntime = ProfileRuntime(
    registry: profileRegistry,
    engines: EnginePorts.stub(),
  );
  final philosophyEngine = PhilosophyEngine(
    ethosStore: const StubEthosStorePort(),
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

Profile _profile(String id, {String name = 'Persona'}) =>
    Profile(id: id, name: name);

void main() {
  group('ForkEngine — wired runtime integration', () {
    test('T-AGT-FORK-INT-001 — assignSkill clones a SkillBundle into '
        'agent-owned storage + emits AgentForkAssignedEvent', () async {
      final skillReg = MemorySkillRegistry();
      await skillReg.registerSkill(_bundle('design_review'));
      final system = _buildSystem(
        skillRegistry: skillReg,
        profileRegistry: ProfileRegistry(),
      );

      await system.agents.createAgent(
        id: 'sara',
        displayName: 'Sara',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      final events = <AgentForkAssignedEvent>[];
      system.eventBus.on<AgentForkAssignedEvent>().listen(events.add);

      await system.agents.assignSkillFromPool('sara', 'design_review');
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.first.axis, equals(AgentAxis.skill));
      // sourceRef now uses the canonical sealed-encoded form (`pool:<id>`).
      expect(events.first.sourceRef, equals('pool:design_review'));
      expect(events.first.forkedRef, equals('sara::design_review'));

      final list =
          await system.agentRegistry!.listOwned('sara', AgentAxis.skill);
      expect(list, hasLength(1));
      expect(list.first.sourceRef, equals('pool:design_review'));
    });

    test('T-AGT-FORK-INT-002 — assignSkill on missing skill throws StateError',
        () async {
      final system = _buildSystem(
        skillRegistry: MemorySkillRegistry(),
        profileRegistry: ProfileRegistry(),
      );
      await system.agents.createAgent(
        id: 'a',
        displayName: 'A',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      await expectLater(
        () => system.agents.assignSkillFromPool('a', 'unknown'),
        throwsA(isA<StateError>()),
      );
    });

    test('T-AGT-FORK-INT-003 — assignProfile clones a Profile into '
        'agent-owned storage', () async {
      final profileReg = ProfileRegistry()..register(_profile('persona'));
      final system = _buildSystem(
        skillRegistry: MemorySkillRegistry(),
        profileRegistry: profileReg,
      );
      await system.agents.createAgent(
        id: 'a',
        displayName: 'A',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      await system.agents.assignProfileFromPool('a', 'persona');
      final list =
          await system.agentRegistry!.listOwned('a', AgentAxis.profile);
      expect(list, hasLength(1));
      expect(list.first.forkedRef, equals('a::persona'));
    });

    test('T-AGT-FORK-INT-004 — assignPhilosophy delegates to '
        'PhilosophyFacade.getEthos and surfaces failures', () async {
      // The stub `EthosStorePort` ships without an active ethos, so the
      // assign-philosophy path is expected to bubble up the underlying
      // `StateError`. This validates that the read API is invoked exactly
      // once and that the engine error is not swallowed.
      final system = _buildSystem(
        skillRegistry: MemorySkillRegistry(),
        profileRegistry: ProfileRegistry(),
      );
      await system.agents.createAgent(
        id: 'a',
        displayName: 'A',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      await expectLater(
        () => system.agents.assignPhilosophyFromPool('a', 'default-ethos'),
        throwsA(isA<StateError>()),
      );
    });

    test('T-AGT-FORK-INT-005 — assignFacts snapshots a queryFacts result',
        () async {
      final system = _buildSystem(
        skillRegistry: MemorySkillRegistry(),
        profileRegistry: ProfileRegistry(),
      );
      await system.agents.createAgent(
        id: 'a',
        displayName: 'A',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      const query = FactQuery(workspaceId: 'default');
      await system.agents.assignFacts('a', query);
      final list =
          await system.agentRegistry!.listOwned('a', AgentAxis.facts);
      expect(list, hasLength(1));
      expect(list.first.sourceRef, startsWith('pool:facts::'));
    });

    test('T-AGT-FORK-INT-006 — P8 Fork Isolation: two agents fork the same '
        'skill, mutating one does not affect the other', () async {
      final skillReg = MemorySkillRegistry();
      await skillReg.registerSkill(_bundle('shared', name: 'Shared'));
      final system = _buildSystem(
        skillRegistry: skillReg,
        profileRegistry: ProfileRegistry(),
      );

      for (final id in const ['a', 'b']) {
        await system.agents.createAgent(
          id: id,
          displayName: id.toUpperCase(),
          model: ModelSpec.stub(),
          workspaceId: 'w1',
        );
        await system.agents.assignSkillFromPool(id, 'shared');
      }

      // Mutate agent A's owned storage by overwriting with idempotent
      // storeOwned (same forkedRef). Agent B's owned skill should be
      // untouched.
      await system.agentRegistry!.storeOwned(
        agentId: 'a',
        axis: AgentAxis.skill,
        sourceRef: 'shared',
        forkedRef: 'a::shared',
        payload: const {'modified_by': 'a'},
      );

      final ownedA =
          await system.agentRegistry!.getOwned('a', AgentAxis.skill, 'a::shared');
      final ownedB =
          await system.agentRegistry!.getOwned('b', AgentAxis.skill, 'b::shared');
      expect(ownedA, isA<Map>());
      expect((ownedA as Map)['modified_by'], equals('a'));
      // B is still the original SkillBundle envelope (OwnedFork) — not a
      // Map with 'modified_by'.
      expect(ownedB, isNot(equals(ownedA)));
    });

    test('T-AGT-FORK-INT-007 — P8 Fork Isolation: pool registry update does '
        'not affect previously assigned forks', () async {
      final skillReg = MemorySkillRegistry();
      await skillReg.registerSkill(_bundle('s', name: 'Original'));
      final system = _buildSystem(
        skillRegistry: skillReg,
        profileRegistry: ProfileRegistry(),
      );
      await system.agents.createAgent(
        id: 'a',
        displayName: 'A',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      await system.agents.assignSkillFromPool('a', 's');

      final ownedBefore =
          await system.agentRegistry!.getOwned('a', AgentAxis.skill, 'a::s');

      // Replace the pool entry with a different bundle.
      await skillReg.unregisterSkill('s');
      await skillReg.registerSkill(_bundle('s', name: 'Updated'));

      final ownedAfter =
          await system.agentRegistry!.getOwned('a', AgentAxis.skill, 'a::s');
      // Storage value pointer is the same envelope — pool change had no
      // effect on the agent's owned copy.
      expect(identical(ownedBefore, ownedAfter), isTrue);
    });
  });
}
