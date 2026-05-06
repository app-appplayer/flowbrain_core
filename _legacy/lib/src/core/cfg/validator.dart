import 'package:logging/logging.dart';

import 'schema/flowbrain_config.dart';

final _log = Logger('ConfigValidator');

/// Known LLM provider types.
const _knownLlmProviders = {
  'claude',
  'openai',
  'gemini',
  'bedrock',
  'cohere',
  'groq',
  'mistral',
  'together',
  'vertex_ai',
  'custom',
};

/// Validates a FlowBrainConfig for boot-readiness.
///
/// Errors cause boot failure (fail-fast). Warnings are logged but allowed.
class ConfigValidator {
  /// Validate the given configuration, returning a report of issues found.
  static ValidationReport validate(
    FlowBrainConfig config, {
    bool inlineSecretsAllowed = false,
  }) {
    final errors = <ValidationIssue>[];
    final warnings = <ValidationIssue>[];

    // 1. Schema version check
    if (config.configVersion < 1) {
      errors.add(ValidationIssue(
        path: 'configVersion',
        message: 'configVersion must be >= 1, got ${config.configVersion}',
      ));
    }

    // 2. Inline secret detection
    _checkInlineSecrets(
      config,
      errors: errors,
      warnings: warnings,
      allowed: inlineSecretsAllowed,
    );

    // 3. Provider availability check
    _checkProviderType(config, errors: errors);

    // 4. MCP topology consistency
    _checkMcpTopology(config, errors: errors, warnings: warnings);

    final report = ValidationReport(errors: errors, warnings: warnings);

    for (final w in warnings) {
      _log.warning('Config warning [${w.path}]: ${w.message}');
    }

    return report;
  }

  /// Recursively check all SecretRef values for inline secrets.
  static void _checkInlineSecrets(
    FlowBrainConfig config, {
    required List<ValidationIssue> errors,
    required List<ValidationIssue> warnings,
    required bool allowed,
  }) {
    final refs = _collectSecretRefs(config);
    for (final entry in refs.entries) {
      if (entry.value is InlineSecret) {
        final issue = ValidationIssue(
          path: entry.key,
          message:
              'Found inline secret at "${entry.key}". '
              'Use \$env:, \$file:, or \$vault: references instead.',
          suggestion: 'Replace with \$env:YOUR_SECRET_NAME',
        );
        if (allowed) {
          warnings.add(issue);
        } else {
          errors.add(issue);
        }
      }
    }
  }

  /// Collect all SecretRef instances with their config paths.
  static Map<String, SecretRef> _collectSecretRefs(FlowBrainConfig config) {
    final refs = <String, SecretRef>{};
    refs['providers.llm.apiKey'] = config.providers.llm.apiKey;
    if (config.providers.storage.credentials != null) {
      refs['providers.storage.credentials'] =
          config.providers.storage.credentials!;
    }
    // Check MCP auth secrets
    final mcp = config.providers.llm.mcp;
    if (mcp != null) {
      for (var i = 0; i < mcp.servers.length; i++) {
        final auth = mcp.servers[i].auth;
        if (auth is BearerAuth) {
          refs['providers.llm.mcp.servers[$i].auth.token'] = auth.token;
        }
        if (auth is OAuth2Auth && auth.clientSecret != null) {
          refs['providers.llm.mcp.servers[$i].auth.clientSecret'] =
              auth.clientSecret!;
        }
      }
      for (var i = 0; i < mcp.clients.length; i++) {
        final auth = mcp.clients[i].auth;
        if (auth is BearerAuth) {
          refs['providers.llm.mcp.clients[$i].auth.token'] = auth.token;
        }
        if (auth is OAuth2Auth && auth.clientSecret != null) {
          refs['providers.llm.mcp.clients[$i].auth.clientSecret'] =
              auth.clientSecret!;
        }
      }
    }
    return refs;
  }

  /// Check that the LLM provider type is recognized.
  static void _checkProviderType(
    FlowBrainConfig config, {
    required List<ValidationIssue> errors,
  }) {
    final type = config.providers.llm.type;
    if (!_knownLlmProviders.contains(type)) {
      errors.add(ValidationIssue(
        path: 'providers.llm.type',
        message: 'Unknown LLM provider "$type"',
        suggestion:
            'Supported: ${_knownLlmProviders.join(", ")}',
      ));
    }
  }

  /// Check MCP topology: duplicate ports, duplicate ids, transport requirements.
  static void _checkMcpTopology(
    FlowBrainConfig config, {
    required List<ValidationIssue> errors,
    required List<ValidationIssue> warnings,
  }) {
    final mcp = config.providers.llm.mcp;
    if (mcp == null) return;

    // Check duplicate server ports
    final ports = <int>[];
    for (var i = 0; i < mcp.servers.length; i++) {
      final port = mcp.servers[i].port;
      if (port != null) {
        if (ports.contains(port)) {
          errors.add(ValidationIssue(
            path: 'providers.llm.mcp.servers[$i].port',
            message: 'Found duplicate MCP server port $port',
          ));
        }
        ports.add(port);
      }
    }

    // Check duplicate client ids
    final clientIds = <String>{};
    for (var i = 0; i < mcp.clients.length; i++) {
      final id = mcp.clients[i].id;
      if (!clientIds.add(id)) {
        errors.add(ValidationIssue(
          path: 'providers.llm.mcp.clients[$i].id',
          message: 'Found duplicate MCP client id "$id"',
        ));
      }
    }

    // Check transport requirements
    for (var i = 0; i < mcp.clients.length; i++) {
      final client = mcp.clients[i];
      if (client.transport == McpTransport.http ||
          client.transport == McpTransport.sse) {
        if (client.url == null || client.url!.isEmpty) {
          errors.add(ValidationIssue(
            path: 'providers.llm.mcp.clients[$i]',
            message:
                'MCP client "${client.id}" with ${client.transport.name} '
                'transport requires a url',
          ));
        }
      }
      if (client.transport == McpTransport.stdio) {
        if (client.command == null || client.command!.isEmpty) {
          errors.add(ValidationIssue(
            path: 'providers.llm.mcp.clients[$i]',
            message:
                'MCP client "${client.id}" with stdio transport '
                'requires a command',
          ));
        }
      }
    }
  }
}

/// Error thrown when validation fails and throwIfErrors is called.
class ValidationError implements Exception {
  final List<ValidationIssue> issues;

  const ValidationError(this.issues);

  factory ValidationError.fromIssues(List<ValidationIssue> issues) =>
      ValidationError(issues);

  @override
  String toString() {
    final buf = StringBuffer('ValidationError:\n');
    for (final issue in issues) {
      buf.writeln('  [${issue.path}] ${issue.message}');
      if (issue.suggestion != null) {
        buf.writeln('    suggestion: ${issue.suggestion}');
      }
    }
    return buf.toString();
  }
}

/// Report of validation errors and warnings.
class ValidationReport {
  final List<ValidationIssue> errors;
  final List<ValidationIssue> warnings;

  const ValidationReport({
    this.errors = const [],
    this.warnings = const [],
  });

  bool get hasErrors => errors.isNotEmpty;
  bool get isValid => errors.isEmpty;

  /// Throw a ValidationError if there are any errors.
  void throwIfErrors() {
    if (hasErrors) throw ValidationError.fromIssues(errors);
  }
}

/// A single validation issue found during config checking.
class ValidationIssue {
  final String path;
  final int? line;
  final String message;
  final String? suggestion;

  const ValidationIssue({
    required this.path,
    this.line,
    required this.message,
    this.suggestion,
  });
}
