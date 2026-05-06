/// FlowBrain Core — ConversationStore.
///
/// Per-agent LLM conversation context storage. Guarantees P6 Agent
/// Self-Containment — one agent's history never leaks into another's
/// prompt build (DDD-14 §8). Uses `KvStoragePort` with key prefix
/// `conv/<agentId>/`. See:
///
///   - `os/core/flowbrain/docs/03_DDD/14-agent-conversation-store.md`
///   - FR-FBCORE-AGT-030..034
library;

import 'dart:async';
import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart' show KvStoragePort;

import 'agent_config.dart';
import 'agent_exception.dart';
import 'agent_models.dart';

/// Storage of per-agent conversation history. TTL sweeper + compression are
/// driven by `AgentConfig`.
class ConversationStore {
  ConversationStore({
    required KvStoragePort kvStorage,
    required AgentConfig config,
  })  : _kv = kvStorage,
        _config = config {
    if (_config.conversationTtl > Duration.zero) {
      _ttlTimer = Timer.periodic(
        _ttlSweepInterval,
        (_) => _sweepExpired().catchError((_) {
          // Sweeper failures are intentionally swallowed to avoid disrupting
          // unrelated work. Manual `clear` remains available.
        }),
      );
    }
  }

  final KvStoragePort _kv;
  final AgentConfig _config;
  Timer? _ttlTimer;
  bool _closed = false;

  /// Fixed sweep interval — independent of TTL itself. One hour is a balance
  /// between timely cleanup and storage pressure.
  static const Duration _ttlSweepInterval = Duration(hours: 1);

  /// Load up to [limit] most recent turns. When the agent has been
  /// compressed, the oldest entry is the summary placeholder.
  Future<List<ConversationTurn>> load(
    String agentId, {
    int? limit,
  }) async {
    _ensureOpen();
    final raw = await _kv.get(_turnsKey(agentId));
    if (raw == null) return const [];
    final decoded = jsonDecode(raw as String);
    if (decoded is! List) return const [];
    final turns = decoded
        .cast<Object>()
        .map((e) =>
            ConversationTurn.fromJson((e as Map).cast<String, Object?>()))
        .toList();
    final cap = limit ?? _config.maxConversationTurns;
    if (cap > 0 && turns.length > cap) {
      // Preserve a leading summary placeholder so callers always see the
      // compressed-history marker when one is present.
      final hasSummary = turns.isNotEmpty &&
          turns.first.userMessage == '<compressed-history>';
      if (hasSummary && cap >= 1) {
        final tailCount = cap - 1;
        return [turns.first, ...turns.sublist(turns.length - tailCount)];
      }
      return turns.sublist(turns.length - cap);
    }
    return turns;
  }

  /// Append a turn, then compress if `maxConversationTurns` is exceeded.
  Future<void> append(String agentId, ConversationTurn turn) async {
    _ensureOpen();
    final existing = await load(agentId, limit: -1);
    final next = [...existing, turn];
    final cap = _config.maxConversationTurns;
    final compacted = (cap > 0 && next.length > cap)
        ? _compressOldest(next, cap)
        : next;
    await _kv.set(_turnsKey(agentId),
        jsonEncode(compacted.map((t) => t.toJson()).toList()));
    await _kv.set(_lastAtKey(agentId), turn.timestamp.toIso8601String());
  }

  Future<void> clear(String agentId) async {
    _ensureOpen();
    await _kv.remove(_turnsKey(agentId));
    await _kv.remove(_lastAtKey(agentId));
    await _kv.remove(_summaryKey(agentId));
  }

  /// Remove all conversation traces for a deleted agent. Safe to call even
  /// when the agent had no conversation.
  Future<void> remove(String agentId) => clear(agentId);

  /// Best-effort flush. The current `KvStoragePort` contract is
  /// write-through, so this is a no-op; provided for future buffered
  /// adapters.
  Future<void> flushAll() async {
    _ensureOpen();
  }

  /// Stop the TTL sweeper and disable further mutations.
  Future<void> shutdown() async {
    _ttlTimer?.cancel();
    _ttlTimer = null;
    _closed = true;
  }

/// Force a TTL sweep immediately. Visible for tests — production code
/// relies on the periodic timer.
  Future<void> debugSweepNow() => _sweepExpired();

  // ── Internal ────────────────────────────────────────────────────────────

  void _ensureOpen() {
    if (_closed) {
      throw const ConversationStoreUnavailableException(
        'ConversationStore is shut down',
      );
    }
  }

  String _turnsKey(String agentId) => 'conv/$agentId/turns';
  String _lastAtKey(String agentId) => 'conv/$agentId/lastAt';
  String _summaryKey(String agentId) => 'conv/$agentId/summary';

  /// Replace the oldest excess turns with a single summary placeholder.
  /// The summary content is intentionally minimal — host-supplied LLM
  /// summarization can be added in a later spec revision (FR-FBCORE-AGT-033
  /// allows core-internal policy).
  List<ConversationTurn> _compressOldest(
      List<ConversationTurn> turns, int cap) {
    final excess = turns.length - cap;
    if (excess <= 0) return turns;
    final summary = ConversationTurn(
      userMessage: '<compressed-history>',
      assistantReply:
          '[summary] $excess earlier turns omitted for context length.',
      model: turns.first.model,
      timestamp: turns.first.timestamp,
      extra: const {'compressed': true},
    );
    return [summary, ...turns.sublist(excess)];
  }

  Future<void> _sweepExpired() async {
    if (_closed) return;
    final ttl = _config.conversationTtl;
    if (ttl == Duration.zero) return;
    final keys = await _kv.keys(prefix: 'conv/');
    final now = DateTime.now();
    final expired = <String>{};
    for (final key in keys) {
      if (!key.endsWith('/lastAt')) continue;
      final raw = await _kv.get(key);
      if (raw is! String) continue;
      final lastAt = DateTime.tryParse(raw);
      if (lastAt == null) continue;
      if (now.difference(lastAt) > ttl) {
        // 'conv/<agentId>/lastAt' → '<agentId>'
        final segments = key.split('/');
        if (segments.length >= 3) expired.add(segments[1]);
      }
    }
    for (final agentId in expired) {
      await clear(agentId);
    }
  }
}
