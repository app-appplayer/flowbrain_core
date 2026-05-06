/// FlowBrain Core — MOD-CORE-003 KnowledgeConfig (flowbrain wrapper).
///
/// Wraps `mcp_knowledge`'s `KnowledgeConfig` and adds the Agent Subsystem
/// sub-config (`AgentConfig`). See:
///
///   - `os/core/flowbrain/docs/03_DDD/03-knowledge-config.md`
///   - FR-FBCORE-CFG-001..011
library;

import 'package:mcp_knowledge/mcp_knowledge.dart' as mcp;

import '../agent/agent_config.dart';

// Re-export sub-config types so hosts can import everything via
// `package:flowbrain_core/flowbrain_core.dart`.
export 'package:mcp_knowledge/mcp_knowledge.dart'
    show
        FactGraphConfig,
        SkillConfig,
        ProfileConfig,
        PipelineConfig,
        SchedulerConfig,
        EventConfig,
        LoggingConfig,
        FeatureFlags,
        PhilosophyConfig,
        ExecutionBudgetConfig,
        LogLevel;

export '../agent/agent_config.dart';

/// FlowBrain `KnowledgeConfig` — `mcp_knowledge.KnowledgeConfig` wrapper +
/// `AgentConfig` sub-config.
class KnowledgeConfig {
  KnowledgeConfig({
    mcp.KnowledgeConfig? knowledgeConfig,
    AgentConfig? agent,
    String? workspaceId,
  })  : _config = workspaceId != null
            ? (knowledgeConfig ?? mcp.KnowledgeConfig.defaults)
                .copyWith(workspaceId: workspaceId)
            : (knowledgeConfig ?? mcp.KnowledgeConfig.defaults),
        agent = agent ?? AgentConfig.defaults;

  final mcp.KnowledgeConfig _config;
  final AgentConfig agent;

  /// Underlying mcp_knowledge config — used by the `KnowledgeSystem`
  /// wrapper to forward to the wrapped `mcp.KnowledgeSystem`.
  mcp.KnowledgeConfig get internal => _config;

  String get workspaceId => _config.workspaceId;
  mcp.FactGraphConfig get factGraph => _config.factGraph;
  mcp.SkillConfig get skill => _config.skill;
  mcp.ProfileConfig get profile => _config.profile;
  mcp.PipelineConfig get pipeline => _config.pipeline;
  mcp.SchedulerConfig get scheduler => _config.scheduler;
  mcp.EventConfig get events => _config.events;
  mcp.LoggingConfig get logging => _config.logging;
  mcp.FeatureFlags get features => _config.features;
  mcp.PhilosophyConfig get philosophy => _config.philosophy;

  /// Default preset.
  static KnowledgeConfig get defaults => KnowledgeConfig();

  /// Development preset — debug logs, growth tracking, shorter conversation
  /// TTL.
  static KnowledgeConfig get development => KnowledgeConfig(
        knowledgeConfig: mcp.KnowledgeConfig.development,
        agent: AgentConfig.development,
      );

  /// Production preset.
  static KnowledgeConfig get production => KnowledgeConfig(
        knowledgeConfig: mcp.KnowledgeConfig.production,
        agent: AgentConfig.production,
      );

  KnowledgeConfig copyWith({
    String? workspaceId,
    AgentConfig? agent,
    mcp.KnowledgeConfig? knowledgeConfig,
  }) =>
      KnowledgeConfig(
        knowledgeConfig: knowledgeConfig ?? _config,
        agent: agent ?? this.agent,
        workspaceId: workspaceId,
      );
}
