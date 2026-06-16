/// TEST-22 — assigned facts compose into the ask() system prompt.
///
/// Regression guard for the gap where `bk.agent.assign_facts` stored facts
/// but `AgentRuntime.ask` never composed them into the prompt the provider
/// receives. The fix resolves assigned facts (AgentAxis.facts) and prepends
/// an "Assigned knowledge" section to the agent's base systemPrompt.
library;

import 'dart:convert';

import 'package:flowbrain_core/flowbrain_core.dart';
import 'package:test/test.dart';

/// Captures the system prompt the provider actually receives.
class _CapturingLlm extends StubLlmPort {
  String? captured;

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    captured = request.systemPrompt;
    return const LlmResponse(content: 'ok');
  }
}

/// KvStoragePort that forces the JSON round-trip a *persistent* adapter
/// does — `jsonEncode` (with `toJson` fallback) on set, `jsonDecode` on
/// read. Reproduces the real ops path that the in-memory default hides:
/// fork payloads come back as JSON `Map`s, not live objects.
class _JsonRoundTripKv implements KvStoragePort {
  final Map<String, dynamic> _m = <String, dynamic>{};

  // Mirrors a real persistent adapter's tolerant encode: duck-typed
  // toJson, else toString (never throws into the caller).
  Object? _enc(Object? o) {
    try {
      return (o as dynamic).toJson();
    } catch (_) {
      return o?.toString();
    }
  }

  dynamic _json(dynamic v) =>
      jsonDecode(jsonEncode(v, toEncodable: _enc));

  @override
  Future<void> set(String key, dynamic value) async => _m[key] = _json(value);
  @override
  Future<dynamic> get(String key) async => _m[key];
  @override
  Future<void> remove(String key) async => _m.remove(key);
  @override
  Future<bool> exists(String key) async => _m.containsKey(key);
  @override
  Future<List<String>> keys({String? prefix}) async => _m.keys
      .where((k) => prefix == null || k.startsWith(prefix))
      .toList();
  @override
  Future<void> clear() async => _m.clear();
}

void main() {
  group('assigned facts → ask systemPrompt', () {
    test('assigned facts are composed into the prompt', () async {
      final cap = _CapturingLlm();
      final system =
          KnowledgeSystem.withAgents(llmProviders: <String, LlmPort>{'cap': cap});

      await system.facts.writeFacts(<FactRecord>[
        FactRecord(
          id: 'fact/q4_revenue',
          workspaceId: 'w1',
          type: 'fact',
          content: const <String, dynamic>{
            'value': 'Q4 revenue was 5.1 million USD.',
          },
          createdAt: DateTime.now(),
        ),
      ]);

      await system.agents.createAgent(
        id: 'analyst',
        displayName: 'Analyst',
        model: const ModelSpec(provider: 'cap', model: 'x'),
        workspaceId: 'w1',
        systemPrompt: 'You are an analyst.',
      );
      await system.agents.assignFacts(
        'analyst',
        const FactQuery(workspaceId: 'w1', types: <String>['fact']),
      );

      await system.agents.ask('analyst', 'What was Q4 revenue?');

      expect(cap.captured, isNotNull);
      expect(cap.captured, contains('You are an analyst.')); // base preserved
      expect(cap.captured, contains('Assigned knowledge'));
      expect(cap.captured, contains('Q4 revenue was 5.1 million USD.'));
    });

    test('no assigned facts → base systemPrompt unchanged (regression)',
        () async {
      final cap = _CapturingLlm();
      final system =
          KnowledgeSystem.withAgents(llmProviders: <String, LlmPort>{'cap': cap});

      await system.agents.createAgent(
        id: 'plain',
        displayName: 'Plain',
        model: const ModelSpec(provider: 'cap', model: 'x'),
        workspaceId: 'w1',
        systemPrompt: 'BASE ONLY',
      );

      await system.agents.ask('plain', 'hi');

      expect(cap.captured, equals('BASE ONLY'));
    });

    test('persistent (JSON) KV: assigned facts survive round-trip into prompt',
        () async {
      // The real ops path: fork payloads round-trip through JSON, so facts
      // come back as Maps (not live FactRecord). Pre-FactRecord.toJson this
      // produced "Instance of 'FactRecord'" garbage and the fact was lost.
      final cap = _CapturingLlm();
      final system = KnowledgeSystem.withAgents(
        infraPorts: InfraPorts(
          knowledgePorts: KnowledgePorts(kvStorage: _JsonRoundTripKv()),
        ),
        llmProviders: <String, LlmPort>{'cap': cap},
      );

      await system.facts.writeFacts(<FactRecord>[
        FactRecord(
          id: 'fact/secret',
          workspaceId: 'w1',
          type: 'fact',
          content: const <String, dynamic>{
            'value': 'The launch code is ZEBRA-9921.',
          },
          createdAt: DateTime.now(),
        ),
      ]);
      await system.agents.createAgent(
        id: 'kbagent',
        displayName: 'KB',
        model: const ModelSpec(provider: 'cap', model: 'x'),
        workspaceId: 'w1',
      );
      await system.agents.assignFacts(
        'kbagent',
        const FactQuery(workspaceId: 'w1', types: <String>['fact']),
      );

      await system.agents.ask('kbagent', 'What is the launch code?');

      expect(cap.captured, isNotNull);
      expect(cap.captured, contains('The launch code is ZEBRA-9921.'));
    });
  });
}
