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
    List<({String id, String text})> values = const [],
  }) {
    final systemPrompt = reviewer.systemPrompt ?? '';
    final valueBlock = values.isEmpty
        ? ''
        : '''

# Values the work answers to
${values.map((v) => '- ${v.id}: ${v.text}').join('\n')}
When a verdict turns on one of these, name it in "valuePriorityId" and say in "valueEffect" whether the work fell short of it ("violated") or following it cost too much ("overapplied").
''';
    return '''
$systemPrompt

You are a quality reviewer. Evaluate the following reply.

# Reply Under Review
agent: ${targetReply.agentId}
model: ${targetReply.model}
content:
${targetReply.content}
$valueBlock
# Output Format (strict JSON)
{"verdict": "pass" | "fail" | "revise", "severity": "low" | "medium" | "high" | null, "comments": "..."${values.isEmpty ? '' : ', "valuePriorityId": "<id from the list above or null>", "valueEffect": "violated" | "overapplied" | null'}}
''';
  }

  ReviewResult parseResult(String llmContent) =>
      ReviewResult.tryParse(llmContent);
}
