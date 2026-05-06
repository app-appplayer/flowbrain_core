/// FlowBrain Core — Agent Subsystem events (7 types).
///
/// All Agent events implement `KnowledgeEvent` (from `mcp_knowledge`) and are
/// published on the same `KnowledgeEventBus` as the 13 Knowledge events. See:
///
///   - `os/core/flowbrain/docs/03_DDD/04-event-bus.md`
///   - FR-FBCORE-AGT-060..066
library;

import 'package:mcp_knowledge/mcp_knowledge.dart' show KnowledgeEvent;

import 'agent_models.dart';

/// `agent_created` — emitted by `AgentFacade.createAgent`.
class AgentCreatedEvent implements KnowledgeEvent {
  const AgentCreatedEvent({
    required this.agentId,
    required this.displayName,
    required this.role,
    required this.model,
    required this.timestamp,
  });

  final String agentId;
  final String displayName;
  final AgentRole role;
  final ModelSpec model;

  @override
  final DateTime timestamp;

  @override
  String get type => 'agent_created';
}

/// `agent_deleted` — emitted by `AgentFacade.deleteAgent`.
class AgentDeletedEvent implements KnowledgeEvent {
  const AgentDeletedEvent({
    required this.agentId,
    required this.timestamp,
  });

  final String agentId;

  @override
  final DateTime timestamp;

  @override
  String get type => 'agent_deleted';
}

/// `agent_invoked` — emitted by `AgentFacade.ask`/`stream` at completion
/// (success or failure). Carries success flag + duration + token usage.
class AgentInvokedEvent implements KnowledgeEvent {
  const AgentInvokedEvent({
    required this.agentId,
    required this.model,
    required this.turnIndex,
    required this.success,
    required this.duration,
    required this.timestamp,
    this.tokenUsage,
  });

  final String agentId;
  final String model;
  final int turnIndex;
  final bool success;
  final Duration duration;
  final TokenUsage? tokenUsage;

  @override
  final DateTime timestamp;

  @override
  String get type => 'agent_invoked';
}

/// `agent_fork_assigned` — emitted by `AgentFacade.assign*` after deep copy
/// (or sourceRef registration in copy-on-write mode).
class AgentForkAssignedEvent implements KnowledgeEvent {
  const AgentForkAssignedEvent({
    required this.agentId,
    required this.axis,
    required this.sourceRef,
    required this.forkedRef,
    required this.timestamp,
  });

  final String agentId;
  final AgentAxis axis;
  final String sourceRef;
  final String forkedRef;

  @override
  final DateTime timestamp;

  @override
  String get type => 'agent_fork_assigned';
}

/// `agent_fork_evolved` — emitted by `AgentRegistry.recordEvolution` when
/// Growth Tracker detects a mutation in an agent-owned 4-axis instance.
class AgentForkEvolvedEvent implements KnowledgeEvent {
  const AgentForkEvolvedEvent({
    required this.agentId,
    required this.axis,
    required this.forkedRef,
    required this.kind,
    required this.timestamp,
  });

  final String agentId;
  final AgentAxis axis;
  final String forkedRef;
  final GrowthKind kind;

  @override
  final DateTime timestamp;

  @override
  String get type => 'agent_fork_evolved';
}

/// `manager_routed` — emitted by `AgentFacade.route`.
class ManagerRoutedEvent implements KnowledgeEvent {
  const ManagerRoutedEvent({
    required this.managerId,
    required this.targetAgentId,
    required this.confidence,
    required this.timestamp,
    this.reason,
  });

  final String managerId;
  final String targetAgentId;
  final double confidence;
  final String? reason;

  @override
  final DateTime timestamp;

  @override
  String get type => 'manager_routed';
}

/// `reviewer_verified` — emitted by `AgentFacade.review`.
class ReviewerVerifiedEvent implements KnowledgeEvent {
  const ReviewerVerifiedEvent({
    required this.reviewerId,
    required this.targetAgentId,
    required this.verdict,
    required this.timestamp,
    this.severity,
  });

  final String reviewerId;
  final String targetAgentId;
  final ReviewVerdict verdict;
  final ReviewSeverity? severity;

  @override
  final DateTime timestamp;

  @override
  String get type => 'reviewer_verified';
}

/// `lazy_fork_materialized` — emitted by `ForkEngine.materialize` when a
/// `LazyOwnedFork` (stored under `forkPolicy: ForkPolicy.copyOnWrite`)
/// is converted into an eager `OwnedFork`. Hosts listen to track the
/// transition cost and to confirm explicit materialize calls completed
/// successfully.
class LazyForkMaterializedEvent implements KnowledgeEvent {
  const LazyForkMaterializedEvent({
    required this.agentId,
    required this.axis,
    required this.sourceRef,
    required this.forkedRef,
    required this.timestamp,
  });

  final String agentId;
  final AgentAxis axis;
  final String sourceRef;
  final String forkedRef;

  @override
  final DateTime timestamp;

  @override
  String get type => 'lazy_fork_materialized';
}

/// `kv_index_corruption` — emitted by `AgentRegistry` whenever a `_kv`
/// index entry (per-axis owned-fork index, or an Agent JSON record) fails
/// to deserialize. The registry recovers gracefully (treats the entry as
/// empty / resets on next write), but hosts that wire this event can
/// surface the corruption to operators or to a diagnostics sink — silent
/// recovery is otherwise invisible.
///
/// `keyKind` is one of `'agent'`, `'index'`, `'owned'` (per [_kind]
/// strings produced by `agent_registry.dart`); `key` is the raw KV key
/// that failed to deserialize.
class KvIndexCorruptionEvent implements KnowledgeEvent {
  const KvIndexCorruptionEvent({
    required this.agentId,
    required this.keyKind,
    required this.key,
    required this.error,
    required this.timestamp,
  });

  final String agentId;
  final String keyKind;
  final String key;
  final String error;

  @override
  final DateTime timestamp;

  @override
  String get type => 'kv_index_corruption';
}

/// `agent_lifecycle_fact_failed` — emitted when the lifecycle fact mirror
/// (FR-FBCORE-AGT-080..087) fails to write a `FactRecord`. Hosts listen
/// to this to surface silent fact-write errors that would otherwise be
/// invisible (since `recordLifecycleAsFacts` is best-effort by design).
///
/// Triggered from `ForkEngine._store`, `AgentRegistry.delete`,
/// `AgentRegistry.recordEvolution`, and `AgentRuntime.ask` whenever
/// `system.facts.writeFacts(...)` throws. The agent operation itself
/// (storeOwned / delete / record / ask) still completes — the event is
/// purely observability for diagnosing FactGraph adapter issues.
class AgentLifecycleFactFailedEvent implements KnowledgeEvent {
  const AgentLifecycleFactFailedEvent({
    required this.agentId,
    required this.factType,
    required this.error,
    required this.timestamp,
  });

  final String agentId;

  /// One of [AgentLifecycleFactType] — `agent.fork.assigned`,
  /// `agent.fork.evolved`, `agent.invoked`, or `agent.deleted`.
  final String factType;

  /// String form of the underlying exception (`e.toString()`). Hosts that
  /// want the original `Object`/StackTrace should hook the FactsPort
  /// adapter directly.
  final String error;

  @override
  final DateTime timestamp;

  @override
  String get type => 'agent_lifecycle_fact_failed';
}
