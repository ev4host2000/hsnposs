import 'package:mizapos_desktop/services/cloud/sync/requests/catalog_pull_request.dart';
import 'package:mizapos_desktop/services/cloud/sync/sync_deferred_pull_store.dart';
import 'package:mizapos_desktop/services/cloud/sync/sync_pull_apply.dart';
import 'package:mizapos_desktop/services/cloud/sync/sync_pull_batch_runner.dart';
import 'package:mizapos_desktop/services/cloud/sync/sync_pull_page.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/transaction_sync_exception.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/transaction_sync_repository.dart';
import 'package:sqflite/sqflite.dart';

class TransactionPullResult {
  const TransactionPullResult({
    required this.applied,
    required this.deferred,
    required this.lastSequence,
    required this.entryCount,
  });

  final int applied;
  final int deferred;
  final int lastSequence;
  final int entryCount;
}

/// Pull worker for one registered transaction document type.
class TransactionPullWorker {
  TransactionPullWorker({
    required TransactionSyncRepository repository,
    SyncPullBatchRunner? batchRunner,
    SyncDeferredPullStore? deferredPullStore,
    int pageLimit = 100,
  })  : _repository = repository,
        _batchRunner = batchRunner ??
            SyncPullBatchRunner(
              databaseService: repository.databaseService,
            ),
        _deferredStore = deferredPullStore ?? SyncDeferredPullStore(),
        _pageLimit = pageLimit;

  final TransactionSyncRepository _repository;
  final SyncPullBatchRunner _batchRunner;
  final SyncDeferredPullStore _deferredStore;
  final int _pageLimit;

  TransactionSyncRepository get repository => _repository;

  Future<TransactionPullResult> run({
    required String companyId,
    required String branchId,
    int? limit,
  }) async {
    final sinceSequence = await _repository.readLastPulledSequence(
      organizationId: companyId,
      branchId: branchId,
    );

    try {
      final result = await _batchRunner.run(
        sinceSequence: sinceSequence,
        fetchPage: (cursor) => _fetchPage(
          companyId: companyId,
          branchId: branchId,
          sinceSequence: cursor,
          limit: limit ?? _pageLimit,
        ),
        applyEntry: (entry, txn) async {
          final outcome = await _repository.applyPulledEntry(entry, txn);
          if (outcome == SyncPullApplyOutcome.deferred) {
            await _deferredStore.upsert(
              txn: txn,
              organizationId: companyId,
              branchId: branchId,
              scopeKey: _repository.scopeKey,
              entry: entry,
              reason: SyncDeferredPullStore.reasonAwaitingDependency,
            );
          } else if (outcome == SyncPullApplyOutcome.applied) {
            await _deferredStore.remove(txn: txn, entityId: entry.entityId);
          }
          return outcome;
        },
        writeSequence: (txn, sequence) => _repository.writeLastPulledSequenceTxn(
          txn,
          organizationId: companyId,
          branchId: branchId,
          sequence: sequence,
        ),
        beforeApply: (txn) => _retryDeferred(
          txn: txn,
          companyId: companyId,
          branchId: branchId,
        ),
      );

      return TransactionPullResult(
        applied: result.applied,
        deferred: result.deferred,
        lastSequence: result.lastSequence,
        entryCount: result.entryCount,
      );
    } on SyncPullApplyException catch (e) {
      throw TransactionSyncException(e.code);
    }
  }

  Future<SyncPullPage> _fetchPage({
    required String companyId,
    required String branchId,
    required int sinceSequence,
    required int limit,
  }) async {
    final response = await _repository.pullRemote(
      CatalogPullRequest(
        companyId: companyId,
        branchId: branchId,
        sinceSequence: sinceSequence,
        limit: limit,
      ),
    );

    if (!response.ok || response.data == null) {
      final code = response.error?.code ?? 'pull_failed';
      throw TransactionSyncException(code);
    }

    final entries = response.data!.entries;
    final lastSequence = readLastSequence(sinceSequence, response.meta);
    return SyncPullPage(
      entries: entries,
      lastSequence: lastSequence,
      hasMore: readHasMore(response.meta),
    );
  }

  Future<void> _retryDeferred({
    required DatabaseExecutor txn,
    required String companyId,
    required String branchId,
  }) async {
    final deferred = await _deferredStore.listForScope(
      txn: txn,
      organizationId: companyId,
      branchId: branchId,
      scopeKey: _repository.scopeKey,
    );
    for (final entry in deferred) {
      final outcome = await _repository.applyPulledEntry(entry, txn);
      if (outcome == SyncPullApplyOutcome.applied) {
        await _deferredStore.remove(txn: txn, entityId: entry.entityId);
      }
    }
  }
}
