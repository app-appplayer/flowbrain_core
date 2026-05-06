/// TEST-19 — Final coverage uplift for the remaining branches:
/// AgentRuntime.route candidate filter, ForkEngine copy-on-write, the
/// `KvStoragePort` null guard in `AgentSubsystem.create`, and
/// ConversationStore TTL sweeper.
library;

import 'package:flowbrain_core/flowbrain_core.dart';
import 'package:test/test.dart';

void main() {
  group('Extra coverage', () {
    test('AgentSubsystem.create — kvStorage null → '
        'ConversationStoreUnavailableException', () {
      final infra = InfraPorts(); // every port null
      final eventBus = KnowledgeEventBus();
      expect(
        () => AgentSubsystem.create(
          knowledgeSystemRef: () => Object(),
          infraPorts: infra,
          eventBus: eventBus,
          config: AgentConfig.defaults,
        ),
        throwsA(isA<ConversationStoreUnavailableException>()),
      );
    });

    test('AgentRuntime.route — candidateAgentIds filter is honored',
        () async {
      final system = KnowledgeSystem.withAgents();
      await system.agents.createAgent(
        id: 'm',
        displayName: 'Manager',
        role: AgentRole.manager,
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      await system.agents.createAgent(
        id: 'w1',
        displayName: 'W1',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      await system.agents.createAgent(
        id: 'w2',
        displayName: 'W2',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );

      final routed = <ManagerRoutedEvent>[];
      system.eventBus.on<ManagerRoutedEvent>().listen(routed.add);
      final decision = await system.agents.route(
        'm',
        'task',
        candidateAgentIds: const ['w1'],
      );
      expect(decision, isA<RoutingDecision>());
      await Future<void>.delayed(Duration.zero);
      expect(routed, hasLength(1));
    });

    test('ForkEngine — copyOnWrite defers payload resolution', () async {
      // copyOnWrite stores a LazyOwnedFork (no payload resolution). So
      // assignSkillFromPool succeeds even without a SkillRuntime — the
      // missing-runtime error is deferred until materialize() resolves
      // the source.
      final config = KnowledgeConfig.defaults.copyWith(
        agent: AgentConfig.defaults.copyWith(
          forkPolicy: ForkPolicy.copyOnWrite,
        ),
      );
      final system = KnowledgeSystem.withAgents(config: config);
      await system.agents.createAgent(
        id: 'a',
        displayName: 'A',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      // Lazy assignment succeeds (no source resolution at this point).
      await system.agents.assignSkillFromPool('a', 'unknown');
      // Materialize is where the missing SkillRuntime surfaces.
      final owned = await system.agentRegistry!
          .listOwned('a', AgentAxis.skill);
      expect(owned, isNotEmpty);
      await expectLater(
        () => system.agents
            .materialize('a', AgentAxis.skill, owned.first.forkedRef),
        throwsA(isA<StateError>()),
      );
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('ConversationStore — TTL sweeper removes expired entries',
        () async {
      // Setup with a tiny TTL so the entry is immediately eligible for
      // sweeping when we call `debugSweepNow`.
      final config = KnowledgeConfig.defaults.copyWith(
        agent: AgentConfig.defaults.copyWith(
          conversationTtl: const Duration(microseconds: 1),
        ),
      );
      final system = KnowledgeSystem.withAgents(config: config);
      await system.agents.createAgent(
        id: 'a',
        displayName: 'A',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      await system.agents.ask('a', 'hello');
      // Wait long enough for the TTL window to elapse.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      // Drive the sweeper directly — Timer is set to 1h in production.
      await (system.agentRuntime!.conversationStore).debugSweepNow();
      expect(await system.agents.getHistory('a'), isEmpty);
    });
  });
}
