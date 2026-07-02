/// FlowBrain Core — AgentFacade.
///
/// Single entry point of the Agent Subsystem. Delegates to AgentRegistry +
/// AgentRuntime + ForkEngine + ConversationStore. Holds no business logic.
/// See:
///
///   - `os/core/flowbrain/docs/03_DDD/11-agent-facade.md`
///   - FR-FBCORE-AGT-050..052
library;

import 'package:mcp_bundle/mcp_bundle.dart' show EthosStorePort, LlmTool;
import 'package:mcp_knowledge/mcp_knowledge.dart' show FactQuery;

import '../system/knowledge_system.dart' show KnowledgeSystem;
import 'agent_exception.dart';
import 'agent_models.dart';
import 'agent_registry.dart';
import 'agent_runtime.dart';
import 'conversation_store.dart';
import 'fork_engine.dart';

/// User-visible Agent Subsystem facade. Created once per `KnowledgeSystem`
/// and exposed as `system.agents`.
///
/// When the Agent Subsystem is not activated (either `agentRegistry` or
/// `agentRuntime` is `null` at `KnowledgeSystem` construction), the
/// wrapping `KnowledgeSystem` instantiates a stub via [AgentFacade.stub]
/// and the first method call throws `StateError` per FR-FBCORE-RES-001(d).
class AgentFacade {
  /// Wire the Agent Subsystem. Forks/Conversation are pulled from
  /// `runtime` to keep the wiring surface small.
  AgentFacade({required AgentRuntime runtime})
      : _registry = runtime.registry,
        _runtime = runtime,
        _forkEngine = runtime.forkEngine,
        _conversationStore = runtime.conversationStore,
        _activated = true;

  /// Stub facade used when the Agent Subsystem is not wired. Every method
  /// throws `StateError`.
  AgentFacade.stub()
      : _registry = null,
        _runtime = null,
        _forkEngine = null,
        _conversationStore = null,
        _activated = false;

  final AgentRegistry? _registry;
  final AgentRuntime? _runtime;
  final ForkEngine? _forkEngine;
  final ConversationStore? _conversationStore;
  final bool _activated;

  bool get isActivated => _activated;

  void _requireActivated() {
    if (!_activated) {
      throw StateError(
        'Agent Subsystem not activated — wire `agentRegistry` and '
        '`agentRuntime` at KnowledgeSystem construction.',
      );
    }
  }

  // ── Agent CRUD ──────────────────────────────────────────────────────────

  Future<Agent> createAgent({
    required String id,
    required String displayName,
    AgentRole role = AgentRole.worker,
    required ModelSpec model,
    required String workspaceId,
    String? systemPrompt,
    Map<String, String> tags = const {},
  }) {
    _requireActivated();
    return _registry!.create(
      id: id,
      displayName: displayName,
      role: role,
      model: model,
      workspaceId: workspaceId,
      systemPrompt: systemPrompt,
      tags: tags,
    );
  }

  Future<Agent?> getAgent(String agentId) {
    _requireActivated();
    return _registry!.get(agentId);
  }

  Future<List<Agent>> listAgents({String? role, String? workspaceId}) {
    _requireActivated();
    return _registry!.list(role: role, workspaceId: workspaceId);
  }

  Future<Agent> updateAgent(
    String agentId, {
    String? displayName,
    AgentRole? role,
    ModelSpec? model,
    String? systemPrompt,
    Map<String, String>? tags,
  }) {
    _requireActivated();
    return _registry!.update(
      agentId,
      displayName: displayName,
      role: role,
      model: model,
      systemPrompt: systemPrompt,
      tags: tags,
    );
  }

  Future<void> deleteAgent(String agentId) async {
    _requireActivated();
    await _conversationStore!.remove(agentId);
    await _registry!.delete(agentId);
  }

