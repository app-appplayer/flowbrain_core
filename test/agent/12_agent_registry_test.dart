/// TEST-12 — AgentRegistry
library;

import 'package:flowbrain_core/flowbrain_core.dart';
import 'package:test/test.dart';

void main() {
  group('AgentRegistry', () {
    test('T-AGT-REG-001 — CRUD round-trip + AgentCreated/Deleted events',
        () async {
      final system = KnowledgeSystem.withAgents();
      final created = <String>[];
      final deleted = <String>[];
      system.eventBus
          .on<AgentCreatedEvent>()
          .listen((e) => created.add(e.agentId));
      system.eventBus
          .on<AgentDeletedEvent>()
          .listen((e) => deleted.add(e.agentId));

      await system.agents.createAgent(
        id: 'a',
        displayName: 'A',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      final got = await system.agents.getAgent('a');
      expect(got, isNotNull);
      expect(got!.displayName, equals('A'));

      final list = await system.agents.listAgents(workspaceId: 'w1');
      expect(list, hasLength(1));

      await system.agents.updateAgent('a', displayName: 'A2');
      final updated = await system.agents.getAgent('a');
      expect(updated!.displayName, equals('A2'));

      await system.agents.deleteAgent('a');
      expect(await system.agents.getAgent('a'), isNull);

      await Future<void>.delayed(Duration.zero);
      expect(created, equals(['a']));
      expect(deleted, equals(['a']));
    });

    test(
        'T-AGT-REG-008 — update(role:) changes orchestration role in place '
        '(no delete/recreate), other fields and omissions preserved', () async {
      final system = KnowledgeSystem.withAgents();
      await system.agents.createAgent(
        id: 'a',
        displayName: 'Nora',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
        role: AgentRole.worker,
      );

      // Promote worker -> reviewer without destroying the individual.
      final promoted =
          await system.agents.updateAgent('a', role: AgentRole.reviewer);
      expect(promoted.role, equals(AgentRole.reviewer));
      expect(promoted.displayName, equals('Nora')); // untouched field kept

      // Persisted, not just returned.
      final got = await system.agents.getAgent('a');
      expect(got!.role, equals(AgentRole.reviewer));

      // Omitting role leaves it unchanged.
      final renamed =
          await system.agents.updateAgent('a', displayName: 'Nora 2');
      expect(renamed.role, equals(AgentRole.reviewer));
      expect(renamed.displayName, equals('Nora 2'));
    });

    test('T-AGT-REG-002 — duplicate id throws StateError', () async {
      final system = KnowledgeSystem.withAgents();
      await system.agents.createAgent(
        id: 'a',
        displayName: 'A',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      await expectLater(
        () => system.agents.createAgent(
          id: 'a',
          displayName: 'A again',
          model: ModelSpec.stub(),
          workspaceId: 'w1',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('T-AGT-REG-003 — maxAgentsPerWorkspace cap', () async {
      final system = KnowledgeSystem.withAgents(
        config: KnowledgeConfig.defaults.copyWith(
          agent: AgentConfig.defaults.copyWith(maxAgentsPerWorkspace: 2),
        ),
      );
      await system.agents.createAgent(
        id: 'a',
        displayName: 'A',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      await system.agents.createAgent(
        id: 'b',
        displayName: 'B',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      await expectLater(
        () => system.agents.createAgent(
          id: 'c',
          displayName: 'C',
          model: ModelSpec.stub(),
          workspaceId: 'w1',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('T-AGT-REG-006 — recordEvolution increments counter + emits event',
        () async {
      final system = KnowledgeSystem.withAgents();
      await system.agents.createAgent(
        id: 'a',
        displayName: 'A',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      final events = <AgentForkEvolvedEvent>[];
      system.eventBus
          .on<AgentForkEvolvedEvent>()
          .listen(events.add);

      await system.agentRegistry!.recordEvolution(
        agentId: 'a',
        axis: AgentAxis.skill,
        forkedRef: 'a::s',
        kind: GrowthKind.variation,
      );
      await system.agentRegistry!.recordEvolution(
        agentId: 'a',
        axis: AgentAxis.skill,
        forkedRef: 'a::s',
        kind: GrowthKind.variation,
      );
      await Future<void>.delayed(Duration.zero);

      final agent = await system.agents.getAgent('a');
      expect(agent!.growth.skillCandidateCount, equals(2));
      expect(events, hasLength(2));
    });

    test('T-AGT-REG-007 — enableGrowthTracking=false suppresses event',
        () async {
      final system = KnowledgeSystem.withAgents(
        config: KnowledgeConfig.defaults.copyWith(
          agent: AgentConfig.defaults.copyWith(enableGrowthTracking: false),
        ),
      );
      await system.agents.createAgent(
        id: 'a',
        displayName: 'A',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      final events = <AgentForkEvolvedEvent>[];
      system.eventBus
          .on<AgentForkEvolvedEvent>()
          .listen(events.add);
      await system.agentRegistry!.recordEvolution(
        agentId: 'a',
        axis: AgentAxis.profile,
        forkedRef: 'a::p',
        kind: GrowthKind.adjustment,
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
      // Counter still updates (storage layout stable).
      final agent = await system.agents.getAgent('a');
      expect(agent!.growth.profileAdjustmentCount, equals(1));
    });
  });
}
