import 'dart:io';

import 'package:logging/logging.dart';

import 'schema/flowbrain_config.dart';

export 'schema/secret_ref.dart' show SecretValue;

final _log = Logger('SecretResolver');

/// Error thrown when a secret cannot be resolved.
class SecretError implements Exception {
  final String message;
  const SecretError(this.message);

  @override
  String toString() => 'SecretError: $message';
}

/// Abstract adapter for vault-based secret storage.
abstract class VaultAdapter {
  String get name;
  Future<String?> read(String key);
}

/// Resolves SecretRef instances to their actual values.
class SecretResolver {
  final List<VaultAdapter> vaultAdapters;

  /// Optional environment overrides for testing.
  final Map<String, String>? _envOverrides;

  SecretResolver({
    this.vaultAdapters = const [],
    Map<String, String>? environmentOverrides,
  }) : _envOverrides = environmentOverrides;

  /// Resolve all secret references found in the configuration.
  Future<ResolvedSecrets> resolveAll(FlowBrainConfig config) async {
    final resolved = <SecretRef, SecretValue>{};
    final refs = _collectAllRefs(config);
    for (final ref in refs) {
      resolved[ref] = await _resolve(ref);
    }
    return ResolvedSecrets(resolved);
  }

  /// Collect all SecretRef instances from the config.
  Set<SecretRef> _collectAllRefs(FlowBrainConfig config) {
    final refs = <SecretRef>{};
    refs.add(config.providers.llm.apiKey);
    if (config.providers.storage.credentials != null) {
      refs.add(config.providers.storage.credentials!);
    }
    final mcp = config.providers.llm.mcp;
    if (mcp != null) {
      for (final server in mcp.servers) {
        _collectAuthRefs(server.auth, refs);
      }
      for (final client in mcp.clients) {
        _collectAuthRefs(client.auth, refs);
      }
    }
    return refs;
  }

  void _collectAuthRefs(Auth? auth, Set<SecretRef> refs) {
    if (auth is BearerAuth) {
      refs.add(auth.token);
    } else if (auth is OAuth2Auth && auth.clientSecret != null) {
      refs.add(auth.clientSecret!);
    }
  }

  Future<SecretValue> _resolve(SecretRef ref) async {
    return switch (ref) {
      EnvSecret(:final name) => _resolveEnv(name),
      FileSecret(:final path) => await _resolveFile(path),
      VaultSecret(:final key) => await _resolveVault(key),
      InlineSecret(:final value) => SecretValue(value, fromInline: true),
    };
  }

  SecretValue _resolveEnv(String name) {
    final env = _envOverrides ?? Platform.environment;
    final value = env[name];
    if (value == null) {
      throw SecretError('env variable "$name" is not set');
    }
    _log.fine('Resolved env secret: $name');
    return SecretValue(value);
  }

  Future<SecretValue> _resolveFile(String path) async {
    try {
      final content = await File(path).readAsString();
      _log.fine('Resolved file secret: $path');
      return SecretValue(content.trim());
    } on FileSystemException catch (e) {
      throw SecretError('Failed to read secret file "$path": $e');
    }
  }

  Future<SecretValue> _resolveVault(String key) async {
    for (final adapter in vaultAdapters) {
      final value = await adapter.read(key);
      if (value != null) {
        _log.fine('Resolved vault secret "$key" via ${adapter.name}');
        return SecretValue(value);
      }
    }
    throw SecretError(
      'vault key "$key" not found in any adapter '
      '(tried: ${vaultAdapters.map((a) => a.name).join(", ")})',
    );
  }
}

/// Container for resolved secret values, keyed by their SecretRef.
class ResolvedSecrets {
  final Map<SecretRef, SecretValue> _resolved;

  const ResolvedSecrets(this._resolved);

  /// Get the resolved value for a secret reference.
  SecretValue? get(SecretRef ref) => _resolved[ref];

  /// Get the resolved value, throwing if not found.
  SecretValue require(SecretRef ref) {
    final value = _resolved[ref];
    if (value == null) {
      throw SecretError('Secret ref not resolved: $ref');
    }
    return value;
  }

  /// Indexer shorthand for [get].
  SecretValue? operator [](SecretRef? ref) =>
      ref != null ? _resolved[ref] : null;
}
