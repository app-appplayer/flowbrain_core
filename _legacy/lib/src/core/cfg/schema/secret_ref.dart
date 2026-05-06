/// Secret reference types for configuration values.
///
/// SecretRef is a sealed class hierarchy representing different ways
/// to reference secrets: environment variables, files, vault keys,
/// or inline values (which are rejected by the validator in production).
sealed class SecretRef {
  const SecretRef();

  /// Parse a raw string into the appropriate SecretRef subtype.
  factory SecretRef.parse(String raw) {
    if (raw.startsWith(r'$env:')) return EnvSecret(raw.substring(5));
    if (raw.startsWith(r'$file:')) return FileSecret(raw.substring(6));
    if (raw.startsWith(r'$vault:')) return VaultSecret(raw.substring(7));
    return InlineSecret(raw);
  }

  /// Serialize to JSON-compatible string.
  String toJson();
}

/// Secret resolved from an environment variable.
class EnvSecret extends SecretRef {
  final String name;
  const EnvSecret(this.name);

  @override
  String toJson() => '\$env:$name';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is EnvSecret && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

/// Secret read from a file path.
class FileSecret extends SecretRef {
  final String path;
  const FileSecret(this.path);

  @override
  String toJson() => '\$file:$path';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is FileSecret && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

/// Secret fetched from a vault service.
class VaultSecret extends SecretRef {
  final String key;
  const VaultSecret(this.key);

  @override
  String toJson() => '\$vault:$key';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is VaultSecret && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// Inline plaintext secret — rejected by validator in production mode.
class InlineSecret extends SecretRef {
  final String value;
  const InlineSecret(this.value);

  @override
  String toJson() => value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is InlineSecret && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Resolved secret value with masking support.
class SecretValue {
  final String _value;

  /// Whether this value was resolved from an inline secret.
  final bool fromInline;

  SecretValue(this._value, {this.fromInline = false});

  /// Reveal the plaintext value. Call only at point of use.
  String reveal() => _value;

  @override
  String toString() => '***';
}
