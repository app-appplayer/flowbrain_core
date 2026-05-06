/// FlowBrain — canonical example.
///
/// Spins up a `KnowledgeSystem` with the Agent Subsystem activated using
/// the built-in stub LLM, creates one worker agent, asks a question,
/// reads the conversation back, and tears the system down cleanly.
///
/// No external services required — `StubLlmPort()` is wired by
/// `KnowledgeSystem.withAgents()` when no `llm` / `llmProviders` are
/// supplied. Replace it with `AnthropicLlmPort` / `OpenAiLlmPort` /
/// custom implementation to use a real model.
///
/// Run:
///
///   dart run example/flowbrain_example.dart
library;

import 'package:flowbrain_core/flowbrain_core.dart';

Future<void> main() async {
  // 1. Boot — Agent Subsystem activated, stub LLM auto-wired.
  final system = KnowledgeSystem.withAgents();

  // 2. Create a worker agent. `id` is your stable handle.
  final sara = await system.agents.createAgent(
    id: 'sara',
    displayName: 'Sara',
    role: AgentRole.worker,
    model: ModelSpec.stub(),
    workspaceId: 'demo',
    systemPrompt: 'You are a friendly assistant.',
  );
  print('created agent: ${sara.id} · role=${sara.role.name}');

  // 3. Ask a question. Returns an `AgentReply` with content + metadata.
  final reply = await system.agents.ask(sara.id, 'Hello, what can you do?');
  print('reply: ${reply.content}');
  print('  model=${reply.model}  finishReason=${reply.finishReason ?? "—"}');

  // 4. Inspect the conversation history.
  final history = await system.agents.getHistory(sara.id);
  print('history: ${history.length} turn(s)');

  // 5. Always shut down — cancels event subscriptions, disposes the
  //    wrapped Knowledge runtimes.
  await system.shutdown();
}
