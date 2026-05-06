/// TEST-02 — InfraPorts (MOD-CORE-002, flowbrain wrapper)
///
/// Verifies the wrapper around `mcp.KnowledgePorts` plus the
/// `llmProviders` multi-provider pool.
library;

import 'package:flowbrain_core/flowbrain_core.dart';
import 'package:test/test.dart';

void main() {
  group('MOD-CORE-002 InfraPorts', () {
    test('T-INF-001 — default constructor leaves every infra port null', () {
      final ports = InfraPorts();
      expect(ports.llm, isNull);
      expect(ports.kvStorage, isNull);
      expect(ports.mcp, isNull);
      expect(ports.retrieval, isNull);
      expect(ports.notification, isNull);
      expect(ports.event, isNull);
      expect(ports.metric, isNull);
      expect(ports.llmProviders, isNull);
    });

    test('T-INF-002 — inMemory wires kvStorage + event', () {
      final ports = InfraPorts.inMemory();
      expect(ports.kvStorage, isA<KvStoragePort>());
      expect(ports.event, isA<EventPort>());
      expect(ports.llm, isNull);
    });

    test('T-INF-003 — copyWith replaces only specified fields', () {
      final base = InfraPorts.inMemory();
      final next = base.copyWith(llm: StubLlmPort());
      expect(next.llm, isA<LlmPort>());
      expect(next.kvStorage, equals(base.kvStorage));
    });

    test('T-INF-004 — llmProviders multi-pool round-trip', () {
      final providers = {
        'anthropic': StubLlmPort(),
        'openai': StubLlmPort(),
      };
      final ports = InfraPorts.inMemory(llmProviders: providers);
      expect(ports.llmProviders, equals(providers));
    });

    test('T-INF-005 — internal forwards to underlying KnowledgePorts', () {
      final inner = KnowledgePorts.stub();
      final ports = InfraPorts(knowledgePorts: inner);
      expect(ports.internal, same(inner));
      expect(ports.llm, same(inner.llm));
    });

    test('T-INF-006 — copyWith preserves llmProviders when not overridden',
        () {
      final base = InfraPorts.inMemory(
        llmProviders: {'anthropic': StubLlmPort()},
      );
      final next = base.copyWith(llm: StubLlmPort());
      expect(next.llmProviders, equals(base.llmProviders));
    });
  });
}
