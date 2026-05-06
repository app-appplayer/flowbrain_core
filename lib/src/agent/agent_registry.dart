/// FlowBrain Core — AgentRegistry.
///
/// CRUD over the Agent model + agent-owned 4-axis storage + Growth Tracker.
/// Knowledge Subsystem mutating APIs are not invoked here (NFR-FBCORE-ISO-004).
/// See:
///
///   - `os/core/flowbrain/docs/03_DDD/12-agent-registry.md`
///   - FR-FBCORE-AGT-010..015
library;

import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart' show KvStoragePort;
import 'package:mcp_knowledge/mcp_knowledge.dart' show KnowledgeEventBus;

// We import the wrapping `KnowledgeSystem` lazily through a Function reference
// in the constructor — see DDD-12 §2 for the cycle-avoidance rationale.
import 'agent_config.dart';
import 'agent_event.dart';
import 'agent_exception.dart';
import 'agent_lifecycle_fact.dart';
import 'agent_models.dart';

/// Forward declaration to keep `agent_registry.dart` decoupled from the
/// concrete `KnowledgeSystem` wrapper class. The wrapper supplies `() =>
/// system` at wire time.
typedef KnowledgeSystemRef = Object Function();

class AgentRegistry {
  AgentRegistry({
    required KvStoragePort kvStorage,
    required KnowledgeSystemRef knowledgeSystemRef,
    required AgentConfig config,
    required KnowledgeEventBus eventBus,
  })  : _kv = kvStorage,
        // ignore: unused_element
        _knowledgeSystemRef = knowledgeSystemRef,
        _config = config,
        _eventBus = eventBus;

  final KvStoragePort _kv;
  // Held for callers that want to read Knowledge Subsystem state. Reads must
  // remain side-effect free (P7).
  // ignore: unused_field
  final KnowledgeSystemRef _knowledgeSystemRef;
  final AgentConfig _config;
  final KnowledgeEventBus _eventBus;

  /// Exposed so cooperating components (ForkEngine, AgentRuntime) can
  /// retrieve the wrapping system without holding a separate reference.
  KnowledgeSystemRef get knowledgeSystemRef => _knowledgeSystemRef;

  // ── Storage key helpers ─────────────────────────────────────────────────

  String _agentKey(String workspaceId, String agentId) =>
      'agent/$workspaceId/$agentId';
  String _ownedKey(AgentAxis axis, String agentId, String forkedRef) =>
      'agent_owned_${axis.name}/$agentId/$forkedRef';
  String _indexKey(String agentId, AgentAxis axis) =>
      'agent_owned_index/$agentId/${axis.name}';

  // ── Agent CRUD ──────────────────────────────────────────────────────────

  /// Create an agent. Throws `StateError` on duplicate id or when the
  /// per-workspace cap is exceeded.
  Future<Agent> create({
    required String id,
    required String displayName,
    AgentRole role = AgentRole.worker,
    required ModelSpec model,
    required String workspaceId,
    String? systemPrompt,
    Map<String, String> tags = const {},
  }) async {
    final key = _agentKey(workspaceId, id);
    if (await _kv.exists(key)) {
      throw StateError('Duplicate agent id: $id (workspace=$workspaceId)');
    }
    final cap = _config.maxAgentsPerWorkspace;
    if (cap != null) {
      final existing = await list(workspaceId: workspaceId);
      if (existing.length >= cap) {
        throw StateError(
          'maxAgentsPerWorkspace ($cap) exceeded in workspace=$workspaceId',
        );
      }
    }
    final agent = Agent(
      id: id,
      displayName: displayName,
      role: role,
      model: model,
      workspaceId: workspaceId,
      createdAt: DateTime.now(),
      systemPrompt: systemPrompt,
      tags: tags,
    );
    await _kv.set(key, jsonEncode(agent.toJson()));
    _eventBus.emit(AgentCreatedEvent(
      agentId: id,
      displayName: displayName,
      role: role,
      model: model,
      timestamp: DateTime.now(),
    ));
    return agent;
  }

  /// Look up an agent by id. The workspace is inferred by scanning prefixes
  /// (callers usually keep workspace context themselves; this convenience is
  /// O(N) over registered agents).
  Future<Agent?> get(String agentId) async {
    final keys = await _kv.keys(prefix: 'agent/');
    for (final key in keys) {
      // Skip owned-axis indices and other namespaces.
      if (!key.startsWith('agent/')) continue;
      if (!key.endsWith('/$agentId')) continue;
      final raw = await _kv.get(key);
      if (raw is String) {
        return Agent.fromJson(
            (jsonDecode(raw) as Map).cast<String, Object?>());
      }
    }
    return null;
  }

