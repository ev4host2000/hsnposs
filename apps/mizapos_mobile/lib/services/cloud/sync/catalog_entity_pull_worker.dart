import 'package:mizapos_mobile/services/cloud/sync/catalog_entity_sync_repository.dart';
import 'package:mizapos_mobile/services/cloud/sync/requests/catalog_pull_request.dart';
import 'package:mizapos_mobile/services/cloud/sync/sync_pull_apply.dart';
import 'package:mizapos_mobile/services/cloud/sync/sync_pull_batch_runner.dart';
import 'package:mizapos_mobile/services/cloud/sync/sync_pull_page.dart';

class CatalogEntityPullResult {
  const CatalogEntityPullResult({
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

/// Pull worker for a single catalog entity type.
class CatalogEntityPullWorker {
  CatalogEntityPullWorker({
    required CatalogEntitySyncRepository repository,
    SyncPullBatchRunner? batchRunner,
    int pageLimit = 100,
  })  : _repository = repository,
        _batchRunner = batchRunner ?? SyncPullBatchRunner(
          databaseService: repository.databaseService,
        ),
        _pageLimit = pageLimit;

  final CatalogEntitySyncRepository _repository;
  final SyncPullBatchRunner _batchRunner;
  final int _pageLimit;

  Future<CatalogEntityPullResult> run({
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
        applyEntry: _repository.applyPulledEntry,
        writeSequence: (txn, sequence) => _repository.writeLastPulledSequenceTxn(
          txn,
          organizationId: companyId,
          branchId: branchId,
          sequence: sequence,
        ),
      );

      return CatalogEntityPullResult(
        applied: result.applied,
        deferred: result.deferred,
        lastSequence: result.lastSequence,
        entryCount: result.entryCount,
      );
    } on SyncPullApplyException catch (e) {
      throw CatalogPullException(e.code);
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
      throw CatalogPullException(code);
    }

    final entries = response.data!.entries;
    final lastSequence = readLastSequence(sinceSequence, response.meta);
    return SyncPullPage(
      entries: entries,
      lastSequence: lastSequence,
      hasMore: readHasMore(response.meta),
    );
  }
}

class CatalogPullException implements Exception {
  CatalogPullException(this.code);

  final String code;

  @override
  String toString() => 'CatalogPullException($code)';
}
