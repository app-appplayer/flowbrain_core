import 'package:test/test.dart';
import 'package:flowbrain_core/src/core/cfg/migration.dart';

void main() {
  group('ConfigMigrator', () {
    test('same version is no-op', () {
      final yaml = {'configVersion': 1, 'profile': 'full'};
      final result = ConfigMigrator.migrate(yaml);
      expect(result['configVersion'], equals(1));
      expect(result['profile'], equals('full'));
    });

    test('newer version throws SchemaError', () {
      final yaml = {'configVersion': 999, 'profile': 'full'};
      expect(
        () => ConfigMigrator.migrate(yaml),
        throwsA(isA<SchemaError>()),
      );
    });

    test('missing configVersion throws SchemaError', () {
      final yaml = <String, dynamic>{'profile': 'full'};
      expect(
        () => ConfigMigrator.migrate(yaml),
        throwsA(isA<SchemaError>()),
      );
    });

    test('migration chain applies transforms in sequence', () {
      // Register test migrations: 0 -> 1
      final migrator = ConfigMigrator.withMigrations([
        Migration(
          fromVersion: 0,
          toVersion: 1,
          transform: (data) {
            // Simulate v0->v1: rename 'llm_provider' to nested 'providers.llm'
            final result = Map<String, dynamic>.from(data);
            if (result.containsKey('llm_provider')) {
              result['providers'] = {
                'llm': {'type': result.remove('llm_provider')},
              };
            }
            return result;
          },
        ),
      ]);

      final yaml = {
        'configVersion': 0,
        'llm_provider': 'claude',
      };
      final result = migrator.migrateWith(yaml);
      expect(result['configVersion'], equals(1));
      expect(result['providers'], isA<Map>());
      expect(
        (result['providers'] as Map)['llm'],
        equals({'type': 'claude'}),
      );
    });

    test('no migration path throws SchemaError', () {
      // Version 0 with no registered migrations for it
      final yaml = {'configVersion': 0};
      expect(
        () => ConfigMigrator.migrate(yaml),
        throwsA(isA<SchemaError>()),
      );
    });
  });
}
