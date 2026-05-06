/// TEST-16 — Agent Role · Manager Router · Reviewer Engine
library;

import 'package:flowbrain_core/flowbrain_core.dart';
import 'package:test/test.dart';

void main() {
  group('AgentRole + Manager + Reviewer', () {
    test('T-AGT-ROLE-001 — three roles defined', () {
      expect(AgentRole.values,
          equals([AgentRole.worker, AgentRole.manager, AgentRole.reviewer]));
    });

    test('T-AGT-ROLE-002 — createAgent default role is worker', () async {
      final system = KnowledgeSystem.withAgents();
      final agent = await system.agents.createAgent(
        id: 'a',
        displayName: 'A',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      expect(agent.role, equals(AgentRole.worker));
    });

    test('T-AGT-ROLE-003 — route on worker → AgentRoleMismatchException',
        () async {
      final system = KnowledgeSystem.withAgents();
      await system.agents.createAgent(
        id: 'w',
        displayName: 'Worker',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      await expectLater(
        () => system.agents.route('w', 'task'),
        throwsA(isA<AgentRoleMismatchException>()),
      );
    });

    test('T-AGT-MGR-001 — manager route emits ManagerRoutedEvent',
        () async {
      final system = KnowledgeSystem.withAgents();
      await system.agents.createAgent(
        id: 'm',
        displayName: 'Manager',
        role: AgentRole.manager,
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      final routed = <ManagerRoutedEvent>[];
      system.eventBus.on<ManagerRoutedEvent>().listen(routed.add);

      final decision = await system.agents.route('m', 'do something');
      expect(decision, isA<RoutingDecision>());

      await Future<void>.delayed(Duration.zero);
      expect(routed, hasLength(1));
      expect(routed.first.managerId, equals('m'));
    });

    test('T-AGT-REV-001 — reviewer review emits ReviewerVerifiedEvent',
        () async {
      final system = KnowledgeSystem.withAgents();
      await system.agents.createAgent(
        id: 'r',
        displayName: 'Reviewer',
        role: AgentRole.reviewer,
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      final reviewed = <ReviewerVerifiedEvent>[];
      system.eventBus.on<ReviewerVerifiedEvent>().listen(reviewed.add);

      final reply = AgentReply(
        id: '',
        agentId: 'someone',
        content: 'sample',
        model: 'stub-1',
        timestamp: DateTime.now(),
      );
      final result = await system.agents.review('r', reply);
      expect(result, isA<ReviewResult>());

      await Future<void>.delayed(Duration.zero);
      expect(reviewed, hasLength(1));
      expect(reviewed.first.reviewerId, equals('r'));
    });

    test('T-AGT-EVT-001 — RoutingDecision parse fallback', () {
      final decision = RoutingDecision.tryParse('not json');
      expect(decision.targetAgentId, isEmpty);
      expect(decision.reason, equals('parse_error'));
    });

    test('T-AGT-EVT-002 — ReviewResult parse fallback', () {
      final result = ReviewResult.tryParse('not json');
      expect(result.verdict, equals(ReviewVerdict.fail));
      expect(result.comments, equals('parse_error'));
    });
  });
}
