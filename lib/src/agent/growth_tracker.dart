/// FlowBrain Core — Growth Tracker.
///
/// Detects mutations in agent-owned 4-axis instances and forwards them to
/// `AgentRegistry.recordEvolution` (which increments counters and emits
/// `AgentForkEvolvedEvent`). The current implementation is a hook surface —
/// host integrations or future auto-detection logic call into the public
/// methods. See:
///
///   - `os/core/flowbrain/docs/03_DDD/12-agent-registry.md` §4-3
///   - FR-FBCORE-AGT-014, AGT-064
library;

import 'agent_config.dart';
import 'agent_models.dart';
import 'agent_registry.dart';

class GrowthTracker {
  GrowthTracker({
    required AgentRegistry registry,
    required AgentConfig config,
  })  : _registry = registry,
        // ignore: unused_field
        _config = config;

  final AgentRegistry _registry;
  // Held for future heuristics (e.g. variance thresholds before recording).
  // ignore: unused_field
  final AgentConfig _config;

  /// Record a skill variation observed during agent invocation.
  Future<void> trackVariation({
    required String agentId,
    required String forkedRef,
  }) =>
      _registry.recordEvolution(
        agentId: agentId,
        axis: AgentAxis.skill,
        forkedRef: forkedRef,
        kind: GrowthKind.variation,
      );

  /// Record a profile adjustment (persona fine-tuning).
  Future<void> trackAdjustment({
    required String agentId,
    required String forkedRef,
  }) =>
      _registry.recordEvolution(
        agentId: agentId,
        axis: AgentAxis.profile,
        forkedRef: forkedRef,
        kind: GrowthKind.adjustment,
      );

  /// Record a philosophy revision.
  Future<void> trackRevision({
    required String agentId,
    required String forkedRef,
  }) =>
      _registry.recordEvolution(
        agentId: agentId,
        axis: AgentAxis.philosophy,
        forkedRef: forkedRef,
        kind: GrowthKind.revision,
      );

  /// Record an accumulation in the agent's facts snapshot.
  Future<void> trackFactsAccumulation({
    required String agentId,
    required String forkedRef,
  }) =>
      _registry.recordEvolution(
        agentId: agentId,
        axis: AgentAxis.facts,
        forkedRef: forkedRef,
        kind: GrowthKind.revision, // ignored for facts axis (see DDD-12 §4-3)
      );
}
