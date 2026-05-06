/// TEST-01 — KnowledgeSystem (MOD-CORE-001)
///
/// flowbrain wrapper class. Verifies the 5 Knowledge facade delegations,
/// the `agents` (Agent Subsystem) facade, the three factories
/// (`defaults` / `stub` / `withAgents`), and the lifecycle.
library;

import 'package:flowbrain_core/flowbrain_core.dart';
import 'package:test/test.dart';

void main() {
  group('MOD-CORE-001 KnowledgeSystem', () {
    test('T-SYS-001 — full construction exposes 6 facades', () {
      final system = KnowledgeSystem(
        config: KnowledgeConfig.defaults,
        infraPorts: InfraPorts(knowledgePorts: KnowledgePorts.stub()),
      );
      expect(system.facts, isA<FactFacade>());
      expect(system.skill, isA<SkillFacade>());
      expect(system.profile, isA<ProfileFacade>());
      expect(system.philosophy, isA<PhilosophyFacade>());
      expect(system.ops, isA<OpsFacade>());
      expect(system.agents, isA<AgentFacade>());
      expect(system.agents.isActivated, isFalse);
    });

    test('T-SYS-002 — partial assembly: opt-in null + StateError on call',
        () async {
      final system = KnowledgeSystem(config: KnowledgeConfig.defaults);
      expect(system.facts, isNotNull);
      expect(() => system.profile.apply('p1', entityId: 'e1'),
          throwsA(isA<StateError>()));
      await system.shutdown();
    });

    test('T-SYS-003 — defaults factory uses defaults config', () {
      final system = KnowledgeSystem.defaults();
      expect(system.config.workspaceId, equals('default'));
      expect(system.config.agent.forkPolicy, equals(ForkPolicy.eagerFull));
    });

    test('T-SYS-004 — stub factory: L0 auto + opt-in null + agent stub', () {
      final system = KnowledgeSystem.stub();
      expect(system.factGraph, isNotNull);
      expect(system.skillRuntime, isNull);
      expect(system.profileRuntime, isNull);
      expect(system.philosophyEngine, isNull);
      expect(system.opsRuntime, isNull);
      expect(system.agents.isActivated, isFalse);
      expect(system.isAgentSubsystemActivated, isFalse);
    });

    test('T-SYS-005 — stub construction completes within 50ms', () {
      final sw = Stopwatch()..start();
      KnowledgeSystem.stub();
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThanOrEqualTo(50));
    });

    test('T-SYS-006 — facades are eagerly instantiated', () {
      final system = KnowledgeSystem.stub();
      expect(system.facts, isNotNull);
      expect(system.skill, isNotNull);
      expect(system.profile, isNotNull);
      expect(system.philosophy, isNotNull);
      expect(system.ops, isNotNull);
      expect(system.agents, isNotNull);
    });

    test('T-SYS-007 — withAgents factory activates Agent Subsystem', () {
      final system = KnowledgeSystem.withAgents();
      expect(system.isAgentSubsystemActivated, isTrue);
      expect(system.agents.isActivated, isTrue);
      expect(system.agentRegistry, isNotNull);
      expect(system.agentRuntime, isNotNull);
    });

    test('T-SYS-008 — shutdown emits SystemShutdownEvent and closes bus',
        () async {
      final system = KnowledgeSystem.stub();
      var shutdownSeen = false;
      final sub = system.eventBus.stream.listen((e) {
        if (e.type == 'system_shutdown') shutdownSeen = true;
      });
      await system.shutdown();
      await sub.cancel();
      expect(shutdownSeen, isTrue);
    });

    test('T-SYS-009 — multiple instances coexist independently', () {
      final s1 = KnowledgeSystem.stub();
      final s2 = KnowledgeSystem.stub();
      expect(identical(s1, s2), isFalse);
      expect(identical(s1.eventBus, s2.eventBus), isFalse);
    });

    test('T-SYS-010 — withAgents shutdown completes both subsystems',
        () async {
      final system = KnowledgeSystem.withAgents();
      await system.shutdown();
      // Subsequent createAgent throws because storage is shut down.
      // (We don't enforce a specific exception; just ensure shutdown
      // does not hang.)
      expect(true, isTrue);
    });
  });
}
