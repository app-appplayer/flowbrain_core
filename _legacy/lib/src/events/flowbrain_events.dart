/// FlowBrain-specific events per SDD §5.4.
///
/// These 7 event types are published to `KnowledgeEventBus` by FlowBrain
/// modules. They supplement the 13 built-in events from mcp_knowledge.
library;

import 'package:mcp_knowledge/mcp_knowledge.dart' show KnowledgeEvent;

/// Emitted after AgentRouter resolves which agent handles a request.
class AgentResolvedEvent implements KnowledgeEvent {
  @override
  final DateTime timestamp;

  @override
  String get type => 'agent_resolved';

  /// Resolved agent identifier.
  final String agentId;

  /// Original request text.
  final String request;

  const AgentResolvedEvent({
    required this.agentId,
    required this.request,
    required this.timestamp,
  });
}

/// Emitted when FlowBrain.ask() is entered.
///
/// At "started" time, the agent may not yet be resolved, so [agentId]
/// is optional (null until routing completes).
class AgentAskStartedEvent implements KnowledgeEvent {
  @override
  final DateTime timestamp;

  @override
  String get type => 'agent_ask_started';

  /// Agent handling the request (null if not yet resolved).
  final String? agentId;

  /// Original request text.
  final String request;

  /// Trace identifier for correlation.
  final String traceId;

  const AgentAskStartedEvent({
    this.agentId,
    required this.request,
    required this.traceId,
    required this.timestamp,
  });
}

/// Emitted when FlowBrain.ask() completes.
class AgentAskCompletedEvent implements KnowledgeEvent {
  @override
  final DateTime timestamp;

  @override
  String get type => 'agent_ask_completed';

  /// Agent that handled the request.
  final String agentId;

  /// Trace identifier for correlation.
  final String traceId;

  /// Total ask duration.
  final Duration duration;

  /// Whether the ask succeeded.
  final bool success;

  /// Error message if [success] is false.
  final String? error;

  const AgentAskCompletedEvent({
    required this.agentId,
    required this.traceId,
    required this.duration,
    required this.success,
    this.error,
    required this.timestamp,
  });
}

/// Emitted when KFL (Knowledge-First LLM) classifies and dispatches a request.
class KflEscalationEvent implements KnowledgeEvent {
  @override
  final DateTime timestamp;

  @override
  String get type => 'kfl_escalation';

  /// Escalation tier that was selected (hit / partial / miss).
  final String tier;

  /// Aggregated knowledge confidence that drove the decision.
  final double confidence;

  /// Whether the escalation resulted in failure.
  final bool failed;

  const KflEscalationEvent({
    required this.tier,
    required this.confidence,
    this.failed = false,
    required this.timestamp,
  });
}

/// Emitted after a successful hot-reload of configuration.
class ConfigReloadedEvent implements KnowledgeEvent {
  @override
  final DateTime timestamp;

  @override
  String get type => 'config_reloaded';

  /// Config sections that were reloaded.
  final List<String> sections;

  const ConfigReloadedEvent({
    required this.sections,
    required this.timestamp,
  });
}

/// Emitted when a hot-reload of configuration fails.
class ConfigReloadFailedEvent implements KnowledgeEvent {
  @override
  final DateTime timestamp;

  @override
  String get type => 'config_reload_failed';

  /// Error message describing why the reload failed.
  final String error;

  /// Config sections that were being reloaded, if known.
  final List<String> sections;

  const ConfigReloadFailedEvent({
    required this.error,
    this.sections = const [],
    required this.timestamp,
  });
}

/// Emitted when a bundle is rolled back.
class BundleRolledBackEvent implements KnowledgeEvent {
  @override
  final DateTime timestamp;

  @override
  String get type => 'bundle_rolled_back';

  /// Bundle identifier.
  final String bundleId;

  /// Reason for rollback.
  final String reason;

  const BundleRolledBackEvent({
    required this.bundleId,
    required this.reason,
    required this.timestamp,
  });
}

/// Emitted when daily cost exceeds configured threshold.
class CostThresholdExceededEvent implements KnowledgeEvent {
  @override
  final DateTime timestamp;

  @override
  String get type => 'cost_threshold_exceeded';

  /// Accumulated cost for the current day (USD).
  final double todayUsd;

  /// Configured threshold (USD).
  final double threshold;

  const CostThresholdExceededEvent({
    required this.todayUsd,
    required this.threshold,
    required this.timestamp,
  });
}
