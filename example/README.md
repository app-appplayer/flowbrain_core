# FlowBrain Examples

Three runnable samples that exercise the package's public surface end-to-end against the built-in stub LLM — no external service or API key required.

| File | Demonstrates |
|------|--------------|
| `flowbrain_example.dart` | Canonical hello — boot → create one worker agent → `ask` → read history → shutdown |
| `multi_role.dart` | The three [`AgentRole`][role] cooperating: `manager` routes a request to one of two `worker` candidates, then a `reviewer` evaluates the worker's reply |
| `lifecycle_events.dart` | Subscribing to `system.eventBus.stream` and observing the events emitted by create / ask / delete |

[role]: https://pub.dev/documentation/flowbrain/latest/flowbrain/AgentRole.html

## Running

From the `dart/` package root:

```bash
dart run example/flowbrain_example.dart
dart run example/multi_role.dart
dart run example/lifecycle_events.dart
```

## Swapping in a real LLM

The examples use `ModelSpec.stub()`, which routes through `StubLlmPort()` — deterministic short replies, no network. To wire a real provider, supply `llm:` (or `llmProviders:` for multi-provider routing) when constructing the system:

```dart
final system = KnowledgeSystem.withAgents(
  llm: AnthropicLlmPort(apiKey: '...'),
);
final sara = await system.agents.createAgent(
  id: 'sara',
  displayName: 'Sara',
  role: AgentRole.worker,
  model: ModelSpec(provider: 'anthropic', model: 'claude-sonnet-4-6'),
  workspaceId: 'demo',
);
```

`AnthropicLlmPort` / `OpenAiLlmPort` / `GeminiLlmPort` etc. are provided by `mcp_llm`; any class implementing `LlmPort` works.
