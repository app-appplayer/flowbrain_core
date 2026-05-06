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
