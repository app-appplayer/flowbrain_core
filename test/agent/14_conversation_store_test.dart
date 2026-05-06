/// TEST-14 — ConversationStore
library;

import 'package:flowbrain_core/flowbrain_core.dart';
import 'package:test/test.dart';

void main() {
  group('ConversationStore', () {
    test('T-AGT-CONV-001 — append + load round-trip', () async {
      final system = KnowledgeSystem.withAgents();
      await system.agents.createAgent(
        id: 'a',
        displayName: 'A',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      await system.agents.ask('a', 'one');
      await system.agents.ask('a', 'two');
      final history = await system.agents.getHistory('a');
      expect(history, hasLength(2));
      expect(history.map((t) => t.userMessage), equals(['one', 'two']));
    });

    test('T-AGT-CONV-003 — clear isolation across agents', () async {
      final system = KnowledgeSystem.withAgents();
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
      await system.agents.ask('a', 'a-msg');
      await system.agents.ask('b', 'b-msg');
      await system.agents.clearHistory('a');
      expect(await system.agents.getHistory('a'), isEmpty);
      expect(await system.agents.getHistory('b'), hasLength(1));
    });

    test('T-AGT-CONV-005 — limit returns most recent turns', () async {
      final system = KnowledgeSystem.withAgents();
      await system.agents.createAgent(
        id: 'a',
        displayName: 'A',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      for (var i = 0; i < 5; i++) {
        await system.agents.ask('a', 'msg-$i');
      }
      final last2 = await system.agents.getHistory('a', limit: 2);
      expect(last2.map((t) => t.userMessage), equals(['msg-3', 'msg-4']));
    });

    test('T-AGT-CONV-006 — maxConversationTurns triggers compression',
        () async {
      final system = KnowledgeSystem.withAgents(
        config: KnowledgeConfig.defaults.copyWith(
          agent: AgentConfig.defaults.copyWith(maxConversationTurns: 3),
        ),
      );
      await system.agents.createAgent(
        id: 'a',
        displayName: 'A',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      for (var i = 0; i < 5; i++) {
        await system.agents.ask('a', 'msg-$i');
      }
      final history = await system.agents.getHistory('a');
      expect(history.first.userMessage, equals('<compressed-history>'));
      expect(history, hasLength(lessThanOrEqualTo(3)));
    });
  });
}
