/// FlowBrain Core — Agent Subsystem configuration.
///
/// Sub-config of `KnowledgeConfig` (composed in `KnowledgeConfig` wrapper at
/// Phase 3). Defined separately so the Agent Subsystem can compile
/// independently of the `KnowledgeConfig` wrapper. See:
///
///   - `os/core/flowbrain/docs/03_DDD/14-agent-conversation-store.md`
///   - FR-FBCORE-CFG-010, FR-FBCORE-CFG-011, FR-FBCORE-AGT-046
library;

import 'agent_models.dart';

/// Agent Subsystem configuration. Field defaults match SRS §3-2 CFG-010.
class AgentConfig {
  const AgentConfig({
    this.defaultModel,
    this.conversationTtl = const Duration(days: 30),
    this.maxConversationTurns = 100,
    this.forkPolicy = ForkPolicy.eagerFull,
    this.maxAgentsPerWorkspace,
    this.enableGrowthTracking = true,
    this.enableManagerRouting = true,
    this.enableReviewer = true,
    this.recordLifecycleAsFacts = true,
  });

  /// Default model used when an Agent has no explicit `model` (rare — most
  /// callers supply a `ModelSpec` at `createAgent` time).
  final ModelSpec? defaultModel;

  /// Time since `lastAt` after which a conversation is GC-eligible.
  /// `Duration.zero` disables the TTL sweeper entirely.
  final Duration conversationTtl;

  /// Maximum number of turns retained verbatim per agent. Older turns are
  /// compressed by core-internal policy (FR-FBCORE-AGT-033).
  final int maxConversationTurns;

  /// Determines whether deep copy happens at assignment (`eagerFull`) or at
  /// first mutation (`copyOnWrite`).
  final ForkPolicy forkPolicy;

  /// Per-workspace agent cap. `null` = unlimited.
  final int? maxAgentsPerWorkspace;

  /// When false, `recordEvolution` no longer emits `AgentForkEvolvedEvent`
  /// (counters are still updated for stable storage layout).
  final bool enableGrowthTracking;

  /// When false, `route()` throws `StateError` regardless of role.
  final bool enableManagerRouting;

  /// When false, `review()` throws `StateError` regardless of role.
  final bool enableReviewer;

  /// When true (default), every agent lifecycle event — fork assignment,
  /// fork evolution, agent invocation, agent deletion — is automatically
  /// written to the workspace FactGraph as a `FactRecord` with type
  /// `agent.fork.assigned` / `agent.fork.evolved` / `agent.invoked` /
  /// `agent.deleted`. Hosts get a uniform timeline ("who used what, from
  /// when, until when") for free, with no per-host wiring. Set to `false`
  /// when the host wants to handle bookkeeping itself.
  final bool recordLifecycleAsFacts;

  AgentConfig copyWith({
    ModelSpec? defaultModel,
    Duration? conversationTtl,
    int? maxConversationTurns,
    ForkPolicy? forkPolicy,
    int? maxAgentsPerWorkspace,
    bool? enableGrowthTracking,
    bool? enableManagerRouting,
    bool? enableReviewer,
    bool? recordLifecycleAsFacts,
  }) =>
      AgentConfig(
        defaultModel: defaultModel ?? this.defaultModel,
        conversationTtl: conversationTtl ?? this.conversationTtl,
        maxConversationTurns:
            maxConversationTurns ?? this.maxConversationTurns,
        forkPolicy: forkPolicy ?? this.forkPolicy,
        maxAgentsPerWorkspace:
            maxAgentsPerWorkspace ?? this.maxAgentsPerWorkspace,
        enableGrowthTracking:
            enableGrowthTracking ?? this.enableGrowthTracking,
        enableManagerRouting:
            enableManagerRouting ?? this.enableManagerRouting,
        enableReviewer: enableReviewer ?? this.enableReviewer,
        recordLifecycleAsFacts:
            recordLifecycleAsFacts ?? this.recordLifecycleAsFacts,
      );

  /// Default preset.
  static const AgentConfig defaults = AgentConfig();

  /// Development preset — shorter TTL, aggressive growth tracking.
  static const AgentConfig development = AgentConfig(
    conversationTtl: Duration(days: 7),
    enableGrowthTracking: true,
  );

  /// Production preset — defaults are already production-friendly.
  static const AgentConfig production = AgentConfig();
}
