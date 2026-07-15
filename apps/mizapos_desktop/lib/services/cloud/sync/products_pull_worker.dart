import 'package:mizapos_desktop/services/cloud/sync/cash_sync_registry.dart';
import 'package:mizapos_desktop/services/cloud/sync/catalog_entity_orchestrator.dart';
import 'package:mizapos_desktop/services/cloud/sync/catalog_sync_registry.dart';
import 'package:mizapos_desktop/services/cloud/sync/expense_sync_registry.dart';
import 'package:mizapos_desktop/services/cloud/sync/partners_sync_registry.dart';
import 'package:mizapos_desktop/services/cloud/sync/products_sync_repository.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/transaction_orchestrator.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/transaction_registry.dart';
import 'package:mizapos_desktop/services/cloud/sync/requests/products_pull_request.dart';
import 'package:mizapos_desktop/services/cloud/sync/sync_pull_apply.dart';
import 'package:mizapos_desktop/services/cloud/sync/sync_pull_batch_runner.dart';
import 'package:mizapos_desktop/services/cloud/sync/sync_pull_page.dart';

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
    CashSyncRegistry? cashRegistry,
    ExpenseSyncRegistry? expenseRegistry,
    TransactionRegistry? transactionRegistry,
    SyncPullBatchRunner? batchRunner,
    int pageLimit = 500,
  })  : _repository = repository,
        _catalog = catalogRegistry,
        _partners = partnersRegistry,
        _cash = cashRegistry,
        _expenses = expenseRegistry,
        _transactions = transactionRegistry,
        _batchRunner = batchRunner ??
            SyncPullBatchRunner(databaseService: repository.databaseService),
        _pageLimit = pageLimit;

  final ProductsSyncRepository _repository;
  final CatalogSyncRegistry? _catalog;
  final PartnersSyncRegistry? _partners;
  final CashSyncRegistry? _cash;
  final ExpenseSyncRegistry? _expenses;
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
        parallel: true,
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
        parallel: true,
      );
      totalApplied += result.applied;
      totalDeferred += result.deferred;
      totalEntries += result.entryCount;
      if (result.maxSequence > catalogMaxSequence) {
        catalogMaxSequence = result.maxSequence;
      }
    }

    // المنتجات قبل المعاملات — وإلا تُؤجَّل الفواتير ثم يُفقد المؤشر.
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
        applyEntry: (entry, txn) => _repository.applyPulledEntry(
          entry,
          txn,
          organizationId: companyId,
          branchId: branchId,
        ),
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
      totalApplied += result.applied;
      totalDeferred += result.deferred;
      totalEntries += result.entryCount;
      if (result.lastSequence > catalogMaxSequence) {
        catalogMaxSequence = result.lastSequence;
      }
    } on SyncPullApplyException catch (e) {
      throw ProductsPullException(e.code);
    }

    final cash = _cash;
    if (cash != null) {
      final result = await CatalogEntityOrchestrator.runPullWorkers(
        workers: cash.pullWorkers,
        companyId: companyId,
        branchId: branchId,
        limit: limit,
        parallel: true,
      );
      totalApplied += result.applied;
      totalDeferred += result.deferred;
      totalEntries += result.entryCount;
      if (result.maxSequence > catalogMaxSequence) {
        catalogMaxSequence = result.maxSequence;
      }
    }

    final expenses = _expenses;
    if (expenses != null) {
      final result = await CatalogEntityOrchestrator.runPullWorkers(
        workers: expenses.pullWorkers,
        companyId: companyId,
        branchId: branchId,
        limit: limit,
        parallel: true,
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
        parallel: true,
      );
      totalApplied += result.applied;
      totalDeferred += result.deferred;
      totalEntries += result.entryCount;
      if (result.maxSequence > catalogMaxSequence) {
        catalogMaxSequence = result.maxSequence;
      }
    }

    return ProductsPullResult(
      applied: totalApplied,
      deferred: totalDeferred,
      lastSequence: catalogMaxSequence,
      entryCount: totalEntries,
    );
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
