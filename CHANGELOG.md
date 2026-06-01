## 0.1.3

### Added
- `AgentFacade.ask` / `AgentRuntime.ask` gain an optional `resetContext` flag (default `false`). When `true`, the agent's conversation history is cleared before the prompt is composed — for manager agents whose every turn should be treated fresh (bounds context growth, avoids stale prior-turn pollution that weakens the current directive). The post-ask turn is still appended; the reset is one-shot.

### Changed (dependency floor)
- `mcp_knowledge` `^0.2.3` → `^0.2.4` — raises the floor so the re-exported `OpsFacade` is guaranteed to carry the behavior-execution methods (`runBehavior` / `resumeBehavior` / `listBehaviors`, added in mcp_knowledge 0.2.4). flowbrain_core's own code is otherwise unchanged; this guarantees the capability for consumers (e.g. brain_kernel) that reach behavior through `system.ops`. Consumers should bump to `^0.1.3`.

## 0.1.2

### Changed (cascade)
- `mcp_bundle` caret bumped from `^0.3.2` to `^0.4.0` (mcp_bundle 0.4.0 `UiSection.pages` spec realignment).
- `mcp_knowledge` caret bumped from `^0.2.2` to `^0.2.3` (sibling cascade).

flowbrain_core does not touch `UiSection.pages` directly — caret-only cascade. Consumers should bump to `^0.1.2`.

## 0.1.1

### Dependencies
- `mcp_bundle: ^0.3.1` → `^0.3.2` — cascade alignment to pick up `McpBundle.factGraphSection` wire (additive — fact instance round-trip slot alongside the existing `factGraphSchema` type catalogue).
- `mcp_knowledge: ^0.2.1` → `^0.2.2` — same cascade.

No code changes in `flowbrain_core` itself.

---

## 0.1.0

Initial release.

* **Knowledge Subsystem** — five facades (`facts`, `skill`, `profile`, `philosophy`, `ops`) wrapped from `mcp_knowledge` 0.2.x. Four-layer knowledge structure (L0 FactGraph → L1 Skill → L2 Profile → L3 Philosophy) plus Ops, with default L0 auto-wiring and `InfraPorts.inMemory()` smoke infrastructure.
* **Agent Subsystem** — flowbrain-native, fully on-package:
    * Self-contained agents — own LLM context, own model (`ModelSpec`), own forked 4-axis instances.
    * Three roles via `AgentRole` — `worker` / `manager` / `reviewer`.
    * 4-axis fork assignment from workspace pool or from another already-evolved agent (`PoolForkSource` / `AgentForkSource`) across `skill` · `profile` · `philosophy` · `facts`.
    * `agents.ask` / `agents.stream` for conversation, `agents.route` for manager dispatch, `agents.review` for reviewer evaluation.
    * Growth Tracker records evolution kinds (variation / adjustment / revision / accretion) per agent.
    * Conversation Store with `getHistory(limit)`.
* **Event bus** — `system.eventBus.stream` (broadcast `Stream<KnowledgeEvent>`); domain-typed agent events (`AgentCreatedEvent`, `AgentDeletedEvent`, …).
* **Stub LLM** — `StubLlmPort` auto-wired by `KnowledgeSystem.withAgents()` when no provider is supplied; deterministic short replies for tests / smoke runs.
* **Public surface** — single barrel import `package:flowbrain_core/flowbrain_core.dart` exposes:
    * `KnowledgeSystem` (defaults / stub / withAgents factories)
    * `KnowledgeConfig` + 9 sub-configs
    * `InfraPorts` + standard infrastructure port interfaces
    * `AgentFacade` + `Agent` / `AgentReply` / `AgentRole` / `AgentAxis` / `ModelSpec` / `RoutingDecision` / `ReviewResult` / `ReviewVerdict` / `GrowthKind` / `ConversationTurn`
    * Philosophy domain helper exceptions and result types
* **Examples** — `example/flowbrain_example.dart`, `example/multi_role.dart`, `example/lifecycle_events.dart`. All run end-to-end against the stub LLM with no external services.
