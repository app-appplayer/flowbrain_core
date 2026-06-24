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

    test('T-AGT-CONV-RACE — concurrent same-agent append loses no turn',
        () async {
      // Direct store: fire many concurrent appends for the SAME agentId
      // without awaiting each. The non-atomic read-modify-write would
      // last-write-wins and drop turns without per-agent serialization.
      final store = ConversationStore(
        kvStorage: InMemoryKvStoragePort(),
        config: const AgentConfig(maxConversationTurns: 0), // no compression
      );
      ConversationTurn turnOf(String m) => ConversationTurn(
            userMessage: m,
            assistantReply: 'r',
            model: 'stub',
            timestamp: DateTime(2026),
          );
      await Future.wait(<Future<void>>[
        for (var i = 0; i < 25; i++) store.append('a', turnOf('m$i')),
      ]);
      final history = await store.load('a', limit: -1);
      // Every turn preserved (no loss), each exactly once.
      expect(history, hasLength(25));
      expect(
        history.map((t) => t.userMessage).toSet(),
        equals(<String>{for (var i = 0; i < 25; i++) 'm$i'}),
      );
      await store.shutdown();
    });

    test('T-AGT-CONV-RACE-2 — different agents append in parallel, isolated',
        () async {
      final store = ConversationStore(
        kvStorage: InMemoryKvStoragePort(),
        config: const AgentConfig(maxConversationTurns: 0),
      );
      ConversationTurn turnOf(String m) => ConversationTurn(
            userMessage: m,
            assistantReply: 'r',
            model: 'stub',
            timestamp: DateTime(2026),
          );
      // Interleave concurrent appends across two agents — each agent's tail
      // is independent, and per-agent histories stay isolated + complete.
      await Future.wait(<Future<void>>[
        for (var i = 0; i < 10; i++) ...<Future<void>>[
          store.append('a', turnOf('a$i')),
          store.append('b', turnOf('b$i')),
        ],
      ]);
      expect(await store.load('a', limit: -1), hasLength(10));
      expect(await store.load('b', limit: -1), hasLength(10));
      await store.shutdown();
    });
  });
}
