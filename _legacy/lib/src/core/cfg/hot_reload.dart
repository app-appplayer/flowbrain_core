import 'package:logging/logging.dart';

import 'schema/flowbrain_config.dart';

final _log = Logger('HotReloader');

/// Error thrown when hot-reload encounters unreloadable field changes.
class ReloadError implements Exception {
  final String message;
  const ReloadError(this.message);

  @override
  String toString() => 'ReloadError: $message';
}

/// Compares two FlowBrainConfig instances to determine what changed
/// and whether those changes can be hot-reloaded.
class ConfigDiff {
  /// Fields that changed but cannot be hot-reloaded.
  final List<String> unreloadableFields;

  final bool policyChanged;
  final bool agentsChanged;
  final bool bundlesChanged;
  final bool observabilityChanged;

  const ConfigDiff({
    this.unreloadableFields = const [],
    this.policyChanged = false,
    this.agentsChanged = false,
    this.bundlesChanged = false,
    this.observabilityChanged = false,
  });

  bool get hasUnreloadable => unreloadableFields.isNotEmpty;
  bool get hasChanges =>
      policyChanged ||
      agentsChanged ||
      bundlesChanged ||
      observabilityChanged ||
      hasUnreloadable;

  /// Compare two configurations and produce a diff.
  static ConfigDiff compare(
    FlowBrainConfig oldConfig,
    FlowBrainConfig newConfig,
  ) {
    final unreloadable = <String>[];

    // Profile change requires restart
    if (oldConfig.profile != newConfig.profile) {
      unreloadable.add('profile');
    }

    // LLM provider changes require restart
    final oldLlm = oldConfig.providers.llm;
    final newLlm = newConfig.providers.llm;
    if (oldLlm.type != newLlm.type) {
      unreloadable.add('providers.llm.type');
    }
    if (oldLlm.apiKey.toJson() != newLlm.apiKey.toJson()) {
      unreloadable.add('providers.llm.apiKey');
    }

    // Storage changes require restart
    if (oldConfig.providers.storage.type !=
        newConfig.providers.storage.type) {
      unreloadable.add('providers.storage.type');
    }

    // Reloadable changes: compare via JSON for simplicity
    final policyChanged = _jsonNe(
      oldConfig.policy.toJson(),
      newConfig.policy.toJson(),
    );
    final agentsChanged = _jsonNe(
      oldConfig.agents.map((k, v) => MapEntry(k, v.toJson())),
      newConfig.agents.map((k, v) => MapEntry(k, v.toJson())),
    );
    final bundlesChanged = _jsonNe(
      oldConfig.bundles.map((b) => b.toJson()).toList(),
      newConfig.bundles.map((b) => b.toJson()).toList(),
    );
    final observabilityChanged = _jsonNe(
      oldConfig.observability.toJson(),
      newConfig.observability.toJson(),
    );

    return ConfigDiff(
      unreloadableFields: unreloadable,
      policyChanged: policyChanged,
      agentsChanged: agentsChanged,
      bundlesChanged: bundlesChanged,
      observabilityChanged: observabilityChanged,
    );
  }

  /// Simple deep inequality check via toString comparison.
  static bool _jsonNe(dynamic a, dynamic b) => '$a' != '$b';
}

/// Skeleton hot-reloader for FlowBrain configuration changes.
///
/// File watcher integration is runtime-only; this provides the
/// diff/apply logic that the runtime watcher will invoke.
class HotReloader {
  /// Check whether a config change can be hot-reloaded.
  ///
  /// Returns the diff. Caller should check [ConfigDiff.hasUnreloadable]
  /// and throw [ReloadError] if needed.
  ConfigDiff checkReloadability(
    FlowBrainConfig current,
    FlowBrainConfig proposed,
  ) {
    final diff = ConfigDiff.compare(current, proposed);
    if (diff.hasUnreloadable) {
      _log.warning(
        'Unreloadable fields changed: ${diff.unreloadableFields.join(", ")}',
      );
    }
    return diff;
  }

  /// Validate that a proposed reload is safe, throwing if not.
  void assertReloadable(
    FlowBrainConfig current,
    FlowBrainConfig proposed,
  ) {
    final diff = checkReloadability(current, proposed);
    if (diff.hasUnreloadable) {
      throw ReloadError(
        'Cannot hot-reload: ${diff.unreloadableFields.join(", ")}. '
        'Restart required.',
      );
    }
  }
}
