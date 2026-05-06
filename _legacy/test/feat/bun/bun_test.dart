/// Tests for FEAT-BUN: Bundle installer, rollback journal, section applier.
library;

import 'package:test/test.dart';
import 'package:flowbrain_core/src/feat/bun/bundle_installer.dart';
import 'package:flowbrain_core/src/feat/bun/bundle_source.dart';
import 'package:flowbrain_core/src/feat/bun/rollback_journal.dart';
import 'package:flowbrain_core/src/core/boot/errors.dart';
import 'package:mcp_bundle/mcp_bundle.dart' show McpBundle, BundleManifest;

void main() {
  // ════════════════════════════════════════════════════════════════════════
  // 1. RollbackJournal
  // ════════════════════════════════════════════════════════════════════════

  group('RollbackJournal', () {
    late RollbackJournal journal;

    setUp(() {
      journal = RollbackJournal();
    });

    test('begin creates a pending entry', () {
      final entry = journal.begin('bundle-1');
      expect(entry.bundleId, 'bundle-1');
      expect(entry.status, JournalStatus.pending);
    });

    test('commit sets status to committed', () {
      final entry = journal.begin('bundle-1');
      journal.commit(entry);
      expect(entry.status, JournalStatus.committed);
    });

    test('rollback reverses ops in reverse order and removes entry', () async {
      final order = <String>[];
      final entry = journal.begin('bundle-2');

      entry.ops.add(FunctionRollbackOp(() async => order.add('op1')));
      entry.ops.add(FunctionRollbackOp(() async => order.add('op2')));

      await journal.rollback(entry);

      // Reversed order
      expect(order, ['op2', 'op1']);
      // Entry removed
      expect(journal.lookup('bundle-2'), isNull);
    });

    test('rollback continues on partial failure', () async {
      final entry = journal.begin('bundle-3');
      entry.ops.add(FunctionRollbackOp(() async => throw StateError('fail')));
      entry.ops.add(FunctionRollbackOp(() async {}));

      // Should not throw
      await journal.rollback(entry);
      expect(journal.lookup('bundle-3'), isNull);
    });

    test('listInstalled returns only committed entries', () {
      final e1 = journal.begin('b1');
      journal.commit(e1);
      journal.begin('b2'); // pending, not committed

      final installed = journal.listInstalled();
      expect(installed.length, 1);
      expect(installed.first.id, 'b1');
    });

    test('lookup returns entry by bundleId', () {
      journal.begin('b1');
      expect(journal.lookup('b1'), isNotNull);
      expect(journal.lookup('nonexistent'), isNull);
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // 2. BundleSource
  // ════════════════════════════════════════════════════════════════════════

  group('BundleSource', () {
    test('FileBundleSource holds path', () {
      final source = BundleSource.file('/tmp/bundle.json');
      expect(source, isA<FileBundleSource>());
      expect((source as FileBundleSource).path, '/tmp/bundle.json');
    });

    test('HttpBundleSource holds url', () {
      final source = BundleSource.http('https://example.com/bundle.json');
      expect(source, isA<HttpBundleSource>());
      expect((source as HttpBundleSource).url, 'https://example.com/bundle.json');
    });

    test('MarketplaceBundleSource holds id and version', () {
      final source = BundleSource.marketplace(id: 'my-pack', version: '1.0.0');
      expect(source, isA<MarketplaceBundleSource>());
      final mp = source as MarketplaceBundleSource;
      expect(mp.id, 'my-pack');
      expect(mp.version, '1.0.0');
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // 3. BundleInstaller
  // ════════════════════════════════════════════════════════════════════════

  group('BundleInstaller', () {
    late RollbackJournal journal;
    late _StubBundleLoaderAdapter loader;
    late _StubEventBus eventBus;
    late BundleInstaller installer;

    setUp(() {
      journal = RollbackJournal();
      loader = _StubBundleLoaderAdapter();
      eventBus = _StubEventBus();
      installer = BundleInstaller(
        loader: loader,
        journal: journal,
        eventBus: eventBus,
      );
    });

    test('install success returns result with bundleId', () async {
      loader.bundleToReturn = _createTestBundle('test-bundle', '1.0.0');

      final result = await installer.install(
        BundleSource.file('/fake/path'),
      );
      expect(result.bundleId, 'test-bundle');
      expect(result.status, InstallStatus.success);
      expect(eventBus.emittedCount, greaterThan(0));
    });

    test('install records in journal as committed', () async {
      loader.bundleToReturn = _createTestBundle('test-bundle', '1.0.0');

      await installer.install(BundleSource.file('/fake/path'));
      final entry = journal.lookup('test-bundle');
      expect(entry, isNotNull);
      expect(entry!.status, JournalStatus.committed);
    });

    test('uninstall rolls back and removes entry', () async {
      loader.bundleToReturn = _createTestBundle('test-bundle', '1.0.0');
      await installer.install(BundleSource.file('/fake/path'));

      await installer.uninstall('test-bundle');
      expect(journal.lookup('test-bundle'), isNull);
    });

    test('uninstall unknown bundle throws BundleError', () {
      expect(
        () => installer.uninstall('nonexistent'),
        throwsA(isA<BundleError>()),
      );
    });

    test('list returns installed bundles', () async {
      loader.bundleToReturn = _createTestBundle('b1', '1.0.0');
      await installer.install(BundleSource.file('/fake/b1'));
      loader.bundleToReturn = _createTestBundle('b2', '2.0.0');
      await installer.install(BundleSource.file('/fake/b2'));

      final installed = installer.list();
      expect(installed.length, 2);
    });

    test('integrity failure throws IntegrityError', () async {
      loader.bundleToReturn = _createTestBundle('bad-bundle', '1.0.0');
      loader.failIntegrity = true;
      installer = BundleInstaller(
        loader: loader,
        journal: journal,
        eventBus: eventBus,
        integrityChecker: _FailingIntegrityChecker(),
      );

      expect(
        () => installer.install(BundleSource.file('/fake/path')),
        throwsA(isA<IntegrityError>()),
      );
    });
  });
}

// ── Test helpers ───────────────────────────────────────────────────────────

McpBundle _createTestBundle(String id, String version) {
  return McpBundle(
    manifest: BundleManifest(
      id: id,
      name: id,
      version: version,
    ),
  );
}

/// Stub bundle loader adapter for testing.
class _StubBundleLoaderAdapter implements BundleLoaderAdapter {
  McpBundle? bundleToReturn;
  bool failIntegrity = false;

  @override
  Future<McpBundle> load(BundleSource source) async {
    if (bundleToReturn == null) {
      throw StateError('No bundle configured in stub');
    }
    return bundleToReturn!;
  }
}

/// Stub event bus for testing.
class _StubEventBus implements BundleEventSink {
  int emittedCount = 0;

  @override
  void emitBundleLoaded({
    required String bundleId,
    required String version,
  }) {
    emittedCount++;
  }

  @override
  void emitBundleRolledBack({
    required String bundleId,
    required String reason,
  }) {
    emittedCount++;
  }
}

/// Integrity checker that always fails.
class _FailingIntegrityChecker implements IntegrityChecker {
  @override
  Future<void> verify(McpBundle bundle) async {
    throw const IntegrityError('Hash mismatch');
  }
}
