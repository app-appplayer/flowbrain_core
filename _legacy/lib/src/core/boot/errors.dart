/// CORE-BOOT error hierarchy per DDD §4–§5.
///
/// Extends the base [FlowBrainError] from CORE-ASM with config, bundle,
/// routing, and MCP-specific error types, plus a friendly formatter.
library;

import '../asm/errors.dart';

// Re-export base types so callers can import a single file.
export '../asm/errors.dart';

// ---------------------------------------------------------------------------
// ConfigError family
// ---------------------------------------------------------------------------

/// Configuration-related error with optional file path, line, and suggestion.
class ConfigError extends FlowBrainError {
  /// Path to the offending config file.
  final String? path;

  /// Line number in the config file (1-based), if known.
  final int? line;

  /// Actionable suggestion for fixing the error.
  final String? suggestion;

  const ConfigError(
    super.message, {
    this.path,
    this.line,
    this.suggestion,
    super.cause,
  });

  @override
  String toString() => 'ConfigError: $message';
}

/// Schema-level config error (e.g. unknown key, wrong type).
class SchemaError extends ConfigError {
  const SchemaError(
    super.message, {
    super.path,
    super.line,
    super.suggestion,
    super.cause,
  });

  @override
  String toString() => 'SchemaError: $message';
}

/// Config validation error (e.g. missing required field).
class ConfigValidationError extends ConfigError {
  const ConfigValidationError(
    super.message, {
    super.path,
    super.line,
    super.suggestion,
    super.cause,
  });

  @override
  String toString() => 'ConfigValidationError: $message';
}

/// Secret resolution error (e.g. env var not found).
class SecretError extends ConfigError {
  const SecretError(
    super.message, {
    super.path,
    super.line,
    super.suggestion,
    super.cause,
  });

  @override
  String toString() => 'SecretError: $message';
}

/// Config migration error (e.g. schema version upgrade failed).
class MigrationError extends ConfigError {
  const MigrationError(
    super.message, {
    super.path,
    super.line,
    super.suggestion,
    super.cause,
  });

  @override
  String toString() => 'MigrationError: $message';
}

// ---------------------------------------------------------------------------
// BundleError family
// ---------------------------------------------------------------------------

/// Bundle (knowledge pack) related error.
class BundleError extends FlowBrainError {
  const BundleError(super.message, {super.cause});

  @override
  String toString() => 'BundleError: $message';
}

/// Bundle integrity check failed (e.g. checksum mismatch).
class IntegrityError extends BundleError {
  const IntegrityError(super.message, {super.cause});

  @override
  String toString() => 'IntegrityError: $message';
}

/// Bundle schema version mismatch.
class SchemaVersionError extends BundleError {
  const SchemaVersionError(super.message, {super.cause});

  @override
  String toString() => 'SchemaVersionError: $message';
}

/// Bundle rollback failed.
class RollbackError extends BundleError {
  const RollbackError(super.message, {super.cause});

  @override
  String toString() => 'RollbackError: $message';
}

// ---------------------------------------------------------------------------
// Routing & MCP errors
// ---------------------------------------------------------------------------

/// Routing error (e.g. no handler for the given request).
class RoutingError extends FlowBrainError {
  const RoutingError(super.message, {super.cause});

  @override
  String toString() => 'RoutingError: $message';
}

/// MCP binding error (server startup, client connection, etc.).
class McpBindingError extends FlowBrainError {
  const McpBindingError(super.message, {super.cause});

  @override
  String toString() => 'McpBindingError: $message';
}

// ---------------------------------------------------------------------------
// Exit code mapping
// ---------------------------------------------------------------------------

/// Map a [FlowBrainError] to its DDD-defined exit code.
///
/// | Code | Meaning             |
/// |------|---------------------|
/// | 0    | Normal exit         |
/// | 1    | General error       |
/// | 2    | ConfigError         |
/// | 3    | AssemblyError       |
/// | 4    | BundleError         |
/// | 5    | RuntimeWiringError / RoutingError / McpBindingError |
/// | 130  | SIGINT (Ctrl-C)     |
int exitCodeFor(FlowBrainError error) {
  if (error is ConfigError) return 2;
  if (error is BundleError) return 4;
  if (error is AssemblyError) return 3;
  if (error is RoutingError) return 5;
  if (error is McpBindingError) return 5;
  return 1;
}

// ---------------------------------------------------------------------------
// FriendlyErrorFormatter
// ---------------------------------------------------------------------------

/// Produces human-readable, actionable error messages for CLI output.
class FriendlyErrorFormatter {
  /// Format a [FlowBrainError] for friendly CLI display.
  static String format(FlowBrainError error) {
    if (error is ConfigError) return _formatConfig(error);
    if (error is AssemblyError) return _formatAssembly(error);
    if (error is BundleError) return _formatBundle(error);
    return error.toString();
  }

  static String _formatConfig(ConfigError e) {
    final buf = StringBuffer();
    final location = e.line != null ? '${e.path}:${e.line}' : '${e.path}';
    buf.writeln('[X] Config error at $location');
    buf.writeln('  ${e.message}');
    if (e.suggestion != null) {
      buf.writeln('  -> ${e.suggestion}');
    }
    buf.writeln();
    buf.writeln('Run `flowbrain doctor` for full diagnostics.');
    return buf.toString();
  }

  static String _formatAssembly(AssemblyError e) {
    final buf = StringBuffer();
    buf.writeln('[X] Assembly error');
    buf.writeln('  ${e.message}');
    buf.writeln();
    buf.writeln('Run `flowbrain doctor` for full diagnostics.');
    return buf.toString();
  }

  static String _formatBundle(BundleError e) {
    final buf = StringBuffer();
    buf.writeln('[X] Bundle error');
    buf.writeln('  ${e.message}');
    buf.writeln();
    buf.writeln('Run `flowbrain pack list` to verify installed packs.');
    return buf.toString();
  }
}
