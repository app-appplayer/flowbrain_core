/// TEST-11 — AgentFacade
library;

import 'package:flowbrain_core/flowbrain_core.dart';
import 'package:test/test.dart';

void main() {
  group('AgentFacade', () {
    test('T-AGT-FAC-001 — method catalog is exposed', () {
      final system = KnowledgeSystem.withAgents();
      final f = system.agents;
      expect(f.createAgent, isA<Function>());
      expect(f.getAgent, isA<Function>());
      expect(f.listAgents, isA<Function>());
      expect(f.updateAgent, isA<Function>());
      expect(f.deleteAgent, isA<Function>());
      expect(f.assignSkill, isA<Function>());
      expect(f.assignProfile, isA<Function>());
      expect(f.assignPhilosophy, isA<Function>());
      expect(f.assignFacts, isA<Function>());
      expect(f.unassign, isA<Function>());
      expect(f.ask, isA<Function>());
      expect(f.stream, isA<Function>());
      expect(f.route, isA<Function>());
      expect(f.review, isA<Function>());
      expect(f.getHistory, isA<Function>());
      expect(f.clearHistory, isA<Function>());
    });

    test('T-AGT-FAC-002 — Agent Subsystem unactivated → StateError', () {
      final system = KnowledgeSystem.stub();
      expect(
        () => system.agents.createAgent(
          id: 'a',
          displayName: 'A',
          model: ModelSpec.stub(),
          workspaceId: 'default',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('T-AGT-FAC-004 — withAgents smoke: create → ask round-trip',
        () async {
      final system = KnowledgeSystem.withAgents();
      final agent = await system.agents.createAgent(
        id: 'sara',
        displayName: 'Sara',
        model: ModelSpec.stub(),
        workspaceId: 'default',
      );
      expect(agent.id, equals('sara'));

      final reply = await system.agents.ask('sara', 'hello');
      expect(reply.agentId, equals('sara'));
    });

    test('T-AGT-FAC-007 — AgentNotFoundException for unknown id', () async {
      final system = KnowledgeSystem.withAgents();
      await expectLater(
        () => system.agents.ask('ghost', 'x'),
        throwsA(isA<AgentNotFoundException>()),
      );
    });
  });
}
