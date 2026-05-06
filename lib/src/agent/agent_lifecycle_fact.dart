/// FlowBrain Core — Agent lifecycle FactRecord helpers.
///
/// Every agent lifecycle event (fork assignment / fork evolution / agent
/// invocation / agent deletion) is mirrored into the workspace FactGraph
/// when `AgentConfig.recordLifecycleAsFacts == true`. Hosts get a uniform
/// "who used what from when until when" timeline by querying the FactGraph
/// alone — no per-host event-bus plumbing required.
///
/// Fact types defined here are flowbrain's standard schema. Hosts must not
/// emit conflicting types (`agent.*`) on their own.
library;

import 'package:mcp_bundle/mcp_bundle.dart' show AbsolutePeriod, FactRecord;

import 'agent_models.dart';

/// Standard fact types emitted by the Agent Subsystem.
class AgentLifecycleFactType {
  AgentLifecycleFactType._();

  /// Emitted by `ForkEngine.assign{Skill,Profile,Philosophy,Facts}` after
  /// the owned instance has been stored. Content carries the source (pool
  /// or another agent), the resulting forkedRef, and the lineage chain.
  static const String forkAssigned = 'agent.fork.assigned';

  /// Emitted by `AgentRegistry.recordEvolution`. Content carries the
  /// `GrowthKind` and the updated counter.
  static const String forkEvolved = 'agent.fork.evolved';

  /// Emitted by `AgentRuntime.ask` after the LLM call completes (success or
  /// failure). Content carries model, turn index, success flag, duration,
  /// token usage.
  static const String agentInvoked = 'agent.invoked';

  /// Emitted by `AgentFacade.deleteAgent`. Closes the agent's open lifecycle
  /// — every prior `agent.fork.assigned` whose `agentId` matches is now
  /// effectively `until = deleted.timestamp` from a query standpoint.
  static const String agentDeleted = 'agent.deleted';

  /// All lifecycle fact type strings this builder emits. Hosts can use this
  /// to register custom FactGraph adapters or to assert that no foreign
  /// `agent.*` types leak into the workspace.
  static const List<String> values = [
    forkAssigned,
    forkEvolved,
    agentInvoked,
    agentDeleted,
  ];
}

/// Builds the canonical [FactRecord]s for each lifecycle event so the
/// emit sites stay one-liners. All records use `entityId == agentId` so
/// `FactQuery(entityId: agentId)` returns the agent's full timeline in
/// chronological order.
class AgentLifecycleFactBuilder {
  const AgentLifecycleFactBuilder();

  FactRecord forkAssigned({
    required String agentId,
    required String workspaceId,
    required AgentAxis axis,
    required ForkSource source,
    required String forkedRef,
    required List<String> lineage,
    required DateTime timestamp,
  }) {
    return FactRecord(
      id: 'agent.fork.assigned/$agentId/${axis.name}/$forkedRef/'
          '${timestamp.microsecondsSinceEpoch}',
      workspaceId: workspaceId,
      type: AgentLifecycleFactType.forkAssigned,
      entityId: agentId,
      content: {
        'agentId': agentId,
        'axis': axis.name,
        'source': source.encode(),
        'forkedRef': forkedRef,
        'lineage': lineage,
        'timestamp': timestamp.toIso8601String(),
      },
      // Point period — semantically correct (lifecycle events are
      // instantaneous, not durational). With mcp_fact_graph ≥ 0.2.1's
      // microsecond-precision overlap check
      // (`ConsistencyChecker._periodsOverlap` = `isAtSameMomentAs`),
      // distinct timestamps make consecutive lifecycle records on the
      // same (entity, factType) non-overlapping, so hosts can keep
      // `enableConsistencyCheck: true` (the default).
      period: AbsolutePeriod(start: timestamp, end: timestamp),
      createdAt: timestamp,
    );
  }

  FactRecord forkEvolved({
    required String agentId,
    required String workspaceId,
    required AgentAxis axis,
    required String forkedRef,
    required GrowthKind kind,
    required DateTime timestamp,
  }) {
    return FactRecord(
      id: 'agent.fork.evolved/$agentId/${axis.name}/$forkedRef/'
          '${timestamp.microsecondsSinceEpoch}',
      workspaceId: workspaceId,
      type: AgentLifecycleFactType.forkEvolved,
      entityId: agentId,
      content: {
        'agentId': agentId,
        'axis': axis.name,
        'forkedRef': forkedRef,
        'kind': kind.name,
        'timestamp': timestamp.toIso8601String(),
      },
      period: AbsolutePeriod(start: timestamp, end: timestamp),
      createdAt: timestamp,
    );
  }

  FactRecord agentInvoked({
    required String agentId,
    required String workspaceId,
    required String model,
    required int turnIndex,
    required bool success,
    required Duration duration,
    TokenUsage? tokenUsage,
    required DateTime timestamp,
  }) {
    return FactRecord(
      id: 'agent.invoked/$agentId/$turnIndex/'
          '${timestamp.microsecondsSinceEpoch}',
      workspaceId: workspaceId,
      type: AgentLifecycleFactType.agentInvoked,
      entityId: agentId,
      content: {
        'agentId': agentId,
        'model': model,
        'turnIndex': turnIndex,
        'success': success,
        'durationMs': duration.inMilliseconds,
        if (tokenUsage != null)
          'tokenUsage': {
            'promptTokens': tokenUsage.promptTokens,
            'completionTokens': tokenUsage.completionTokens,
            'totalTokens': tokenUsage.totalTokens,
          },
        'timestamp': timestamp.toIso8601String(),
      },
      period: AbsolutePeriod(start: timestamp, end: timestamp),
      createdAt: timestamp,
    );
  }

  FactRecord agentDeleted({
    required String agentId,
    required String workspaceId,
    required DateTime timestamp,
  }) {
    return FactRecord(
      id: 'agent.deleted/$agentId/${timestamp.microsecondsSinceEpoch}',
      workspaceId: workspaceId,
      type: AgentLifecycleFactType.agentDeleted,
      entityId: agentId,
      content: {
        'agentId': agentId,
        'timestamp': timestamp.toIso8601String(),
      },
      period: AbsolutePeriod(start: timestamp, end: timestamp),
      createdAt: timestamp,
    );
  }
}
