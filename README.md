# FlowBrain

**Judgment- and knowledge-domain core for the MakeMind ecosystem.** A single Dart package exposing two cooperating subsystems:

- **Knowledge Subsystem** — four-layer knowledge structure (L0 FactGraph → L1 Skill → L2 Profile → L3 Philosophy) plus Ops, surfaced through five facades (`facts`, `skill`, `profile`, `philosophy`, `ops`).
- **Agent Subsystem** — flowbrain-native self-contained agents with their own LLM context, model, forked 4-axis instances (skill / profile / philosophy / facts), and three roles (`worker` / `manager` / `reviewer`).

Hosts (Ops apps, MCP servers, derivative OS cores) import only `package:flowbrain_core/flowbrain_core.dart`. The underlying `mcp_knowledge` family and the five domain packages stay as the internal technical stack.

## Install

```bash
dart pub add flowbrain
```

## Hello

```dart
import 'package:flowbrain_core/flowbrain_core.dart';

Future<void> main() async {
  final system = KnowledgeSystem.withAgents();
  await system.agents.createAgent(
    id: 'sara',
    displayName: 'Sara',
    role: AgentRole.worker,
    model: ModelSpec.stub(),       // swap for a real provider in production
    workspaceId: 'demo',
  );
  final reply = await system.agents.ask('sara', 'hello');
  print(reply.content);
  await system.shutdown();
}
```

`KnowledgeSystem.withAgents()` activates the Agent Subsystem with an in-memory infrastructure and a stub LLM, so the snippet above runs end-to-end without any external service.

## Three roles

```dart
final manager = await system.agents.createAgent(role: AgentRole.manager,  ...);
final worker  = await system.agents.createAgent(role: AgentRole.worker,   ...);
final review  = await system.agents.createAgent(role: AgentRole.reviewer, ...);

// Manager picks a worker, worker answers, reviewer evaluates.
final picked = await system.agents.route(manager.id, 'task X', candidateAgentIds: [worker.id]);
final reply  = await system.agents.ask(picked.targetAgentId, 'task X');
final review = await system.agents.review(reviewer.id, reply);
```

## 4-axis fork

Each agent carries forked instances along four axes — skill, profile, philosophy, facts — assignable from a workspace pool or transferred from another already-evolved agent.

```dart
await system.agents.assignSkillFromPool('sara', 'skill.research');
await system.agents.assignProfileFromPool('sara', 'profile.friendly');
await system.agents.assignPhilosophyFromPool('sara', 'ethos.helpful');
await system.agents.assignFacts('sara', FactQuery(workspaceId: 'demo'));
```

The four axes evolve per-agent — `growthTracker` records variations, adjustments, revisions, and accretions — and one agent's matured fork can be transferred to another with `AgentForkSource(...)`.

## Knowledge facades

The five facades are `system.facts`, `system.skill`, `system.profile`, `system.philosophy`, and `system.ops`. They wrap `mcp_knowledge`'s runtimes; check that package's documentation for the full surface. For a high-level event view, subscribe to `system.eventBus.stream`.

```dart
final sub = system.eventBus.stream.listen((event) {
  print('event ${event.type} at ${event.timestamp}');
});
// ... use the system ...
await sub.cancel();
```

## Supplying real LLMs

`KnowledgeSystem.withAgents()` accepts `llm:` (single provider) or `llmProviders:` (multi-provider routed by `ModelSpec.provider`):

```dart
final system = KnowledgeSystem.withAgents(
  llmProviders: {
    'anthropic': AnthropicLlmPort(apiKey: '...'),
    'openai':    OpenAiLlmPort(apiKey: '...'),
  },
);
final sara = await system.agents.createAgent(
  id: 'sara',
  displayName: 'Sara',
  role: AgentRole.worker,
  model: ModelSpec(provider: 'anthropic', model: 'claude-sonnet-4-6'),
  workspaceId: 'demo',
);
```

`LlmPort` implementations live in `mcp_llm`; anything implementing the interface plugs in.

## Examples

See [`example/`](example/) for runnable samples:

- `flowbrain_example.dart` — canonical hello
- `multi_role.dart` — manager / worker / reviewer triad
- `lifecycle_events.dart` — observe `eventBus.stream`

## Where things live

```
package:flowbrain_core/flowbrain_core.dart      ← single import for hosts

  KnowledgeSystem                     ← entry point (defaults / stub / withAgents)
    .facts                            ← L0 FactGraph facade
    .skill                            ← L1 Skill facade
    .profile                          ← L2 Profile facade
    .philosophy                       ← L3 Philosophy facade
    .ops                              ← Ops facade
    .agents                           ← Agent Subsystem facade
    .eventBus                         ← KnowledgeEventBus (broadcast)
```

Configuration (`KnowledgeConfig`, sub-configs for each layer) and infrastructure ports (`InfraPorts`, `LlmPort`, storage / search / embedding / etc.) are also surfaced from the same import. See the API docs for the full list.

## Compatibility

- Dart SDK `^3.0.0`
- Pure Dart — no Flutter dependency
- Ports for storage / search / embedding / LLM are pluggable; `InfraPorts.inMemory()` provides smoke defaults

## License

MIT — see [LICENSE](LICENSE).
