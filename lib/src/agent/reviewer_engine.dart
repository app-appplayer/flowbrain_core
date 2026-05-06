/// FlowBrain Core — Reviewer Engine.
///
/// Builds the review prompt and parses the reviewer LLM response into a
/// `ReviewResult`. See:
///
///   - `os/core/flowbrain/docs/03_DDD/16-agent-role-and-routing.md`
///   - FR-FBCORE-AGT-025, AGT-066
library;

import 'agent_models.dart';

class ReviewerEngine {
  const ReviewerEngine();

  /// Build the review prompt. The reviewer's owned philosophy / profile
  /// should already have been folded into the conversation context — this
  /// prompt focuses on the target reply.
  String buildPrompt({
    required Agent reviewer,
    required AgentReply targetReply,
  }) {
    final systemPrompt = reviewer.systemPrompt ?? '';
    return '''
$systemPrompt

You are a quality reviewer. Evaluate the following reply.

# Reply Under Review
agent: ${targetReply.agentId}
model: ${targetReply.model}
content:
${targetReply.content}

# Output Format (strict JSON)
{"verdict": "pass" | "fail" | "revise", "severity": "low" | "medium" | "high" | null, "comments": "..."}
''';
  }

  ReviewResult parseResult(String llmContent) =>
      ReviewResult.tryParse(llmContent);
}