  // ── Fork assignment ─────────────────────────────────────────────────────
  //
  // [source] is sealed (`PoolForkSource` / `AgentForkSource`) so the same
  // method covers initial assignment from the workspace pool *and* transfer
  // from another agent's already-evolved owned instance — the multi-agent
  // value surface (FR-FBCORE-AGT-040+).
  //
  // String-based shortcuts are provided for the common pool case so
  // existing callers do not have to construct `PoolForkSource` by hand.

  Future<void> assignSkill(String agentId, ForkSource source) {
    _requireActivated();
    return _forkEngine!.assignSkill(agentId, source);
  }

  Future<void> assignSkillFromPool(String agentId, String skillId) =>
      assignSkill(agentId, PoolForkSource(skillId));

  Future<void> assignProfile(String agentId, ForkSource source) {
    _requireActivated();
    return _forkEngine!.assignProfile(agentId, source);
  }

  Future<void> assignProfileFromPool(String agentId, String profileId) =>
      assignProfile(agentId, PoolForkSource(profileId));

  Future<void> assignPhilosophy(String agentId, ForkSource source) {
    _requireActivated();
    return _forkEngine!.assignPhilosophy(agentId, source);
  }

  Future<void> assignPhilosophyFromPool(String agentId, String ethosId) =>
      assignPhilosophy(agentId, PoolForkSource(ethosId));

  /// Convert a lazy fork (FR-FBCORE-AGT-046 `forkPolicy: copyOnWrite`)
  /// into an eager owned copy by resolving the source payload now.
  /// No-op when the fork is already eager or `forkedRef` is unknown.
  /// Concurrent calls on the same `(agentId, axis, forkedRef)` are
  /// collapsed via `ForkEngine`'s in-flight map.
  Future<void> materialize(
    String agentId,
    AgentAxis axis,
    String forkedRef,
  ) {
    _requireActivated();
    return _forkEngine!.materialize(agentId, axis, forkedRef);
  }

  Future<void> assignFacts(String agentId, FactQuery query) {
    _requireActivated();
    return _forkEngine!.assignFacts(agentId, query);
  }

  /// Transfer a facts snapshot from another agent's owned fork.
  Future<void> assignFactsFromAgent(
    String agentId,
    AgentForkSource source,
  ) {
    _requireActivated();
    return _forkEngine!.assignFactsFrom(agentId, source);
  }

  Future<void> unassign(String agentId, AgentAxis axis, String forkedRef) {
    _requireActivated();
    return _forkEngine!.unassign(agentId, axis, forkedRef);
  }

  /// Best-effort skill assignment — returns `false` and skips silently when
  /// SkillRuntime is not wired or the skill is missing in the registry.
  /// `AgentNotFoundException` (the only structural failure) still propagates.
  Future<bool> tryAssignSkill(String agentId, ForkSource source) async {
    _requireActivated();
    await _ensureAgent(agentId);
    try {
      await _forkEngine!.assignSkill(agentId, source);
      return true;
    } on StateError {
      return false;
    }
  }

  Future<bool> tryAssignSkillFromPool(String agentId, String skillId) =>
      tryAssignSkill(agentId, PoolForkSource(skillId));

  Future<bool> tryAssignProfile(String agentId, ForkSource source) async {
    _requireActivated();
    await _ensureAgent(agentId);
    try {
      await _forkEngine!.assignProfile(agentId, source);
      return true;
    } on StateError {
      return false;
    }
  }

  Future<bool> tryAssignProfileFromPool(String agentId, String profileId) =>
      tryAssignProfile(agentId, PoolForkSource(profileId));

  Future<bool> tryAssignPhilosophy(String agentId, ForkSource source) async {
    _requireActivated();
    await _ensureAgent(agentId);
    try {
      await _forkEngine!.assignPhilosophy(agentId, source);
      return true;
    } on StateError {
      return false;
    }
  }

  Future<bool> tryAssignPhilosophyFromPool(String agentId, String ethosId) =>
      tryAssignPhilosophy(agentId, PoolForkSource(ethosId));

