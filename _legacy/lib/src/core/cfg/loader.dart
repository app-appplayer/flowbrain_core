import 'dart:io';

import 'package:logging/logging.dart';
import 'package:yaml/yaml.dart';

import 'schema/flowbrain_config.dart';
import 'migration.dart';

export 'schema/flowbrain_config.dart';

final _log = Logger('FlowBrainConfigLoader');

/// Error thrown for schema-level configuration problems.
class SchemaError implements Exception {
  final String message;
  const SchemaError(this.message);

  @override
  String toString() => 'SchemaError: $message';
}

/// Loads FlowBrain configuration from YAML files with overlay merge support.
///
/// Server mode: base -> env overlay -> secrets (3-layer)
/// Standard mode: base -> user override (2-layer)
class FlowBrainConfigLoader {
  /// Load configuration from a YAML file path with automatic overlay detection.
  ///
  /// [path] is the base `flowbrain.yaml` path.
  /// [env] selects the environment overlay (dev/staging/prod) — Server mode only.
  /// [standardMode] switches to 2-layer Standard overlay.
  /// [homePath] overrides the home directory (for testing).
  static Future<FlowBrainConfig> load(
    String path, {
    String? env,
    bool standardMode = false,
    String? homePath,
  }) async {
    final baseFile = File(path);
    if (!baseFile.existsSync()) {
      throw SchemaError('config file not found: $path');
    }

    final baseYaml = _readYaml(baseFile);
    final layers = <Map<String, dynamic>>[baseYaml];

    if (!standardMode && env != null) {
      final envPath = _deriveEnvPath(path, env);
      final envFile = File(envPath);
      if (envFile.existsSync()) {
        _log.fine('Loading env overlay: $envPath');
        layers.add(_readYaml(envFile));
      }
    }

    final home = homePath ?? Platform.environment['HOME'] ?? '';
    if (!standardMode) {
      final secretsPath = '$home/.flowbrain/secrets.yaml';
      final secretsFile = File(secretsPath);
      if (secretsFile.existsSync()) {
        _log.fine('Loading secrets overlay: $secretsPath');
        layers.add(_readYaml(secretsFile));
      }
    } else {
      final userPath = '$home/.flowbrain/user.yaml';
      final userFile = File(userPath);
      if (userFile.existsSync()) {
        _log.fine('Loading user overlay: $userPath');
        layers.add(_readYaml(userFile));
      }
    }

    final merged = _deepMergeLayers(layers);

    // Run schema migration before deserialization
    final migrated = ConfigMigrator.migrate(merged);

    return FlowBrainConfig.fromJson(migrated);
  }

  /// Build a configuration programmatically from Dart code.
  static FlowBrainConfig build(void Function(FlowBrainConfigBuilder) setup) {
    final b = FlowBrainConfigBuilder();
    setup(b);
    return b.build();
  }

  /// Parse a YAML file into a Map.
  static Map<String, dynamic> _readYaml(File file) {
    try {
      final content = file.readAsStringSync();
      final parsed = loadYaml(content);
      if (parsed == null) return {};
      return _yamlToMap(parsed);
    } on YamlException catch (e) {
      throw SchemaError('YAML parse error: $e');
    }
  }

  /// Derive the environment overlay path from the base path and env name.
  static String _deriveEnvPath(String basePath, String env) {
    final dot = basePath.lastIndexOf('.');
    if (dot < 0) return '$basePath.$env';
    return '${basePath.substring(0, dot)}.$env${basePath.substring(dot)}';
  }

  /// Deep merge multiple layers, later layers take priority.
  static Map<String, dynamic> _deepMergeLayers(
    List<Map<String, dynamic>> layers,
  ) {
    var result = <String, dynamic>{};
    for (final layer in layers) {
      result = _deepMerge(result, layer);
    }
    return result;
  }

  /// Recursively merge two maps. Values in [overlay] take priority.
  /// Null values in overlay do not overwrite base values.
  static Map<String, dynamic> _deepMerge(
    Map<String, dynamic> base,
    Map<String, dynamic> overlay,
  ) {
    final result = Map<String, dynamic>.from(base);
    for (final entry in overlay.entries) {
      if (entry.value == null) continue;
      final baseVal = result[entry.key];
      if (baseVal is Map<String, dynamic> &&
          entry.value is Map<String, dynamic>) {
        result[entry.key] = _deepMerge(
          baseVal,
          entry.value as Map<String, dynamic>,
        );
      } else {
        result[entry.key] = entry.value;
      }
    }
    return result;
  }

  /// Convert YamlMap/YamlList to plain Dart types.
  static dynamic _yamlToMap(dynamic value) {
    if (value is YamlMap) {
      return value.map<String, dynamic>(
        (k, v) => MapEntry(k.toString(), _yamlToMap(v)),
      );
    }
    if (value is YamlList) {
      return value.map(_yamlToMap).toList();
    }
    return value;
  }
}

/// Builder for creating FlowBrainConfig programmatically.
class FlowBrainConfigBuilder {
  int configVersion = 1;
  String profile = 'full';
  String llmType = 'custom';
  String? llmModel;
  String llmApiKey = '';
  String storageType = 'memory';
  Map<String, dynamic> storageOptions = {};
  List<BundleRef> bundles = [];
  Map<String, AgentDef> agents = {};
  ObservabilityConfig? observability;
  PolicyConfig? policy;
  Map<String, dynamic> extensions = {};

  FlowBrainConfig build() {
    return FlowBrainConfig(
      configVersion: configVersion,
      profile: profile,
      providers: ProvidersConfig(
        llm: LlmProviderConfig(
          type: llmType,
          model: llmModel,
          apiKey: SecretRef.parse(llmApiKey),
        ),
        storage: StorageProviderConfig(
          type: storageType,
          options: storageOptions,
        ),
      ),
      bundles: bundles,
      agents: agents,
      observability: observability,
      policy: policy,
      extensions: extensions,
    );
  }
}
