/// FlowBrain Core — Agent Subsystem exceptions.
///
/// All exceptions are flowbrain's own — independent of `mcp_knowledge`. See:
///
///   - `os/core/flowbrain/docs/03_DDD/11-agent-facade.md`
///   - FR-FBCORE-AGT-070..073
library;

import 'agent_models.dart';

/// Thrown when an agent id passed to `ask`/`stream`/`assign*`/`unassign`/
/// `update`/`delete`/`route`/`review`/`getHistory`/`clearHistory` does not
/// resolve to a registered agent (FR-FBCORE-AGT-070).
class AgentNotFoundException implements Exception {
  const AgentNotFoundException(this.agentId);
  final String agentId;
  @override
  String toString() => 'AgentNotFoundException: agent \'$agentId\' not found';
}

/// Thrown when a fork is requested for an `(agentId, axis, sourceRef)`
/// triple that already has an owned instance, and `forkPolicy` strict
/// mode is enabled (FR-FBCORE-AGT-045, AGT-071).
class ForkConflictException implements Exception {
  const ForkConflictException({
    required this.agentId,
    required this.axis,
    required this.sourceRef,
    required this.existingForkedRef,
  });

  final String agentId;
  final AgentAxis axis;
  final String sourceRef;
  final String existingForkedRef;

  @override
  String toString() =>
      'ForkConflictException: agent \'$agentId\' already has a fork '
      'for axis=${axis.name} sourceRef=\'$sourceRef\' '
      '(existing forkedRef=\'$existingForkedRef\')';
}

/// Thrown when `KvStoragePort` is not wired but Agent Subsystem is active —
/// surfaced at first `ask`/`stream` entry (FR-FBCORE-AGT-072).
class ConversationStoreUnavailableException implements Exception {
  const ConversationStoreUnavailableException(this.detail);
  final String detail;
  @override
  String toString() =>
      'ConversationStoreUnavailableException: $detail '
      '(wire `KvStoragePort` via InfraPorts.copyWith(kvStorage: adapter) '
      'or use InfraPorts.inMemory() for tests)';
}

/// Thrown when the agent's assigned Philosophy blocks a generated output at
/// work-time (hard prohibition violated), so the turn is not delivered
/// (spec `platform/12-flowbrain-runtime.md` §3).
class AgentPhilosophyBlockedException implements Exception {
  const AgentPhilosophyBlockedException({
    required this.agentId,
    this.violationIds = const [],
  });

  final String agentId;
  final List<String> violationIds;

  @override
  String toString() =>
      'AgentPhilosophyBlockedException: agent \'$agentId\' output blocked by '
      'philosophy${violationIds.isEmpty ? '' : ' (prohibitions: ${violationIds.join(', ')})'}';
}

/// Thrown when `route()` is called on a non-manager agent or `review()` on a
/// non-reviewer agent (FR-FBCORE-AGT-073).
class AgentRoleMismatchException implements Exception {
  const AgentRoleMismatchException({
    required this.agentId,
    required this.expectedRole,
    required this.actualRole,
  });

  final String agentId;
  final AgentRole expectedRole;
  final AgentRole actualRole;

  @override
  String toString() =>
      'AgentRoleMismatchException: agent \'$agentId\' has role '
      '${actualRole.name}, expected ${expectedRole.name}';
}
