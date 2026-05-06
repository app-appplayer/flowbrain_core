/// CORE-ASM error types per SDD §7.1.
library;

/// Base class for all FlowBrain errors.
class FlowBrainError implements Exception {
  /// Human-readable error message.
  final String message;

  /// Optional cause.
  final Object? cause;

  const FlowBrainError(this.message, {this.cause});

  @override
  String toString() => 'FlowBrainError: $message';
}

/// Validation error — thrown when config or profile values are invalid.
class ValidationError extends FlowBrainError {
  const ValidationError(super.message, {super.cause});

  @override
  String toString() => 'ValidationError: $message';
}

/// Assembly error — thrown when runtime wiring fails.
class AssemblyError extends FlowBrainError {
  const AssemblyError(super.message, {super.cause});

  @override
  String toString() => 'AssemblyError: $message';
}

/// Runtime wiring error — thrown when a required runtime cannot be created.
class RuntimeWiringError extends AssemblyError {
  const RuntimeWiringError(super.message, {super.cause});

  @override
  String toString() => 'RuntimeWiringError: $message';
}

/// Port missing error — thrown when an optional port is invoked but absent.
class PortMissingError extends AssemblyError {
  const PortMissingError(super.message, {super.cause});

  @override
  String toString() => 'PortMissingError: $message';
}

// ── FEAT-ROUTE errors ────────────────────────────────────────────────────

/// Thrown when no agent could be resolved for a request.
class AgentNotFoundError extends FlowBrainError {
  const AgentNotFoundError(super.message, {super.cause});

  @override
  String toString() => 'AgentNotFoundError: $message';
}

/// Thrown when route resolution fails unexpectedly.
class RouteResolutionError extends FlowBrainError {
  const RouteResolutionError(super.message, {super.cause});

  @override
  String toString() => 'RouteResolutionError: $message';
}