  Future<bool> tryAssignFacts(String agentId, FactQuery query) async {
    _requireActivated();
    await _ensureAgent(agentId);
    try {
      await _forkEngine!.assignFacts(agentId, query);
      return true;
    } on StateError {
      return false;
    }
  }

  Future<void> _ensureAgent(String agentId) async {
    final agent = await _registry!.get(agentId);
    if (agent == null) throw AgentNotFoundException(agentId);
  }

  // ── Conversation ────────────────────────────────────────────────────────

  /// [resetContext] = true wipes the conversation history before this
  /// ask composes its prompt — useful for manager agents whose every
  /// turn should be treated as fresh (avoids unbounded context growth
  /// + stale prior-turn pollution that weakens current directive).
  /// The post-ask turn is still appended; the reset is one-shot.
  Future<AgentReply> ask(
    String agentId,
    String message, {
    Map<String, Object?>? context,
    List<LlmTool>? tools,
    bool resetContext = false,
  }) {
    _requireActivated();
    return _runtime!.ask(
      agentId,
      message,
      context: context,
      tools: tools,
      resetContext: resetContext,
    );
  }

  Stream<AgentToken> stream(
    String agentId,
    String message, {
    Map<String, Object?>? context,
    List<LlmTool>? tools,
  }) {
    _requireActivated();
    return _runtime!
        .stream(agentId, message, context: context, tools: tools);
  }

  Future<List<ConversationTurn>> getHistory(
    String agentId, {
    int? limit,
  }) {
    _requireActivated();
    return _conversationStore!.load(agentId, limit: limit);
  }

  Future<void> clearHistory(String agentId) {
    _requireActivated();
    return _conversationStore!.clear(agentId);
  }

  // ── Integrated axis listing ────────────────────────────────────────────

  /// Workspace-level integrated view of one axis: pool starters (Knowledge
  /// Subsystem seed definitions) **plus** every agent's owned forks rolled
  /// into a single union list. Any entry — pool seed or another agent's
  /// evolved instance — is a valid source for a new fork via
  /// [assignSkill]/[assignProfile]/etc. with the entry's [ForkSource].
  ///
  /// [workspaceId] scopes the agent half of the union to that workspace;
  /// pool starters come from the global Knowledge Subsystem facades and are
  /// included unconditionally. UI pickers (member detail · transfer flow)
  /// consume this list directly.
  Future<List<IntegratedAxisEntry>> listIntegrated(
    String workspaceId,
    AgentAxis axis,
  ) async {
    _requireActivated();
    final out = <IntegratedAxisEntry>[];

    // 1. Pool starters — read straight from the Knowledge Subsystem facade
    //    for this axis. `_runtime!.registry.knowledgeSystemRef()` resolves
    //    the live `KnowledgeSystem` lazily so the facade collection sees
    //    the latest pool state.
    out.addAll(await _poolStarters(axis));

    // 2. Agent-owned forks — every agent in the workspace contributes its
    //    `listOwned(axis)` entries. Each entry's source/lineage are read
    //    back from the stored `OwnedFork` envelope so transfer chains stay
    //    visible.
    final agents = await _registry!.list(workspaceId: workspaceId);
    for (final agent in agents) {
      final entries = await _registry!.listOwned(agent.id, axis);
      for (final entry in entries) {
        final stored = await _registry!.getOwned(
          agent.id,
          axis,
          entry.forkedRef,
        );
        ForkSource entrySource;
        List<String> lineage;
        if (stored is OwnedFork) {
          entrySource = stored.source;
          lineage = stored.lineage;
        } else {
          // Defensive fallback for adapters that strip the envelope —
          // recover the source from the indexed sourceRef if possible.
          entrySource = ForkSource.decode(entry.sourceRef) ??
              PoolForkSource(entry.sourceRef);
          lineage = [entry.sourceRef];
        }
        out.add(IntegratedAxisEntry(
          source: AgentForkSource(
            agentId: agent.id,
            axis: axis,
            forkedRef: entry.forkedRef,
          ),
          displayLabel: '${agent.displayName} · ${entry.forkedRef}',
          ownerAgentId: agent.id,
          lineage: lineage,
        ));
        // Suppress unused warning until wider refactor wires entrySource
        // into entry-level diagnostics.
        // ignore: unused_local_variable
        final _ = entrySource;
      }
    }
    return out;
  }

