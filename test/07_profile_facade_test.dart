/// TEST-07 — ProfileFacade (delegated through wrapper)
library;

import 'package:flowbrain_core/flowbrain_core.dart';
import 'package:test/test.dart';

void main() {
  group('ProfileFacade (wrapper getter)', () {
    test('T-PRF-001 — system.profile is ProfileFacade after stub()', () {
      final system = KnowledgeSystem.stub();
      expect(system.profile, isA<ProfileFacade>());
    });

    test('T-PRF-002 — apply throws StateError when profileRuntime is unwired',
        () {
      final system = KnowledgeSystem.stub();
      expect(
        () => system.profile.apply('p1', entityId: 'e1'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
