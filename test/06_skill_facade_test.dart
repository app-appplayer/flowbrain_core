/// TEST-06 — SkillFacade (delegated through wrapper)
library;

import 'package:flowbrain_core/flowbrain_core.dart';
import 'package:test/test.dart';

void main() {
  group('SkillFacade (wrapper getter)', () {
    test('T-SKL-001 — system.skill is SkillFacade after stub()', () {
      final system = KnowledgeSystem.stub();
      expect(system.skill, isA<SkillFacade>());
    });

    test('T-SKL-002 — execute throws StateError when skillRuntime is unwired',
        () {
      final system = KnowledgeSystem.stub();
      expect(
        () => system.skill.execute('s1', const {}),
        throwsA(isA<StateError>()),
      );
    });
  });
}
