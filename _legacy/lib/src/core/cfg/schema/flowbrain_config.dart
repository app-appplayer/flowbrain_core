import 'secret_ref.dart';
import 'mcp_refs.dart';
import 'agents_config.dart';

// Re-export schema types for convenience
export 'secret_ref.dart';
export 'mcp_refs.dart';
export 'agents_config.dart';

/// Log level for observability configuration.
enum LogLevel { trace, debug, info, warn, error, fatal }

/// Log output format.
enum LogFormat { text, json }

/// Audit level for policy configuration.
enum AuditLevel { none, basic, full }

/// Auto-update policy for bundle references.
enum AutoUpdatePolicy { manual, notify, auto }

/// Root configuration for FlowBrain.
class FlowBrainConfig {
  final int configVersion;
  final String profile;
  final ProvidersConfig providers;
  final List<BundleRef> bundles;
  final Map<String, AgentDef> agents;
  final ObservabilityConfig observability;
  final PolicyConfig policy;
  final Map<String, dynamic> extensions;

  const FlowBrainConfig({
    required this.configVersion,
    required this.profile,
    required this.providers,
    this.bundles = const [],
    this.agents = const {},
    ObservabilityConfig? observability,
    PolicyConfig? policy,
    this.extensions = const {},
  })  : observability = observability ?? const ObservabilityConfig(),
        policy = policy ?? const PolicyConfig();

  factory FlowBrainConfig.fromJson(Map<String, dynamic> json) {
    // Supports both camelCase (Dart convention) and snake_case (YAML convention).
    return FlowBrainConfig(
      configVersion:
          (json['configVersion'] ?? json['config_version']) as int? ?? 1,
      profile: json['profile'] as String? ?? 'full',
      providers: ProvidersConfig.fromJson(
        json['providers'] as Map<String, dynamic>? ?? {},
      ),
      bundles: (json['bundles'] as List<dynamic>?)
              ?.map(
                  (e) => BundleRef.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      agents: (json['agents'] as Map<String, dynamic>?)?.map(
            (k, v) =>
                MapEntry(k, AgentDef.fromJson(v as Map<String, dynamic>)),
          ) ??
          const {},
      observability: json['observability'] != null
          ? ObservabilityConfig.fromJson(
              json['observability'] as Map<String, dynamic>)
          : const ObservabilityConfig(),
      policy: json['policy'] != null
          ? PolicyConfig.fromJson(json['policy'] as Map<String, dynamic>)
          : const PolicyConfig(),
      extensions:
          (json['extensions'] as Map<String, dynamic>?) ?? const {},
    );
  }

  Map<String, dynamic> toJson() => {
        'configVersion': configVersion,
        'profile': profile,
        'providers': providers.toJson(),
        if (bundles.isNotEmpty)
          'bundles': bundles.map((b) => b.toJson()).toList(),
        if (agents.isNotEmpty)
          'agents': agents.map((k, v) => MapEntry(k, v.toJson())),
        'observability': observability.toJson(),
        'policy': policy.toJson(),
        if (extensions.isNotEmpty) 'extensions': extensions,
      };

  /// Create a copy with specified fields replaced.
  FlowBrainConfig copyWith({
    int? configVersion,
    String? profile,
    ProvidersConfig? providers,
    List<BundleRef>? bundles,
    Map<String, AgentDef>? agents,
    ObservabilityConfig? observability,
    PolicyConfig? policy,
    Map<String, dynamic>? extensions,
  }) {
    return FlowBrainConfig(
      configVersion: configVersion ?? this.configVersion,
      profile: profile ?? this.profile,
      providers: providers ?? this.providers,
      bundles: bundles ?? this.bundles,
      agents: agents ?? this.agents,
      observability: observability ?? this.observability,
      policy: policy ?? this.policy,
      extensions: extensions ?? this.extensions,
    );
  }
}

/// Provider configuration (LLM + Storage).
class ProvidersConfig {
  final LlmProviderConfig llm;
  final StorageProviderConfig storage;

  const ProvidersConfig({
    required this.llm,
    required this.storage,
  });

