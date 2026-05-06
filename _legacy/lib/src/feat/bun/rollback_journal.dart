/// Rollback journal for FEAT-BUN.
///
/// Provides atomic bundle installation with rollback capability.
/// Each bundle install records reverse operations that can undo the
/// changes if the install fails partway through.
library;

import 'package:logging/logging.dart';

final _log = Logger('RollbackJournal');

// ── Journal status ───────────────────────────────────────────────────────

/// Lifecycle status of a journal entry.
enum JournalStatus {
  /// Installation in progress, not yet committed.
  pending,

  /// Installation completed successfully.
  committed,
}

// ── Rollback operation ───────────────────────────────────────────────────

/// Abstract reverse operation recorded during bundle installation.
abstract class RollbackOp {
  /// Execute the reverse operation to undo a change.
  Future<void> reverse();
}

/// Convenience [RollbackOp] backed by a function.
class FunctionRollbackOp extends RollbackOp {
  final Future<void> Function() _fn;

  FunctionRollbackOp(this._fn);

  @override
  Future<void> reverse() => _fn();
}

// ── Rollback entry ───────────────────────────────────────────────────────

/// Journal entry for a single bundle installation.
class RollbackEntry {
  /// Bundle identifier this entry belongs to.
  final String bundleId;

  /// Ordered list of reverse operations. Executed in reverse order
  /// during rollback.
  final List<RollbackOp> ops;

  /// Current lifecycle status.
  JournalStatus status;

  /// Timestamp when the entry was created.
  final DateTime createdAt;

  RollbackEntry({
    required this.bundleId,
    List<RollbackOp>? ops,
    this.status = JournalStatus.pending,
    DateTime? createdAt,
  })  : ops = ops ?? [],
        createdAt = createdAt ?? DateTime.now();
}

// ── Installed bundle info ────────────────────────────────────────────────

/// Summary of an installed bundle for listing.
class InstalledBundle {
  /// Bundle identifier.
  final String id;

  /// Installation timestamp.
  final DateTime installedAt;

  const InstalledBundle({
    required this.id,
    required this.installedAt,
  });
}

// ── Journal ──────────────────────────────────────────────────────────────

/// Manages rollback entries for bundle installations.
///
/// Each [begin] call creates a [RollbackEntry]. During installation,
/// reverse operations are appended to the entry. On success, [commit]
/// marks it as committed. On failure, [rollback] executes all reverse
/// ops in reverse order.
class RollbackJournal {
  final Map<String, RollbackEntry> _entries = {};

  /// Start a new journal entry for [bundleId].
  RollbackEntry begin(String bundleId) {
    final entry = RollbackEntry(bundleId: bundleId);
    _entries[bundleId] = entry;
    return entry;
  }

  /// Mark an entry as successfully committed.
  void commit(RollbackEntry entry) {
    entry.status = JournalStatus.committed;
  }

  /// Execute all reverse operations in reverse order and remove the entry.
  ///
  /// Individual op failures are logged but do not stop the rollback —
  /// partial rollback is better than a stuck state.
  Future<void> rollback(RollbackEntry entry) async {
    for (final op in entry.ops.reversed) {
      try {
        await op.reverse();
      } catch (e) {
        _log.warning(
          'Rollback op failed for bundle=${entry.bundleId}: $e',
        );
      }
    }
    _entries.remove(entry.bundleId);
  }

  /// Look up an entry by [bundleId].
  RollbackEntry? lookup(String bundleId) => _entries[bundleId];

  /// List all bundles that have been successfully installed (committed).
  List<InstalledBundle> listInstalled() => _entries.values
      .where((e) => e.status == JournalStatus.committed)
      .map((e) => InstalledBundle(id: e.bundleId, installedAt: e.createdAt))
      .toList();
}