  Future<List<Agent>> list({String? role, String? workspaceId}) async {
    final prefix =
        workspaceId != null ? 'agent/$workspaceId/' : 'agent/';
    final keys = await _kv.keys(prefix: prefix);
    final agents = <Agent>[];
    for (final key in keys) {
      // Filter out nested namespaces (`agent_owned_*`, `agent_owned_index/`).
      if (!key.startsWith('agent/')) continue;
      final raw = await _kv.get(key);
      if (raw is! String) continue;
      try {
        final agent = Agent.fromJson(
            (jsonDecode(raw) as Map).cast<String, Object?>());
        if (role != null && agent.role.name != role) continue;
        agents.add(agent);
      } catch (e) {
        // Tolerate stray entries — caller can re-create. Surface the
        // corruption so hosts can audit, but keep the recovery in place.
        _emitCorruption(
          agentId: key.split('/').last,
          keyKind: 'agent',
          key: key,
          error: e,
        );
      }
    }
    return agents;
  }

  Future<Agent> update(
    String agentId, {
    String? displayName,
    ModelSpec? model,
    String? systemPrompt,
    Map<String, String>? tags,
  }) async {
    final current = await get(agentId);
    if (current == null) throw AgentNotFoundException(agentId);
    final next = current.copyWith(
      displayName: displayName,
      model: model,
      systemPrompt: systemPrompt,
      tags: tags,
    );
    await _kv.set(_agentKey(current.workspaceId, agentId),
        jsonEncode(next.toJson()));
    return next;
  }

  /// Delete an agent and all owned axis storage. Conversation cleanup is the
  /// caller's responsibility (handled by `AgentFacade` via
  /// `ConversationStore.remove`).
  Future<void> delete(String agentId) async {
    final current = await get(agentId);
    if (current == null) throw AgentNotFoundException(agentId);

    // Remove all owned-axis entries via index lookup.
    for (final axis in AgentAxis.values) {
      final indexRaw = await _kv.get(_indexKey(agentId, axis));
      if (indexRaw is String) {
        try {
          final entries =
              (jsonDecode(indexRaw) as Map).cast<String, String>();
          for (final forkedRef in entries.values) {
            await _kv.remove(_ownedKey(axis, agentId, forkedRef));
          }
        } catch (e) {
          // Ignore index corruption — best-effort cleanup. Surface the
          // event so hosts can detect that some owned-fork records may
          // have been orphaned by the corrupt index.
          _emitCorruption(
            agentId: agentId,
            keyKind: 'index',
            key: _indexKey(agentId, axis),
            error: e,
          );
        }
      }
      await _kv.remove(_indexKey(agentId, axis));
    }

    await _kv.remove(_agentKey(current.workspaceId, agentId));
    final deletedAt = DateTime.now();
    _eventBus.emit(AgentDeletedEvent(
      agentId: agentId,
      timestamp: deletedAt,
    ));
    // Mirror into FactGraph — closes the agent's open lifecycle so a
    // FactQuery(entityId: agentId) returns "from … until deleted" cleanly.
    if (_config.recordLifecycleAsFacts) {
      try {
        final ks = knowledgeSystemRef() as dynamic;
        final fact = const AgentLifecycleFactBuilder().agentDeleted(
          agentId: agentId,
          workspaceId: current.workspaceId,
          timestamp: deletedAt,
        );
        await ks.facts.writeFacts([fact]);
      } catch (e) {
        _eventBus.emit(AgentLifecycleFactFailedEvent(
          agentId: agentId,
          factType: AgentLifecycleFactType.agentDeleted,
          error: e.toString(),
          timestamp: DateTime.now(),
        ));
      }
    }
  }

  // ── Owned axis storage ──────────────────────────────────────────────────

  /// Persist a forked owned instance. `payload` may be either a domain
  /// object (kept as-is by in-memory adapters) or a `Map`/`String`
  /// representation produced by the host. `AgentRegistry` is agnostic to
  /// the underlying domain model.
  Future<void> storeOwned({
    required String agentId,
    required AgentAxis axis,
    required String sourceRef,
    required String forkedRef,
    required Object? payload,
  }) async {
    // Conflict check (FR-FBCORE-AGT-045).
    final existing = await getOwnedRef(agentId, axis, sourceRef);
    if (existing != null && existing != forkedRef) {
      throw ForkConflictException(
        agentId: agentId,
        axis: axis,
        sourceRef: sourceRef,
        existingForkedRef: existing,
      );
    }
    await _kv.set(_ownedKey(axis, agentId, forkedRef), payload);
    await _appendIndex(agentId, axis, sourceRef, forkedRef);
  }

  /// Retrieve a previously stored owned instance. The return type is
  /// `Object?` since the underlying `KvStoragePort` adapter chooses how to
  /// serialize / round-trip (in-memory adapters return the object as-is;
  /// persistent adapters typically return JSON-decoded `Map`s).
  Future<Object?> getOwned(
    String agentId,
    AgentAxis axis,
    String forkedRef,
  ) =>
      _kv.get(_ownedKey(axis, agentId, forkedRef));

