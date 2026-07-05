import 'package:mizapos_mobile/services/cloud/sync/models/sync_changelog_entry.dart';
import 'package:mizapos_mobile/services/cloud/sync/sync_pull_apply.dart';
import 'package:mizapos_mobile/services/cloud/sync/sync_pull_page.dart';
import 'package:mizapos_mobile/services/database_service.dart';
import 'package:sqflite/sqflite.dart';

typedef SyncPullPageFetcher = Future<SyncPullPage> Function(int sinceSequence);

typedef SyncPullEntryApplier = Future<SyncPullApplyOutcome> Function(
  SyncChangelogEntry entry,
  DatabaseExecutor txn,
);

typedef SyncPullBeforeApply = Future<void> Function(DatabaseExecutor txn);

typedef SyncPullWriteSequence = Future<void> Function(
  DatabaseExecutor txn,
  int sequence,
);

class SyncPullBatchResult {
  const SyncPullBatchResult({
    required this.applied,
    required this.deferred,
    required this.entryCount,
    required this.lastSequence,
  });

  final int applied;
  final int deferred;
  final int entryCount;
  final int lastSequence;
}

/// Fetches all pull pages then applies them in one SQLite transaction.
class SyncPullBatchRunner {
  SyncPullBatchRunner({DatabaseService? databaseService})
      : _db = databaseService ?? DatabaseService();

  final DatabaseService _db;

  Future<SyncPullBatchResult> run({
    required int sinceSequence,
    required SyncPullPageFetcher fetchPage,
    required SyncPullEntryApplier applyEntry,
    required SyncPullWriteSequence writeSequence,
    SyncPullBeforeApply? beforeApply,
  }) async {
    final pages = <SyncPullPage>[];
    var cursor = sinceSequence;
    while (true) {
      final page = await fetchPage(cursor);
      pages.add(page);
      if (!page.hasMore) break;
      if (page.lastSequence <= cursor) {
        throw SyncPullApplyException('pull_paging_stalled');
      }
      cursor = page.lastSequence;
    }

    final allEntries = pages.expand((page) => page.entries).toList();
    final finalSequence = pages.isEmpty
        ? sinceSequence
        : pages.map((p) => p.lastSequence).reduce((a, b) => a > b ? a : b);

    var applied = 0;
    var deferred = 0;

    try {
      final db = await _db.database;
      await db.transaction((txn) async {
        if (beforeApply != null) {
          await beforeApply(txn);
        }

        for (final entry in allEntries) {
          final outcome = await applyEntry(entry, txn);
          switch (outcome) {
            case SyncPullApplyOutcome.applied:
              applied++;
            case SyncPullApplyOutcome.deferred:
              deferred++;
            case SyncPullApplyOutcome.failed:
              throw SyncPullApplyException('apply_failed', entry: entry);
          }
        }

        if (finalSequence > sinceSequence) {
          await writeSequence(txn, finalSequence);
        }
      });
    } on SyncPullApplyException {
      rethrow;
    }

    return SyncPullBatchResult(
      applied: applied,
      deferred: deferred,
      entryCount: allEntries.length,
      lastSequence: finalSequence,
    );
  }
}
