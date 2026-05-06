/// TEST-08 — PhilosophyFacade (delegated through wrapper)
library;

import 'package:flowbrain_core/flowbrain_core.dart';
import 'package:test/test.dart';

void main() {
  group('PhilosophyFacade (wrapper getter)', () {
    test('T-PHL-001 — system.philosophy is PhilosophyFacade after stub()',
        () {
      final system = KnowledgeSystem.stub();
      expect(system.philosophy, isA<PhilosophyFacade>());
    });

    test('T-PHL-002 — getEthos throws StateError when engine unwired', () {
      final system = KnowledgeSystem.stub();
      expect(
        () => system.philosophy.getEthos(),
        throwsA(isA<StateError>()),
      );
    });
  });
}
