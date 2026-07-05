import 'package:mizapos_mobile/services/cloud/sync/catalog_entity_orchestrator.dart';
import 'package:mizapos_mobile/services/cloud/sync/catalog_sync_registry.dart';
import 'package:mizapos_mobile/services/cloud/sync/partners_sync_registry.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_sync_repository.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/transaction_orchestrator.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/transaction_registry.dart';
import 'package:mizapos_mobile/services/cloud/sync/requests/products_pull_request.dart';
import 'package:mizapos_mobile/services/cloud/sync/sync_pull_apply.dart';
import 'package:mizapos_mobile/services/cloud/sync/sync_pull_batch_runner.dart';
import 'package:mizapos_mobile/services/cloud/sync/sync_pull_page.dart';

class ProductsPullResult {
  const ProductsPullResult({
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

/// Pulls delta catalog + partners + products and applies locally.
class ProductsPullWorker {
  ProductsPullWorker({
    required ProductsSyncRepository repository,
    CatalogSyncRegistry? catalogRegistry,
    PartnersSyncRegistry? partnersRegistry,
    TransactionRegistry? transactionRegistry,
    SyncPullBatchRunner? batchRunner,
    int pageLimit = 100,
  })  : _repository = repository,
        _catalog = catalogRegistry,
        _partners = partnersRegistry,
        _transactions = transactionRegistry,
        _batchRunner = batchRunner ??
            SyncPullBatchRunner(databaseService: repository.databaseService),
        _pageLimit = pageLimit;

  final ProductsSyncRepository _repository;
  final CatalogSyncRegistry? _catalog;
  final PartnersSyncRegistry? _partners;
  final TransactionRegistry? _transactions;
  final SyncPullBatchRunner _batchRunner;
  final int _pageLimit;

  Future<ProductsPullResult> run({
    required String companyId,
    required String branchId,
    int? limit,
  }) async {
    var totalApplied = 0;
    var totalDeferred = 0;
    var totalEntries = 0;
    var catalogMaxSequence = 0;

    final catalog = _catalog;
    if (catalog != null) {
      final result = await CatalogEntityOrchestrator.runPullWorkers(
        workers: [
          catalog.productCategoriesPull,
          catalog.productUnitsPull,
          catalog.taxesPull,
          catalog.priceListsPull,
        ],
        companyId: companyId,
        branchId: branchId,
        limit: limit,
      );
      totalApplied += result.applied;
      totalDeferred += result.deferred;
      totalEntries += result.entryCount;
      catalogMaxSequence = result.maxSequence;
    }

    final partners = _partners;
    if (partners != null) {
      final result = await CatalogEntityOrchestrator.runPullWorkers(
        workers: partners.pullWorkers,
        companyId: companyId,
        branchId: branchId,
        limit: limit,
      );
      totalApplied += result.applied;
      totalDeferred += result.deferred;
      totalEntries += result.entryCount;
      if (result.maxSequence > catalogMaxSequence) {
        catalogMaxSequence = result.maxSequence;
      }
    }

    final transactions = _transactions;
    if (transactions != null && !transactions.isEmpty) {
      final result = await TransactionOrchestrator.runPullWorkers(
        workers: transactions.pullWorkers,
        companyId: companyId,
        branchId: branchId,
        limit: limit,
      );
      totalApplied += result.applied;
      totalDeferred += result.deferred;
      totalEntries += result.entryCount;
      if (result.maxSequence > catalogMaxSequence) {
        catalogMaxSequence = result.maxSequence;
      }
    }

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
        beforeApply: (txn) => _repository.retryDeferredProducts(
          txn: txn,
          organizationId: companyId,
          branchId: branchId,
        ),
      );

      return ProductsPullResult(
        applied: totalApplied + result.applied,
        deferred: totalDeferred + result.deferred,
        lastSequence: result.lastSequence > catalogMaxSequence
            ? result.lastSequence
            : catalogMaxSequence,
        entryCount: totalEntries + result.entryCount,
      );
    } on SyncPullApplyException catch (e) {
      throw ProductsPullException(e.code);
    }
  }

  Future<SyncPullPage> _fetchPage({
    required String companyId,
    required String branchId,
    required int sinceSequence,
    required int limit,
  }) async {
    final response = await _repository.pullRemote(
      ProductsPullRequest(
        companyId: companyId,
        branchId: branchId,
        sinceSequence: sinceSequence,
        limit: limit,
      ),
    );

    if (!response.ok || response.data == null) {
      final code = response.error?.code ?? 'pull_failed';
      throw ProductsPullException(code);
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

class ProductsPullException implements Exception {
  ProductsPullException(this.code);

  final String code;

  @override
  String toString() => 'ProductsPullException($code)';
}
