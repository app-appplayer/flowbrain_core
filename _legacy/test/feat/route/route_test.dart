/// Tests for FEAT-ROUTE: Agent definition, registry, router, and pipeline.
library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:flowbrain_core/src/feat/route/agent_definition.dart';
import 'package:flowbrain_core/src/feat/route/agent_registry.dart';
import 'package:flowbrain_core/src/feat/route/agent_router.dart';
import 'package:flowbrain_core/src/feat/route/ask_pipeline.dart';
import 'package:flowbrain_core/src/core/asm/errors.dart';

// ── Stubs ──────────────────────────────────────────────────────────────────

/// Minimal LlmPort stub for testing.
class _StubLlmPort implements LlmPort {
  final String? agentIdToReturn;
  int callCount = 0;

  _StubLlmPort({this.agentIdToReturn});

  @override
  Future<LlmResponse> complete(String prompt) async {
    callCount++;
    return LlmResponse(text: agentIdToReturn ?? '');
  }
}

/// Minimal AskRouteCache stub.
class _StubCache implements AskRouteCache {
  final Map<String, String> _map = {};

  @override
  String? get(String request) => _map[request];

  @override
  void put(String request, String agentId) => _map[request] = agentId;
}

void main() {
  // ════════════════════════════════════════════════════════════════════════
  // 1. RouteRule matching
  // ════════════════════════════════════════════════════════════════════════

  group('KeywordRule', () {
    test('matches when keyword is contained (case-insensitive)', () {
      final rule = KeywordRule(keywords: ['finance', 'tax']);
      expect(rule.matches('Please calculate my Tax'), isTrue);
      expect(rule.matches('anything about finance here'), isTrue);
    });

    test('does not match when no keyword present', () {
      final rule = KeywordRule(keywords: ['finance']);
      expect(rule.matches('weather today'), isFalse);
    });
  });

  group('RegexRule', () {
    test('matches when pattern hits', () {
      final rule = RegexRule(pattern: RegExp(r'\b\d{3}-\d{4}\b'));
      expect(rule.matches('Call 555-1234 now'), isTrue);
    });

    test('does not match when pattern misses', () {
      final rule = RegexRule(pattern: RegExp(r'^ERROR'));
      expect(rule.matches('no error here'), isFalse);
    });
  });

  group('LlmRule', () {
    test('matches always returns false (handled by router)', () {
      final rule = LlmRule(prompt: 'classify this');
      expect(rule.matches('anything'), isFalse);
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // 2. AgentRegistry
  // ════════════════════════════════════════════════════════════════════════

  group('AgentRegistry', () {
    late AgentRegistry registry;

    setUp(() {
      registry = AgentRegistry();
    });

    test('register and get agent by id', () {
      final agent = AgentDefinition(
        id: 'test-agent',
        factGraphScopes: ['scope1'],
        skills: ['skill1'],
        profileId: 'p1',
        philosophyId: 'ph1',
      );
      registry.register(agent);
      expect(registry.get('test-agent'), equals(agent));
    });

    test('register agent with id "default" sets defaultAgent', () {
      final agent = AgentDefinition(
        id: 'default',
        factGraphScopes: [],
        skills: ['general'],
        profileId: 'neutral',
        philosophyId: 'safety',
      );
      registry.register(agent);
      expect(registry.defaultAgent, equals(agent));
    });

    test('unregister removes agent', () {
      final agent = AgentDefinition(
        id: 'temp',
        factGraphScopes: [],
        skills: ['s1'],
        profileId: 'p1',
        philosophyId: 'ph1',
      );
      registry.register(agent);
      registry.unregister('temp');
      expect(registry.get('temp'), isNull);
    });

    test('list returns only enabled agents by default', () {
      registry.register(AgentDefinition(
        id: 'enabled-agent',
        factGraphScopes: [],
        skills: ['s1'],
        profileId: 'p1',
        philosophyId: 'ph1',
        enabled: true,
      ));
      registry.register(AgentDefinition(
        id: 'disabled-agent',
        factGraphScopes: [],
        skills: ['s2'],
        profileId: 'p2',
        philosophyId: 'ph2',
        enabled: false,
      ));

      final enabled = registry.list();
      expect(enabled.length, 1);
      expect(enabled.first.id, 'enabled-agent');

      final all = registry.list(onlyEnabled: false);
      expect(all.length, 2);
    });

    test('load from config map', () {
      final config = <String, dynamic>{
        'finance': {
          'skills': ['settlement', 'tax_report'],
          'profile': 'conservative',
          'philosophy': 'accuracy_first',
          'scopes': ['accounting', 'payroll'],
          'route': {
            'type': 'keyword',
            'keywords': ['tax', 'finance'],
          },
        },
        'default': {
          'skills': ['general_chat'],
          'profile': 'neutral',
          'philosophy': 'safety',
        },
      };

      final loaded = AgentRegistry.load(config);
      expect(loaded.get('finance'), isNotNull);
      expect(loaded.get('finance')!.skills, ['settlement', 'tax_report']);
      expect(loaded.defaultAgent, isNotNull);
      expect(loaded.defaultAgent!.id, 'default');
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // 3. AgentRouter
  // ════════════════════════════════════════════════════════════════════════

  group('AgentRouter', () {
    late AgentRegistry registry;
    late _StubCache cache;

    setUp(() {
      registry = AgentRegistry();
      cache = _StubCache();
    });

    test('resolves via keyword rule match', () async {
      final agent = AgentDefinition(
        id: 'finance',
        factGraphScopes: ['accounting'],
        skills: ['settlement'],
        profileId: 'conservative',
        philosophyId: 'accuracy',
        route: KeywordRule(keywords: ['tax', 'finance']),
      );
      registry.register(agent);

      final router = AgentRouter(
        registry: registry,
        cache: cache,
      );

      final resolved = await router.resolve('Calculate my tax');
      expect(resolved.id, 'finance');
    });

    test('resolves via cache on second call', () async {
      final agent = AgentDefinition(
        id: 'finance',
        factGraphScopes: [],
        skills: ['s1'],
        profileId: 'p1',
        philosophyId: 'ph1',
        route: KeywordRule(keywords: ['tax']),
      );
      registry.register(agent);

      final router = AgentRouter(
        registry: registry,
        cache: cache,
      );

      // First call populates cache
      await router.resolve('tax question');
      // Second call should hit cache
      final resolved = await router.resolve('tax question');
      expect(resolved.id, 'finance');
    });

    test('falls back to default agent when no rule matches', () async {
      final defaultAgent = AgentDefinition(
        id: 'default',
        factGraphScopes: [],
        skills: ['general'],
        profileId: 'neutral',
        philosophyId: 'safety',
      );
      registry.register(defaultAgent);

      final router = AgentRouter(
        registry: registry,
        cache: cache,
      );

      final resolved = await router.resolve('random unmatched query');
      expect(resolved.id, 'default');
    });

    test('throws AgentNotFoundError when no match and no default', () async {
      final router = AgentRouter(
        registry: registry,
        cache: cache,
      );

      expect(
        () => router.resolve('no match possible'),
        throwsA(isA<AgentNotFoundError>()),
      );
    });

    test('uses LLM fallback when keyword/regex miss', () async {
      final llm = _StubLlmPort(agentIdToReturn: 'smart-agent');

      final smartAgent = AgentDefinition(
        id: 'smart-agent',
        factGraphScopes: [],
        skills: ['ai_chat'],
        profileId: 'p1',
        philosophyId: 'ph1',
      );
      registry.register(smartAgent);

      final router = AgentRouter(
        registry: registry,
        cache: cache,
        llm: llm,
      );

      final resolved = await router.resolve('complex ambiguous query');
      expect(resolved.id, 'smart-agent');
      expect(llm.callCount, 1);
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // 4. AskPipeline (basic flow with stubs)
  // ════════════════════════════════════════════════════════════════════════

  group('AskPipeline', () {
    test('returns AskResult with routed agent', () async {
      final registry = AgentRegistry();
      registry.register(AgentDefinition(
        id: 'default',
        factGraphScopes: [],
        skills: ['general'],
        profileId: 'neutral',
        philosophyId: 'safety',
      ));

      final router = AgentRouter(
        registry: registry,
        cache: _StubCache(),
      );

      final pipeline = AskPipeline(router: router);
      final result = await pipeline.run('hello world');

      expect(result.agentId, 'default');
      expect(result.traceId, isNotEmpty);
    });
  });
}
