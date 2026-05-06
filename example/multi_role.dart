/// FlowBrain — manager / worker / reviewer triad.
///
/// Demonstrates the three [AgentRole] values cooperating: a **manager**
/// routes a request to one of several **worker** candidates, the worker
/// answers via `ask`, and a **reviewer** evaluates the worker's reply.
///
/// All three agents share the same workspace and the same stub LLM —
/// in production the manager / reviewer typically run on stronger
/// models than the worker.
///
/// Run:
///
///   dart run example/multi_role.dart
library;

import 'package:flowbrain_core/flowbrain_core.dart';

Future<void> main() async {
  final system = KnowledgeSystem.withAgents();

  // Two specialist workers.
  await system.agents.createAgent(
    id: 'worker-research',
    displayName: 'Research Worker',
    role: AgentRole.worker,
    model: ModelSpec.stub(),
    workspaceId: 'triad-demo',
    tags: const {'specialty': 'research'},
  );
  await system.agents.createAgent(
    id: 'worker-coding',
    displayName: 'Coding Worker',
    role: AgentRole.worker,
    model: ModelSpec.stub(),
    workspaceId: 'triad-demo',
    tags: const {'specialty': 'coding'},
  );

  // One manager and one reviewer.
  final manager = await system.agents.createAgent(
    id: 'manager-1',
    displayName: 'Manager',
    role: AgentRole.manager,
    model: ModelSpec.stub(),
    workspaceId: 'triad-demo',
  );
  final reviewer = await system.agents.createAgent(
    id: 'reviewer-1',
    displayName: 'Reviewer',
    role: AgentRole.reviewer,
    model: ModelSpec.stub(),
    workspaceId: 'triad-demo',
  );

  // 1. Manager picks a candidate worker for the incoming request.
  //
  // `agents.route` parses the manager LLM's output as JSON to extract a
  // [RoutingDecision]. The bundled `StubLlmPort` returns plain text, so
  // the parse will land on [RoutingDecision.parseError] — in production
  // an Anthropic / OpenAI / etc. provider with a system prompt that
  // instructs JSON output produces a real decision. We fall back to the
  // first candidate when parsing fails so the example continues end-to-end.
  const request = 'Summarise the architecture of the new payment service.';
  const candidates = ['worker-research', 'worker-coding'];
  final decision = await system.agents.route(
    manager.id,
    request,
    candidateAgentIds: candidates,
  );
  final picked = decision.targetAgentId.isNotEmpty
      ? decision.targetAgentId
      : candidates.first;
  print('manager decision: target="${decision.targetAgentId}"'
      '  ·  confidence=${decision.confidence.toStringAsFixed(2)}'
      '${decision.reason != null ? "  ·  ${decision.reason}" : ""}');
  print('  → falling back to ${picked == decision.targetAgentId ? "manager pick" : "candidates.first ($picked)"}');

  // 2. The chosen worker answers.
  final reply = await system.agents.ask(picked, request);
  print('worker reply: ${reply.content}');

  // 3. Reviewer evaluates that reply.
  final review = await system.agents.review(reviewer.id, reply);
  print('reviewer verdict: ${review.verdict.name}'
      '${review.comments != null ? "  ·  ${review.comments}" : ""}');

  await system.shutdown();
}
