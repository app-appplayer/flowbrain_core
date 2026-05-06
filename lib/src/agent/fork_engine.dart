/// FlowBrain Core — ForkEngine.
///
/// Reads from Knowledge Subsystem, packages the result with fork metadata,
/// and writes the owned instance into `AgentRegistry`. P7 (Knowledge
/// Read-Only by Agent) + P8 (Fork Isolation) are enforced here. See:
///
///   - `os/core/flowbrain/docs/03_DDD/15-agent-fork-mechanism.md`
///   - FR-FBCORE-AGT-040..048
///
/// **Serialization note.** The `mcp_*` domain models (`SkillBundle`,
/// `Profile`, `Ethos`, `FactRecord`) currently expose `fromJson` only;
/// they do not provide `toJson`. To stay infrastructure-agnostic the engine
/// stores domain objects verbatim inside an `OwnedFork` envelope. In-memory
/// `KvStoragePort` adapters keep the object as-is; persistent adapters are
/// expected to wrap an explicit serializer (out of FlowBrain's scope).
library;

import 'package:mcp_knowledge/mcp_knowledge.dart' as mcp;

import '../system/knowledge_system.dart' show KnowledgeSystem;
import 'agent_config.dart';
import 'agent_event.dart';
import 'agent_lifecycle_fact.dart';
import 'agent_models.dart';
import 'agent_registry.dart';

/// Envelope written into `AgentRegistry` per fork. Holds the original
/// domain object + fork provenance.
///
/// [source] is sealed (`PoolForkSource` / `AgentForkSource`) so the fork
/// origin — pool seed vs. another agent's evolved instance — is explicit.
/// [lineage] is the encoded chain of every prior source on the way to this
/// fork (oldest first). Pool-rooted forks have a single-element lineage;
/// transfer chains accumulate one entry per hop.
class OwnedFork<T> {
  const OwnedFork({
    required this.payload,
    required this.source,
    required this.lineage,
    required this.forkOwnerAgentId,
    required this.forkedAt,
  });

  final T payload;
  final ForkSource source;
  final List<String> lineage;
  final String forkOwnerAgentId;
  final DateTime forkedAt;

  Map<String, Object?> toMetadata() => {
        'forked_from': source.encode(),
        'lineage': lineage,
        'forked_at': forkedAt.toIso8601String(),
        'fork_owner': forkOwnerAgentId,
      };

  /// JSON form for persistent `KvStoragePort` adapters. Pulls `payload`
  /// through a best-effort encoder — domain objects that ship a `toJson`
  /// method round-trip cleanly; anything else falls back to `toString()`.
  /// Adapters can opt in via `jsonEncode(value, toEncodable: ...)` or by
  /// detecting `OwnedFork` and calling this directly.
  Map<String, Object?> toJson() => {
        'payload': _payloadToJson(),
        'source': source.encode(),
        'lineage': lineage,
        'forkOwnerAgentId': forkOwnerAgentId,
        'forkedAt': forkedAt.toIso8601String(),
      };

  Object? _payloadToJson() {
    final p = payload;
    if (p == null) return null;
    if (p is num || p is bool || p is String) return p;
    if (p is List) return p;
    if (p is Map) return p;
    try {
      return (p as dynamic).toJson();
    } catch (_) {
      return p.toString();
    }
  }

