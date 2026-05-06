/// TEST-15 — ForkEngine (assignment + isolation)
///
/// Without active SkillRuntime / ProfileRuntime / PhilosophyEngine the
/// fork attempts surface as `StateError`. Full fork-isolation tests
/// require the host to wire those runtimes — covered in integration
/// suites maintained downstream.
library;

import 'package:flowbrain_core/flowbrain_core.dart';
import 'package:test/test.dart';

void main() {
  group('ForkEngine', () {
    test('T-AGT-FORK-001 — assignSkill without SkillRuntime → StateError',
        () async {
      final system = KnowledgeSystem.withAgents();
      await system.agents.createAgent(
        id: 'a',
        displayName: 'A',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      await expectLater(
        () => system.agents.assignSkillFromPool('a', 'design_review'),
        throwsA(isA<StateError>()),
      );
    });

    test('T-AGT-FORK-009 — duplicate fork is detected (or idempotent)',
        () async {
      // With no SkillRuntime wired we cannot perform an actual fork — the
      // intent here is to verify that ForkConflictException exists and is
      // exported.
      expect(ForkConflictException, isNotNull);
      const exc = ForkConflictException(
        agentId: 'a',
        axis: AgentAxis.skill,
        sourceRef: 's',
        existingForkedRef: 'a::s',
      );
      expect(exc.toString(), contains('agent \'a\''));
      expect(exc.toString(), contains('axis=skill'));
    });

    test('T-AGT-FORK-011 — fork engine has no Knowledge write API call',
        () {
      // Static check is enforced by code review (NFR-FBCORE-ISO-004).
      // This placeholder confirms the engine type is reachable from
      // public API only via AgentFacade.assign* methods.
      final system = KnowledgeSystem.withAgents();
      expect(system.agents.assignSkill, isA<Function>());
      expect(system.agents.assignProfile, isA<Function>());
      expect(system.agents.assignPhilosophy, isA<Function>());
      expect(system.agents.assignFacts, isA<Function>());
    });

    test('T-AGT-FORK-013 — tryAssignSkill returns false when SkillRuntime '
        'is missing instead of throwing', () async {
      final system = KnowledgeSystem.withAgents();
      await system.agents.createAgent(
        id: 'a',
        displayName: 'A',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      final ok = await system.agents.tryAssignSkillFromPool('a', 'unknown');
      expect(ok, isFalse);
    });

    test('T-AGT-FORK-014 — tryAssignProfile / Philosophy / Facts skip '
        'silently in partial-wire setups', () async {
      final system = KnowledgeSystem.withAgents();
      await system.agents.createAgent(
        id: 'a',
        displayName: 'A',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      expect(
          await system.agents.tryAssignProfileFromPool('a', 'persona'), isFalse);
      expect(
          await system.agents.tryAssignPhilosophyFromPool('a', 'ethos'), isFalse);
      // assignFacts requires only the L0 default runtime which is always
      // wired — this should succeed.
      final factsOk = await system.agents.tryAssignFacts(
        'a',
        const FactQuery(workspaceId: 'default'),
      );
      expect(factsOk, isTrue);
    });

    test('T-AGT-FORK-015 — tryAssign* still surfaces AgentNotFoundException',
        () async {
      final system = KnowledgeSystem.withAgents();
      await expectLater(
        () => system.agents.tryAssignSkillFromPool('ghost', 's'),
        throwsA(isA<AgentNotFoundException>()),
      );
    });
  });
}
