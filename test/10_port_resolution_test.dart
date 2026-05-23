/// TEST-10 — Port resolution (Knowledge 5 + Agent 1) — zero silent fallbacks.
library;

import 'package:flowbrain_core/flowbrain_core.dart';
import 'package:test/test.dart';

void main() {
  group('Port Resolution (6 facade silent-fallback 0)', () {
    test('T-RES-001 — Knowledge 5: opt-in unwired → StateError', () {
      final system = KnowledgeSystem.stub();
      expect(
        () => system.skill.execute('s1', const {}),
        throwsA(isA<StateError>()),
      );
      expect(
        () => system.profile.apply('p1', entityId: 'e1'),
        throwsA(isA<StateError>()),
      );
      expect(
        () => system.philosophy.getEthos(),
        throwsA(isA<StateError>()),
      );
      expect(
        () => system.ops.runWorkflow('w1', const {}),
        throwsA(isA<StateError>()),
      );
    });

    test('T-RES-002 — Agent Subsystem unwired → StateError on first call',
        () {
      final system = KnowledgeSystem.stub();
      expect(system.agents.isActivated, isFalse);
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

    test('T-RES-003 — error message identifies the missing facade', () {
      final system = KnowledgeSystem.stub();
      try {
        system.agents.getAgent('any');
        fail('expected StateError');
      } on StateError catch (e) {
        expect(e.message, contains('Agent Subsystem'));
        expect(e.message, contains('agentRegistry'));
        expect(e.message, contains('agentRuntime'));
      }
    });
  });
}
