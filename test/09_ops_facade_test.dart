/// TEST-09 — OpsFacade (delegated through wrapper)
library;

import 'package:flowbrain_core/flowbrain_core.dart';
import 'package:test/test.dart';

void main() {
  group('OpsFacade (wrapper getter)', () {
    test('T-OPS-001 — system.ops is OpsFacade after stub()', () {
      final system = KnowledgeSystem.stub();
      expect(system.ops, isA<OpsFacade>());
    });

    test('T-OPS-002 — runWorkflow throws StateError when ops unwired', () {
      final system = KnowledgeSystem.stub();
      expect(
        () => system.ops.runWorkflow('w1', const {}),
        throwsA(isA<StateError>()),
      );
    });
  });
}