  factory ProvidersConfig.fromJson(Map<String, dynamic> json) {
    return ProvidersConfig(
      llm: LlmProviderConfig.fromJson(
        json['llm'] as Map<String, dynamic>? ?? {},
      ),
      storage: StorageProviderConfig.fromJson(
        json['storage'] as Map<String, dynamic>? ?? {},
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'llm': llm.toJson(),
        'storage': storage.toJson(),
      };
}

/// LLM provider configuration.
class LlmProviderConfig {
  final String type;
  final String? model;
  final SecretRef apiKey;
  final Map<String, dynamic> options;
  final LlmMcpConfig? mcp;

  const LlmProviderConfig({
    required this.type,
    required this.apiKey,
    this.model,
    this.options = const {},
    this.mcp,
  });

  factory LlmProviderConfig.fromJson(Map<String, dynamic> json) {
    return LlmProviderConfig(
      type: json['type'] as String? ?? 'custom',
      model: json['model'] as String?,
      apiKey: SecretRef.parse(
        (json['apiKey'] ?? json['api_key']) as String? ?? '',
      ),
      options:
          (json['options'] as Map<String, dynamic>?) ?? const {},
      mcp: json['mcp'] != null
          ? LlmMcpConfig.fromJson(json['mcp'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        if (model != null) 'model': model,
        'apiKey': apiKey.toJson(),
        if (options.isNotEmpty) 'options': options,
        if (mcp != null) 'mcp': mcp!.toJson(),
      };
}

/// Nested MCP configuration within LLM provider.
class LlmMcpConfig {
  final List<McpServerRef> servers;
  final List<McpClientRef> clients;

  const LlmMcpConfig({
    this.servers = const [],
    this.clients = const [],
  });

  factory LlmMcpConfig.fromJson(Map<String, dynamic> json) {
    return LlmMcpConfig(
      servers: (json['servers'] as List<dynamic>?)
              ?.map((e) =>
                  McpServerRef.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      clients: (json['clients'] as List<dynamic>?)
              ?.map((e) =>
                  McpClientRef.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
        if (servers.isNotEmpty)
          'servers': servers.map((s) => s.toJson()).toList(),
        if (clients.isNotEmpty)
          'clients': clients.map((c) => c.toJson()).toList(),
      };
}

/// Storage provider configuration.
class StorageProviderConfig {
  final String type;
  final Map<String, dynamic> options;
  final SecretRef? credentials;

  const StorageProviderConfig({
    required this.type,
    this.options = const {},
    this.credentials,
  });

  factory StorageProviderConfig.fromJson(Map<String, dynamic> json) {
    return StorageProviderConfig(
      type: json['type'] as String? ?? 'memory',
      options:
          (json['options'] as Map<String, dynamic>?) ?? const {},
      credentials: json['credentials'] != null
          ? SecretRef.parse(json['credentials'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        if (options.isNotEmpty) 'options': options,
        if (credentials != null) 'credentials': credentials!.toJson(),
      };
}

/// Bundle reference in configuration.
class BundleRef {
  final String source;
  final String? pin;
  final AutoUpdatePolicy autoUpdate;

  const BundleRef({
    required this.source,
    this.pin,
    this.autoUpdate = AutoUpdatePolicy.manual,
  });

  factory BundleRef.fromJson(Map<String, dynamic> json) {
    return BundleRef(
      source: json['source'] as String,
      pin: json['pin'] as String?,
      autoUpdate: (json['autoUpdate'] ?? json['auto_update']) != null
          ? AutoUpdatePolicy.values.byName(
              (json['autoUpdate'] ?? json['auto_update']) as String)
          : AutoUpdatePolicy.manual,
    );
  }

  Map<String, dynamic> toJson() => {
        'source': source,
        if (pin != null) 'pin': pin,
        'autoUpdate': autoUpdate.name,
      };
}

/// Observability configuration.
class ObservabilityConfig {
  final List<String> exporters;
  final double? costAlertUsdPerDay;
  final LogLevel logLevel;
  final LogFormat logFormat;

  const ObservabilityConfig({
    this.exporters = const [],
    this.costAlertUsdPerDay,
    this.logLevel = LogLevel.info,
    this.logFormat = LogFormat.text,
  });

  factory ObservabilityConfig.fromJson(Map<String, dynamic> json) {
    return ObservabilityConfig(
      exporters: (json['exporters'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      costAlertUsdPerDay:
          ((json['costAlertUsdPerDay'] ?? json['cost_alert_usd_per_day'])
                  as num?)
              ?.toDouble(),
      logLevel: (json['logLevel'] ?? json['log_level']) != null
          ? LogLevel.values
              .byName((json['logLevel'] ?? json['log_level']) as String)
          : LogLevel.info,
      logFormat: (json['logFormat'] ?? json['log_format']) != null
          ? LogFormat.values
              .byName((json['logFormat'] ?? json['log_format']) as String)
          : LogFormat.text,
    );
  }

  Map<String, dynamic> toJson() => {
        if (exporters.isNotEmpty) 'exporters': exporters,
        if (costAlertUsdPerDay != null)
          'costAlertUsdPerDay': costAlertUsdPerDay,
        'logLevel': logLevel.name,
        'logFormat': logFormat.name,
      };
}

/// Policy configuration.
class PolicyConfig {
  final PhilosophyPolicy philosophy;
  final ApprovalPolicy approval;
  final AuditPolicy audit;
  final String defaultLanguage;

  const PolicyConfig({
    this.philosophy = const PhilosophyPolicy(),
    this.approval = const ApprovalPolicy(),
    this.audit = const AuditPolicy(),
    this.defaultLanguage = 'en',
  });

  factory PolicyConfig.fromJson(Map<String, dynamic> json) {
    return PolicyConfig(
      philosophy: json['philosophy'] != null
          ? PhilosophyPolicy.fromJson(
              json['philosophy'] as Map<String, dynamic>)
          : const PhilosophyPolicy(),
      approval: json['approval'] != null
          ? ApprovalPolicy.fromJson(
              json['approval'] as Map<String, dynamic>)
          : const ApprovalPolicy(),
      audit: json['audit'] != null
          ? AuditPolicy.fromJson(json['audit'] as Map<String, dynamic>)
          : const AuditPolicy(),
      defaultLanguage:
          (json['defaultLanguage'] ?? json['default_language'])
              as String? ??
          'en',
    );
  }

  Map<String, dynamic> toJson() => {
        'philosophy': philosophy.toJson(),
        'approval': approval.toJson(),
        'audit': audit.toJson(),
        'defaultLanguage': defaultLanguage,
      };
}

/// Philosophy intervention policy.
///
/// Uses String set for intervention points to avoid hard dependency
/// on mcp_bundle's InterventionPoint enum at the config layer.
class PhilosophyPolicy {
  final Set<String> enabledPoints;

  const PhilosophyPolicy({
    this.enabledPoints = const {'preGeneration', 'postGeneration'},
  });

  factory PhilosophyPolicy.fromJson(Map<String, dynamic> json) {
    return PhilosophyPolicy(
      enabledPoints:
          ((json['enabledPoints'] ?? json['enabled_points']) as List<dynamic>?)
                  ?.map((e) => e as String)
                  .toSet() ??
              const {'preGeneration', 'postGeneration'},
    );
  }

  Map<String, dynamic> toJson() => {
        'enabledPoints': enabledPoints.toList(),
      };
}

/// Approval policy: which operations require explicit approval.
class ApprovalPolicy {
  final Set<String> requiredFor;

  const ApprovalPolicy({
    this.requiredFor = const {},
  });

  factory ApprovalPolicy.fromJson(Map<String, dynamic> json) {
    return ApprovalPolicy(
      requiredFor:
          ((json['requiredFor'] ?? json['required_for']) as List<dynamic>?)
                  ?.map((e) => e as String)
                  .toSet() ??
              const {},
    );
  }

  Map<String, dynamic> toJson() => {
        'requiredFor': requiredFor.toList(),
      };
}

/// Audit policy.
class AuditPolicy {
  final AuditLevel level;

  const AuditPolicy({this.level = AuditLevel.basic});

  factory AuditPolicy.fromJson(Map<String, dynamic> json) {
    return AuditPolicy(
      level: json['level'] != null
          ? AuditLevel.values.byName(json['level'] as String)
          : AuditLevel.basic,
    );
  }

  Map<String, dynamic> toJson() => {
        'level': level.name,
      };
}
