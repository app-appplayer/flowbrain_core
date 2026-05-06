import 'package:logging/logging.dart';

import 'loader.dart' show SchemaError;

export 'loader.dart' show SchemaError;

final _log = Logger('ConfigMigrator');

/// Schema migration engine for FlowBrain configuration.
///
/// Handles automatic migration when configVersion is older than expected,
/// and rejects configs from newer versions.
class ConfigMigrator {
  /// Current schema version supported by this FlowBrain build.
  static const int currentVersion = 1;

  /// Registered migrations (empty at v1 — populated as schema evolves).
  static final List<Migration> _defaultMigrations = [];

  /// Migrate a raw YAML map to the current schema version.
  ///
  /// - Same version: no-op
  /// - Older version: applies migration chain
  /// - Newer version: throws SchemaError
  /// - Missing configVersion: throws SchemaError
  static Map<String, dynamic> migrate(Map<String, dynamic> yaml) {
    return _migrateWith(yaml, _defaultMigrations);
  }

  /// Create a migrator with custom migrations (for testing).
  static ConfigMigrator withMigrations(List<Migration> migrations) {
    return ConfigMigrator._(migrations);
  }

  final List<Migration> _migrations;
  const ConfigMigrator._(this._migrations);

  /// Instance-method version of migrate, using custom migration list.
  Map<String, dynamic> migrateWith(Map<String, dynamic> yaml) {
    return _migrateWith(yaml, _migrations);
  }

  static Map<String, dynamic> _migrateWith(
    Map<String, dynamic> yaml,
    List<Migration> migrations,
  ) {
    var current = yaml['configVersion'] as int? ??
        (throw const SchemaError('configVersion is required'));
    var data = Map<String, dynamic>.from(yaml);

    if (current > currentVersion) {
      throw SchemaError(
        'configVersion $current is newer than supported ($currentVersion). '
        'Upgrade FlowBrain.',
      );
    }

    while (current < currentVersion) {
      final migration = migrations
          .where((m) => m.fromVersion == current)
          .firstOrNull;
      if (migration == null) {
        throw SchemaError(
          'No migration path from version $current to $currentVersion',
        );
      }

      _log.info(
        'Migrating config from v${migration.fromVersion} '
        'to v${migration.toVersion}',
      );
      data = migration.transform(data);
      current = migration.toVersion;
      data['configVersion'] = current;
    }

    return data;
  }
}

/// A single schema migration step.
class Migration {
  final int fromVersion;
  final int toVersion;
  final Map<String, dynamic> Function(Map<String, dynamic>) transform;

  const Migration({
    required this.fromVersion,
    required this.toVersion,
    required this.transform,
  });
}
