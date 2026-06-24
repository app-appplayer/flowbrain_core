## 0.1.6 - 2026-06-24 - ConversationStore per-agent append atomicity (additive)

### Fixed
- **`ConversationStore.append` is now atomic per agentId.** `append` was a non-atomic read-modify-write (`load` → `[...existing, turn]` → `_kv.set`); two concurrent `agents.ask` calls for the *same* agent could read the same history, each append its own turn, and the last `set` win — silently dropping a turn (the agent then "forgets" the lost request). A per-agentId serialization tail now chains mutating ops (`append`, and `clear` so append↔clear/TTL-sweep can't interleave either) so same-agent calls run strictly in order; different agentIds stay parallel. The tail always completes successfully (a failed op surfaces to its caller but never blocks the next) and its map entry is dropped when nothing is chained behind it (bounded growth). Regression: `test/agent/14_conversation_store_test.dart` (25 concurrent same-agent appends preserve all 25 · two agents stay isolated) — both fail without the serialization.

### Backward compatibility
- Fully additive. No API or signature change — `append` / `clear` / `remove` keep their shapes; only concurrent-call ordering is now guaranteed.

## 0.1.5 - 2026-06-23 - FlowBrain runtime wiring (spec 12 §2·§3·§3b·§4·§4b)

### Changed (behavior — additive, no API change)
- **§2 — 4-axis ask composition**: `AgentRuntime.ask` now composes **all 4 assigned axes** (profile · philosophy · skill · facts), not facts alone (spec `platform/12-flowbrain-runtime.md` §2). Order: profile (persona) → philosophy (values/prohibitions) → skill → facts. Facts keep rich `_factLine`; non-facts axes render defensively from their owned-fork payload (live object via `toJson`, or JSON `Map`) so no hidden Knowledge-Subsystem type is imported — 20 items/axis cap. None assigned → prompt identical (regression-safe).
- **§3 enforcement proven end-to-end (real engine, not stub)**: `test/agent/25_philosophy_prohibition_enforcement_test.dart` wires a real `PhilosophyEngine` over a seeded ethos store and proves `ask` actually **blocks** an output hitting a hard prohibition and **delivers** a clean one — via `Prohibition.forbiddenPatterns` (mcp_bundle 0.4.4 + mcp_philosophy 0.1.2's deterministic `_detectViolation`). This closes the gap that TEST-24's always-block stub masked: the structural evaluator previously caught only two hardcoded NL shapes and silently fell open for every other prohibition. **Runtime requirement: mcp_philosophy ≥ 0.1.2 for the deterministic path to actually block** (resolved transitively via `mcp_knowledge` caret; semantic NL judgment remains an LLM seam — spec §3.1).
- **§3 — Philosophy work-time intervention**: `AgentRuntime.ask` now runs the assigned Philosophy's post-generation gate over the LLM output before delivery — a hard prohibition throws `AgentPhilosophyBlockedException` (turn not appended/delivered), soft modifications adjust the text. Opt-in: no assigned philosophy or no engine → skipped (the existing-suite agents are unaffected). Fails open on engine error. (`InterventionPoint`/`PipelineContext`/`InterventionResult` come from `mcp_bundle` — flowbrain's own direct dep; no new dependency.) `detectTensions` at the fork-evolution boundary is a separate follow-up.
- **§4 — outcome→knowledge loop (philosophy)**: `AgentRuntime.review` now feeds the reviewer verdict back as a Philosophy `FeedbackEvent` → `proposeFeedback` (pass→positive · fail→negative · revise→mixed). The proposal is **human-gated and never auto-applied** (facade only emits `EvolutionProposedEvent`; gated by `enableEvolution`). Opt-in (target has assigned philosophy + engine available); fails open. `AgentPhilosophyBlockedException` added (`agent_exception.dart`). (Other axes already accumulate: facts write + profile growth counters; the `FeedbackEvent` wire was the missing outcome→proposal call-site. `detectTensions` at fork-evolution = follow-up.)
- **§4b — skill refinement path**: `AgentRuntime.review` now, on a deficient verdict (`fail` / `revise`), records a skill *variation candidate* per assigned skill fork via `GrowthTracker.trackVariation` (`GrowthKind.variation` → `skillCandidateCount` accumulator + `AgentForkEvolvedEvent` + FactGraph timeline). A `pass` verdict means the skill worked as-is → no candidate. This completes the §4 four-axis loop (philosophy reinforcement + skill refinement + facts/profile already accumulating). Reuses the existing growth mechanism — no new model. Opt-in (target has an assigned skill); fails open.
- **§3b — Philosophy fork-evolution drift anchor**: `AgentRuntime.review` now, at the fork-evolution boundary (a review verdict is the outcome that evolves the target's non-philosophy axes), calls the assigned Philosophy's `detectTensions(MultiLayerContext)` over the agent's evolving profile + facts-provenance, emitting `AgentForkTensionDetectedEvent` (count + max severity + descriptions) when tensions are found. Philosophy is the only axis that *governs* the other three — this surfaces drift so a host can flag/hold an evolution that would leave the constitution. Opt-in (target has assigned philosophy); advisory (emit, no auto-revert); no-op when the adapter doesn't implement `detectTensions` (`UnsupportedError` caught); fails open. (`MultiLayerContext`/`PhilosophyEvaluationContext`/`Tension` from `mcp_bundle` — direct dep, no new dependency.) `AgentForkTensionDetectedEvent` added (`agent_event.dart`).
- No public API change (additive). Tests: `test/agent/24_assigned_axes_in_prompt_test.dart` (profile compose · philosophy block · opt-in pass-through · **fork tension emit · opt-in no-tension**) + `22_*` (facts) + **skill-refinement candidate (§4b)** + **§3 prohibition enforcement (TEST-25, real engine)**. **150 PASS · analyze 0.**

### Changed (dependency floor)
- `mcp_bundle` `^0.4.3` → `^0.4.4` — internal-dep latest (0.4.4 hardens the Ethos object-graph `fromJson` with field-named validation). flowbrain_core consumes the ethos via the philosophy port; no new symbol required, constraint kept current.
- `mcp_knowledge` `^0.2.4` → `^0.2.5` — **propagates the §3 prohibition-enforcement guarantee**: mcp_knowledge 0.2.5 floors `mcp_philosophy ^0.1.2` (deterministic `forbiddenPatterns` enforcement). Flooring it here ensures flowbrain's resolution actually carries the enforcing engine rather than relying on caret-resolves-to-latest — the §3 gate (TEST-25) is hollow without mcp_philosophy ≥ 0.1.2.

## 0.1.4 - 2026-06-14 - assigned facts compose into ask prompt

### Changed (behavior — additive, no API change)
- `AgentRuntime.ask` now composes the agent's **assigned facts** (set via `assignFacts` / `bk.agent.assign_facts`, stored under `AgentAxis.facts`) into the system prompt: base `systemPrompt` first, then an `## Assigned knowledge (facts)` section. Previously `ask` passed only the base `systemPrompt`, so assigned facts never reached the provider — a per-agent-knowledge-scoping gap (agent answered "I don't have that fact"). Facts are read from the agent's eager `OwnedFork` payload (handles live `OwnedFork` and persistent JSON `Map` forms), capped at 50 lines. No assigned facts → prompt identical to before (regression-safe). No public API change. Tests: `test/agent/22_assigned_facts_in_prompt_test.dart` (in-memory + **persistent JSON-KV round-trip**).

### Changed (dependency floor)
- `mcp_bundle` `^0.4.0` → `^0.4.3` — guarantees `FactRecord.toJson`/`fromJson`. Without it, assigned facts persisted via a *persistent* `KvStoragePort` serialize to `"Instance of 'FactRecord'"` (toString) and the compose above yields nothing — the fix only works end-to-end with serializable `FactRecord`. (In-memory KV worked regardless.)

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