  /// Resolve the forkedRef for an `(agentId, axis, sourceRef)` triple, if
  /// any.
  Future<String?> getOwnedRef(
    String agentId,
    AgentAxis axis,
    String sourceRef,
  ) async {
    final raw = await _kv.get(_indexKey(agentId, axis));
    if (raw is! String) return null;
    try {
      final entries = (jsonDecode(raw) as Map).cast<String, String>();
      return entries[sourceRef];
    } catch (e) {
      _emitCorruption(
        agentId: agentId,
        keyKind: 'index',
        key: _indexKey(agentId, axis),
        error: e,
      );
      return null;
    }
  }

  Future<List<({String sourceRef, String forkedRef})>> listOwned(
    String agentId,
    AgentAxis axis,
  ) async {
    final raw = await _kv.get(_indexKey(agentId, axis));
    if (raw is! String) return const [];
    try {
      final entries = (jsonDecode(raw) as Map).cast<String, String>();
      return entries.entries
          .map((e) => (sourceRef: e.key, forkedRef: e.value))
          .toList();
    } catch (e) {
      _emitCorruption(
        agentId: agentId,
        keyKind: 'index',
        key: _indexKey(agentId, axis),
        error: e,
      );
      return const [];
    }
  }

  Future<void> removeOwned(
    String agentId,
    AgentAxis axis,
    String forkedRef,
  ) async {
    await _kv.remove(_ownedKey(axis, agentId, forkedRef));
    final raw = await _kv.get(_indexKey(agentId, axis));
    if (raw is! String) return;
    try {
      final entries = (jsonDecode(raw) as Map).cast<String, String>();
      entries.removeWhere((_, v) => v == forkedRef);
      await _kv.set(_indexKey(agentId, axis), jsonEncode(entries));
    } catch (e) {
      // Ignore — index corruption is non-fatal. Surface so hosts can
      // detect that the removeOwned call did not also reconcile the
      // axis index (the owned record is gone, but the index still
      // points at it).
      _emitCorruption(
        agentId: agentId,
        keyKind: 'index',
        key: _indexKey(agentId, axis),
        error: e,
      );
    }
  }

  Future<void> _appendIndex(
    String agentId,
    AgentAxis axis,
    String sourceRef,
    String forkedRef,
  ) async {
    final raw = await _kv.get(_indexKey(agentId, axis));
    final entries = <String, String>{};
    if (raw is String) {
      try {
        entries.addAll((jsonDecode(raw) as Map).cast<String, String>());
      } catch (e) {
        // Reset on corruption — surface so hosts know prior index entries
        // were dropped on this write.
        _emitCorruption(
          agentId: agentId,
          keyKind: 'index',
          key: _indexKey(agentId, axis),
          error: e,
        );
      }
    }
    entries[sourceRef] = forkedRef;
    await _kv.set(_indexKey(agentId, axis), jsonEncode(entries));
  }

  void _emitCorruption({
    required String agentId,
    required String keyKind,
    required String key,
    required Object error,
  }) {
    _eventBus.emit(KvIndexCorruptionEvent(
      agentId: agentId,
      keyKind: keyKind,
      key: key,
      error: error.toString(),
      timestamp: DateTime.now(),
    ));
  }

  // ── Growth Tracker ──────────────────────────────────────────────────────

  /// Record an evolution observed by Growth Tracker. Always increments
  /// counters; only emits the event when `enableGrowthTracking` is true
  /// (FR-FBCORE-CFG-010 / AGT-014).
  Future<void> recordEvolution({
    required String agentId,
    required AgentAxis axis,
    required String forkedRef,
    required GrowthKind kind,
  }) async {
    final agent = await get(agentId);
    if (agent == null) throw AgentNotFoundException(agentId);
    final now = DateTime.now();
    final updatedGrowth = axis == AgentAxis.facts
        ? agent.growth.bumpFacts(at: now)
        : agent.growth.bump(kind, at: now);
    final updated = agent.copyWith(growth: updatedGrowth);
    await _kv.set(
      _agentKey(updated.workspaceId, agentId),
      jsonEncode(updated.toJson()),
    );
    if (_config.enableGrowthTracking) {
      _eventBus.emit(AgentForkEvolvedEvent(
        agentId: agentId,
        axis: axis,
        forkedRef: forkedRef,
        kind: kind,
        timestamp: now,
      ));
    }
    // Mirror into FactGraph regardless of growth tracking — the timeline is
    // observability and stays even when host disables growth events.
    if (_config.recordLifecycleAsFacts) {
      try {
        final ks = knowledgeSystemRef() as dynamic;
        final fact = const AgentLifecycleFactBuilder().forkEvolved(
          agentId: agentId,
          workspaceId: updated.workspaceId,
          axis: axis,
          forkedRef: forkedRef,
          kind: kind,
          timestamp: now,
        );
        await ks.facts.writeFacts([fact]);
      } catch (e) {
        _eventBus.emit(AgentLifecycleFactFailedEvent(
          agentId: agentId,
          factType: AgentLifecycleFactType.forkEvolved,
          error: e.toString(),
          timestamp: DateTime.now(),
        ));
      }
    }
  }
}
