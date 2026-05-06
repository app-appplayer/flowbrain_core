/// TEST-05 — FactFacade (delegated through wrapper)
///
/// FactFacade itself lives in `mcp_knowledge`. The flowbrain wrapper just
/// re-exposes it via `system.facts`. Tests focus on accessibility +
/// L0 default wiring.
library;

import 'package:flowbrain_core/flowbrain_core.dart';
import 'package:test/test.dart';

void main() {
  group('FactFacade (wrapper getter)', () {
    test('T-FCT-001 — system.facts is FactFacade after stub()', () {
      final system = KnowledgeSystem.stub();
      expect(system.facts, isA<FactFacade>());
    });

    test('T-FCT-002 — L0 default runtime is auto-wired', () {
      final system = KnowledgeSystem.stub();
      expect(system.factGraph, isNotNull);
    });

    test('T-FCT-003 — FactQuery round-trip via stub returns a list', () async {
      final system = KnowledgeSystem.stub();
      final results = await system.facts.queryFacts(
        const FactQuery(workspaceId: 'default'),
      );
      expect(results, isA<List<FactRecord>>());
    });
  });
}