  Future<List<IntegratedAxisEntry>> _poolStarters(AgentAxis axis) async {
    final out = <IntegratedAxisEntry>[];
    final system = _registry!.knowledgeSystemRef() as KnowledgeSystem;
    switch (axis) {
      case AgentAxis.skill:
        try {
          final runtime = system.skillRuntime;
          if (runtime == null) break;
          // `SkillBundleRegistry.listSkills({workspaceId?})` — call without
          // a workspace filter so every registered skill surfaces (UI
          // picker filters per-workspace by enablement, not by listing).
          final list = await runtime.registry.listSkills();
          for (final s in list) {
            final id = s.manifest.id;
            if (id.isEmpty) continue;
            final name = s.manifest.name;
            out.add(IntegratedAxisEntry(
              source: PoolForkSource(id),
              displayLabel: name.isEmpty || name == id ? id : '$name · $id',
              lineage: ['pool:$id'],
            ));
          }
        } catch (_) {
          // Pool not available — skip; agent forks still surface.
        }
        break;
      case AgentAxis.profile:
        try {
          final list = system.profile.list();
          for (final p in list) {
            final id = p.id;
            if (id.isEmpty) continue;
            out.add(IntegratedAxisEntry(
              source: PoolForkSource(id),
              displayLabel: id,
              lineage: ['pool:$id'],
            ));
          }
        } catch (_) {}
        break;
      case AgentAxis.philosophy:
        // Multi-ethos enumeration when an EthosStorePort is wired —
        // every record in the store surfaces as a pool starter so a
        // workspace with both `ads-core` and `editorial-core` shows
        // both. Falls back to the single active ethos of
        // PhilosophyFacade when no store is wired (older hosts /
        // smoke tests).
        final EthosStorePort? store = system.ethosStore;
        if (store != null) {
          try {
            final list = await store.listEthos();
            for (final r in list) {
              final id = r.id;
              if (id.isEmpty) continue;
              out.add(IntegratedAxisEntry(
                source: PoolForkSource(id),
                displayLabel: r.name.isEmpty ? id : '${r.name} · $id',
                lineage: ['pool:$id'],
              ));
            }
            break;
          } catch (_) {
            // fall through to single-active fallback
          }
        }
        try {
          final ethos = await system.philosophy.getEthos();
          final id = ethos.id.isEmpty ? 'active' : ethos.id;
          out.add(IntegratedAxisEntry(
            source: PoolForkSource(id),
            displayLabel: 'philosophy · $id',
            lineage: ['pool:$id'],
          ));
        } catch (_) {}
        break;
      case AgentAxis.facts:
        // Facts have no enumerable pool — every forked snapshot carries a
        // synthetic `facts::<hash>` source produced by `assignFacts`.
        // Pool starters are therefore not listable independently.
        break;
    }
    return out;
  }

  // ── Manager / Reviewer ─────────────────────────────────────────────────

  Future<RoutingDecision> route(
    String managerId,
    String request, {
    List<String>? candidateAgentIds,
  }) {
    _requireActivated();
    return _runtime!.route(
      managerId,
      request,
      candidateAgentIds: candidateAgentIds,
    );
  }

  Future<ReviewResult> review(String reviewerId, AgentReply targetReply) {
    _requireActivated();
    return _runtime!.review(reviewerId, targetReply);
  }

  // ── Lifecycle (called by KnowledgeSystem.shutdown) ─────────────────────

  Future<void> shutdownInternal() async {
    if (!_activated) return;
    await _runtime!.shutdown();
  }
}
