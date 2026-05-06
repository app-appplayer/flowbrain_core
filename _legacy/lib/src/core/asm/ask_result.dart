/// AskResult — result of a FlowBrain.ask() call.
library;

import 'package:mcp_bundle/mcp_bundle.dart' show SkillResult;

/// Result returned by [FlowBrain.ask].
///
/// Contains the response text, the agent that handled the request,
/// the trace identifier for correlation, and an optional [SkillResult]
/// if a skill was executed as part of answering.
class AskResult {
  /// The response text.
  final String response;

  /// Agent that handled the request.
  final String agentId;

  /// Trace identifier for correlation and observability.
  final String traceId;

  /// Skill execution result, if a skill was invoked.
  final SkillResult? skillResult;

  const AskResult({
    required this.response,
    required this.agentId,
    required this.traceId,
    this.skillResult,
  });

  @override
  String toString() =>
      'AskResult(agentId: $agentId, traceId: $traceId, '
      'response: ${response.length > 80 ? '${response.substring(0, 80)}...' : response})';
}
