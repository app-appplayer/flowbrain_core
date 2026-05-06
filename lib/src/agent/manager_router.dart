/// FlowBrain Core — Manager Router.
///
/// Builds the routing prompt and parses the manager LLM response into a
/// `RoutingDecision`. See:
///
///   - `os/core/flowbrain/docs/03_DDD/16-agent-role-and-routing.md`
///   - FR-FBCORE-AGT-024, AGT-065
library;

import 'agent_models.dart';

class ManagerRouter {
  const ManagerRouter();

  /// Build the routing prompt. Includes the manager's system prompt (if
  /// any), the candidate agent summary, and the user request.
  String buildPrompt({
    required Agent manager,
    required String request,
    required List<Agent> candidates,
  }) {
    final candidateBlock = candidates
        .map((a) =>
            '- ${a.id}: ${a.displayName} (role=${a.role.name}, model=${a.model.provider}/${a.model.model})')
        .join('\n');

    final systemPrompt = manager.systemPrompt ?? '';
    return '''
$systemPrompt

You are a routing manager. Analyze the user request and select the most
suitable agent from the candidates.

# Candidates
$candidateBlock

# User Request
$request

# Output Format (strict JSON)
{"targetAgentId": "<id>", "confidence": 0.0-1.0, "reason": "..."}
''';
  }

  /// Delegate to `RoutingDecision.tryParse` — kept here so that callers can
  /// substitute alternative parsers via subclassing in tests.
  RoutingDecision parseDecision(String llmContent) =>
      RoutingDecision.tryParse(llmContent);
}