  /// Reconstruct an envelope from the JSON form produced by [toJson].
  /// `payload` round-trips as whatever the original `_payloadToJson`
  /// emitted — typically a `Map` for domain objects with `toJson`. The
  /// caller is responsible for re-hydrating it into a domain instance if
  /// strict typing is needed; transfer flows treat the deserialized
  /// payload as opaque and re-store it under the new owner verbatim.
  static OwnedFork<Object?> fromJson(Map<String, Object?> json) {
    final sourceStr = json['source'] as String? ?? '';
    final source = ForkSource.decode(sourceStr) ?? PoolForkSource(sourceStr);
    final lineage =
        (json['lineage'] as List?)?.cast<String>() ?? <String>[];
    return OwnedFork<Object?>(
      payload: json['payload'],
      source: source,
      lineage: lineage,
      forkOwnerAgentId: json['forkOwnerAgentId'] as String? ?? '',
      forkedAt: DateTime.tryParse(json['forkedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// Lazy fork envelope (FR-FBCORE-AGT-046). Holds only the fork metadata
/// — no resolved payload — and defers the source dereference until the
/// agent actually needs the contents (read for transfer / explicit
/// materialize). Used by `ForkEngine` when [AgentConfig.forkPolicy] is
/// [ForkPolicy.copyOnWrite].
///
/// On the read path (`_resolvePayload(AgentForkSource(...))`): if the
/// owned record is a `LazyOwnedFork`, the engine resolves through
/// `source` instead of returning a stored payload.
///
/// On materialize (`ForkEngine.materialize`): the lazy envelope is
/// replaced at the same `forkedRef` key with a regular `OwnedFork`
/// carrying the now-resolved payload. A `LazyForkMaterializedEvent`
/// fires on the workspace event bus.
class LazyOwnedFork {
  const LazyOwnedFork({
    required this.source,
    required this.lineage,
    required this.forkOwnerAgentId,
    required this.forkedAt,
  });

  final ForkSource source;
  final List<String> lineage;
  final String forkOwnerAgentId;
  final DateTime forkedAt;

  Map<String, Object?> toMetadata() => {
        'forked_from': source.encode(),
        'lineage': lineage,
        'forked_at': forkedAt.toIso8601String(),
        'fork_owner': forkOwnerAgentId,
        'lazy': true,
      };

  Map<String, Object?> toJson() => {
        'lazy': true,
        'source': source.encode(),
        'lineage': lineage,
        'forkOwnerAgentId': forkOwnerAgentId,
        'forkedAt': forkedAt.toIso8601String(),
      };

  static LazyOwnedFork fromJson(Map<String, Object?> json) {
    final sourceStr = json['source'] as String? ?? '';
    final source = ForkSource.decode(sourceStr) ?? PoolForkSource(sourceStr);
    final lineage =
        (json['lineage'] as List?)?.cast<String>() ?? <String>[];
    return LazyOwnedFork(
      source: source,
      lineage: lineage,
      forkOwnerAgentId: json['forkOwnerAgentId'] as String? ?? '',
      forkedAt: DateTime.tryParse(json['forkedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  /// Detect a persistent-JSON form of [LazyOwnedFork] by the `lazy` flag
  /// (since persistent adapters typically round-trip envelopes through
  /// `Map<String, Object?>`).
  static bool isLazyJson(Object? raw) =>
      raw is Map && raw['lazy'] == true;
}

/// Performs the fork operation for each of the four axes.
class ForkEngine {
  ForkEngine({
    required AgentRegistry registry,
    required mcp.KnowledgeEventBus eventBus,
    required AgentConfig config,
  })  : _registry = registry,
        _eventBus = eventBus,
        // ignore: unused_field
        _config = config;

  final AgentRegistry _registry;
  final mcp.KnowledgeEventBus _eventBus;
  // Materialize de-duplication — collapses concurrent calls on the same
  // `(agentId, axis, forkedRef)` so only one payload resolution runs.
  final Map<String, Future<void>> _materializeInflight = {};
  // ignore: unused_field
  final AgentConfig _config;

  KnowledgeSystem _system() =>
      _registry.knowledgeSystemRef() as KnowledgeSystem;

  /// Stable forkedRef per `(agentId, source.encode())`. Pool-rooted forks
  /// look like `agentX::editor-default`, transferred forks like
  /// `agentB::A::editor-default` so the lineage is also visible in the key.
  String _forkedRef(String agentId, ForkSource source) {
    if (source is PoolForkSource) {
      return '$agentId::${source.poolId}';
    }
    if (source is AgentForkSource) {
      // `<target>::<sourceForkedRef>` — drop redundant `agentId/axis`
      // prefixes; the forkedRef itself already carries the chain.
      return '$agentId::${source.forkedRef}';
    }
    return '$agentId::${source.encode()}';
  }

  /// Resolve the lineage chain for a fork rooted in [source]. Pool sources
  /// produce a single-element lineage. Agent sources walk back through
  /// the source agent's `OwnedFork.lineage` and append the new hop —
  /// chains build up one transfer at a time.
  Future<List<String>> _resolveLineage(ForkSource source) async {
    if (source is PoolForkSource) {
      return [source.encode()];
    }
    if (source is AgentForkSource) {
      final parent = await _registry.getOwned(
        source.agentId,
        source.axis,
        source.forkedRef,
      );
      List<String> base;
      if (parent is OwnedFork) {
        base = List<String>.from(parent.lineage);
      } else if (parent is Map) {
        // Persistent adapter round-trip — deserialize lineage from JSON form.
        final envelope = OwnedFork.fromJson(Map<String, Object?>.from(parent));
        base = List<String>.from(envelope.lineage);
      } else {
        base = <String>[];
      }
      base.add(source.encode());
      return base;
    }
    return [source.encode()];
  }

  Future<void> _store({
    required String agentId,
    required AgentAxis axis,
    required ForkSource source,
    required Future<Object> Function() resolvePayload,
  }) async {
    final forkedRef = _forkedRef(agentId, source);
    final lineage = await _resolveLineage(source);
    final now = DateTime.now();
    // copyOnWrite (FR-FBCORE-AGT-046): defer the deep-copy by storing a
    // metadata-only envelope and skipping the source resolution until
    // the host explicitly materializes (or a future per-agent mutation
    // API materializes as its first step).
    final Object envelope;
    if (_config.forkPolicy == ForkPolicy.copyOnWrite) {
      envelope = LazyOwnedFork(
        source: source,
        lineage: lineage,
        forkOwnerAgentId: agentId,
        forkedAt: now,
      );
    } else {
      final payload = await resolvePayload();
      envelope = OwnedFork<Object>(
        payload: payload,
        source: source,
        lineage: lineage,
        forkOwnerAgentId: agentId,
        forkedAt: now,
      );
    }
    await _registry.storeOwned(
      agentId: agentId,
      axis: axis,
      sourceRef: source.encode(),
      forkedRef: forkedRef,
      payload: envelope,
    );
    _eventBus.emit(AgentForkAssignedEvent(
      agentId: agentId,
      axis: axis,
      sourceRef: source.encode(),
      forkedRef: forkedRef,
      timestamp: now,
    ));
    // Mirror the lifecycle event into the workspace FactGraph so hosts see
    // a uniform "who used what from when" timeline by querying facts alone
    // (FR-FBCORE-AGT-070). Best-effort — a fact write failure must not
    // corrupt the storeOwned that already succeeded above.
    if (_config.recordLifecycleAsFacts) {
      final agent = await _registry.get(agentId);
      if (agent != null) {
        try {
          final fact = const AgentLifecycleFactBuilder().forkAssigned(
            agentId: agentId,
            workspaceId: agent.workspaceId,
            axis: axis,
            source: source,
            forkedRef: forkedRef,
            lineage: lineage,
            timestamp: now,
          );
          await _system().facts.writeFacts([fact]);
        } catch (e) {
          // Best-effort — surface the silent failure via the event bus
          // so hosts can diagnose FactGraph adapter issues without
          // gating the storeOwned that already succeeded above.
          _eventBus.emit(AgentLifecycleFactFailedEvent(
            agentId: agentId,
            factType: AgentLifecycleFactType.forkAssigned,
            error: e.toString(),
            timestamp: DateTime.now(),
          ));
        }
      }
    }
  }

  /// Resolve [source] to the live domain payload for [axis]. Pool sources
  /// hit the Knowledge Subsystem facade; agent sources read the source
  /// agent's existing OwnedFork — the same payload object is shared
  /// (immutability is the contract; downstream evolution writes a new
  /// envelope).
  Future<Object> _resolvePayload(AgentAxis axis, ForkSource source) async {
    if (source is AgentForkSource) {
      if (source.axis != axis) {
        throw StateError(
          'Cross-axis transfer is not supported — source axis '
          '${source.axis.name} ≠ target axis ${axis.name}',
        );
      }
      final raw = await _registry.getOwned(
        source.agentId,
        source.axis,
        source.forkedRef,
      );
      // Lazy fork — recurse through the metadata-only envelope to its
      // own source. (FR-FBCORE-AGT-046 copyOnWrite branch.)
      if (raw is LazyOwnedFork) {
        return _resolvePayload(source.axis, raw.source);
      }
      if (LazyOwnedFork.isLazyJson(raw)) {
        final lazy =
            LazyOwnedFork.fromJson(Map<String, Object?>.from(raw as Map));
        return _resolvePayload(source.axis, lazy.source);
      }
      // In-memory adapters return the live OwnedFork; persistent adapters
      // round-trip through JSON and surface a `Map` (the form produced by
      // `OwnedFork.toJson`). Accept both — reconstruct from Map when
      // needed so transfer works regardless of KvStoragePort backend.
      if (raw is OwnedFork) {
        return raw.payload as Object;
      }
      if (raw is Map) {
        final envelope =
            OwnedFork.fromJson(Map<String, Object?>.from(raw));
        final p = envelope.payload;
        if (p == null) {
          throw StateError(
            'Source fork has null payload after deserialization: '
            'agent=${source.agentId} forkedRef=${source.forkedRef}',
          );
        }
        return p;
      }
      throw StateError(
        'Source fork not found: agent=${source.agentId} '
        'axis=${source.axis.name} forkedRef=${source.forkedRef}',
      );
    }
    final poolId = (source as PoolForkSource).poolId;
    switch (axis) {
      case AgentAxis.skill:
        final runtime = _system().skillRuntime;
        if (runtime == null) {
          throw StateError(
            'SkillRuntime not wired — cannot fork skill \'$poolId\' '
            '(activate L1 by passing skillRuntime to KnowledgeSystem).',
          );
        }
        final bundle = await runtime.registry.getSkill(poolId);
        if (bundle == null) {
          throw StateError('Skill \'$poolId\' not found in registry');
        }
        return bundle;
      case AgentAxis.profile:
        final p = _system().profile.get(poolId);
        if (p == null) {
          throw StateError('Profile \'$poolId\' not found in registry');
        }
        return p;
      case AgentAxis.philosophy:
        // Per-id ethos resolution via PhilosophyFacade.getEthosById
        // (mcp_knowledge ≥ 0.2.1). The facade reads from the wired
        // `KnowledgePorts.ethosStore` and falls back to the active
        // ethos when the store is unwired, the id is absent, or the
        // record's payload schema doesn't match. Returns an [Ethos]
        // so owned-fork payload shape stays stable.
        return await _system().philosophy.getEthosById(poolId);
      case AgentAxis.facts:
        // For facts, [poolId] must encode a FactQuery — not supported via
        // pool source string alone. Use [assignFacts] with a typed query.
        throw StateError(
          'Pool-source facts assignment requires a FactQuery — '
          'use assignFacts(agentId, query) directly.',
        );
    }
  }

  // ── Skill ───────────────────────────────────────────────────────────────

  /// Fork a skill from either the workspace pool or another agent's
  /// already-evolved owned instance. Source is sealed
  /// ([PoolForkSource] / [AgentForkSource]) so callers express their intent
  /// — initial assignment vs. transfer — at the type level.
  Future<void> assignSkill(String agentId, ForkSource source) async {
    await _store(
      agentId: agentId,
      axis: AgentAxis.skill,
      source: source,
      resolvePayload: () => _resolvePayload(AgentAxis.skill, source),
    );
  }

  // ── Profile ─────────────────────────────────────────────────────────────

  Future<void> assignProfile(String agentId, ForkSource source) async {
    await _store(
      agentId: agentId,
      axis: AgentAxis.profile,
      source: source,
      resolvePayload: () => _resolvePayload(AgentAxis.profile, source),
    );
  }

  // ── Philosophy ──────────────────────────────────────────────────────────

  /// Snapshot the active `Ethos` (pool source) or fork from another agent's
  /// owned philosophy instance (agent source). For pool sources the
  /// `poolId` is treated as a label for the snapshot.
  Future<void> assignPhilosophy(String agentId, ForkSource source) async {
    await _store(
      agentId: agentId,
      axis: AgentAxis.philosophy,
      source: source,
      resolvePayload: () => _resolvePayload(AgentAxis.philosophy, source),
    );
  }

  // ── Facts ───────────────────────────────────────────────────────────────

  /// Snapshot a `FactQuery` result — the only entry point for pool-rooted
  /// facts forks. The pool source is synthesized from the query hash.
  Future<void> assignFacts(String agentId, mcp.FactQuery query) async {
    final source = PoolForkSource('facts::${query.hashCode}');
    await _store(
      agentId: agentId,
      axis: AgentAxis.facts,
      source: source,
      resolvePayload: () async {
        final records = await _system().facts.queryFacts(query);
        return records;
      },
    );
  }

  /// Transfer a facts snapshot from another agent's owned fork. Mirrors
  /// the other axes' `assign*` shape so the agent-source path is callable
  /// uniformly across all four axes.
  Future<void> assignFactsFrom(String agentId, AgentForkSource source) async {
    if (source.axis != AgentAxis.facts) {
      throw StateError(
        'assignFactsFrom requires AgentForkSource.axis == facts; got '
        '${source.axis.name}',
      );
    }
    await _store(
      agentId: agentId,
      axis: AgentAxis.facts,
      source: source,
      resolvePayload: () => _resolvePayload(AgentAxis.facts, source),
    );
  }

  // ── Materialize (copyOnWrite → eager) ───────────────────────────────────

  /// Convert a lazy fork (`LazyOwnedFork`) at `(agentId, axis, forkedRef)`
  /// into an eager [OwnedFork] by resolving the source payload now and
  /// re-storing the envelope. No-op if the fork is already eager or the
  /// `forkedRef` does not exist.
  ///
  /// Concurrent calls on the same `(agentId, axis, forkedRef)` are
  /// collapsed — the second caller awaits the first call's resolution
  /// rather than racing the source resolve / re-store.
  ///
  /// Emits [LazyForkMaterializedEvent] on the workspace event bus when a
  /// lazy fork is converted. Idempotent for already-eager forks (no
  /// event).
  Future<void> materialize(
    String agentId,
    AgentAxis axis,
    String forkedRef,
  ) {
    final key = '$agentId|${axis.name}|$forkedRef';
    final existing = _materializeInflight[key];
    if (existing != null) return existing;
    final future = _runMaterialize(key, agentId, axis, forkedRef);
    _materializeInflight[key] = future;
    return future;
  }

  Future<void> _runMaterialize(
    String key,
    String agentId,
    AgentAxis axis,
    String forkedRef,
  ) async {
    try {
      await _materializeImpl(agentId, axis, forkedRef);
    } finally {
      _materializeInflight.remove(key);
    }
  }

  Future<void> _materializeImpl(
    String agentId,
    AgentAxis axis,
    String forkedRef,
  ) async {
    final raw = await _registry.getOwned(agentId, axis, forkedRef);
    if (raw == null) {
      throw StateError(
          'materialize: no owned record at agent=$agentId '
          'axis=${axis.name} forkedRef=$forkedRef');
    }
    LazyOwnedFork lazy;
    if (raw is LazyOwnedFork) {
      lazy = raw;
    } else if (LazyOwnedFork.isLazyJson(raw)) {
      lazy = LazyOwnedFork.fromJson(Map<String, Object?>.from(raw as Map));
    } else {
      // Already eager (OwnedFork or its JSON form) — no-op.
      return;
    }
    final payload = await _resolvePayload(axis, lazy.source);
    final eager = OwnedFork<Object>(
      payload: payload,
      source: lazy.source,
      lineage: lazy.lineage,
      forkOwnerAgentId: lazy.forkOwnerAgentId,
      forkedAt: lazy.forkedAt,
    );
    await _registry.storeOwned(
      agentId: agentId,
      axis: axis,
      sourceRef: lazy.source.encode(),
      forkedRef: forkedRef,
      payload: eager,
    );
    _eventBus.emit(LazyForkMaterializedEvent(
      agentId: agentId,
      axis: axis,
      sourceRef: lazy.source.encode(),
      forkedRef: forkedRef,
      timestamp: DateTime.now(),
    ));
  }

  // ── Unassign ────────────────────────────────────────────────────────────

  Future<void> unassign(
    String agentId,
    AgentAxis axis,
    String forkedRef,
  ) =>
      _registry.removeOwned(agentId, axis, forkedRef);
}
