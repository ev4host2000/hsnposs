import 'package:mizapos_mobile/services/cloud/sync/catalog_entity_orchestrator.dart';
import 'package:mizapos_mobile/services/cloud/sync/catalog_sync_registry.dart';
import 'package:mizapos_mobile/services/cloud/sync/partners_sync_registry.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_sync_repository.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/transaction_orchestrator.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/transaction_registry.dart';
import 'package:mizapos_mobile/services/cloud/sync/requests/products_push_request.dart';
import 'package:mizapos_mobile/services/cloud/sync/responses/products_push_response.dart';
import 'package:uuid/uuid.dart';

class ProductsPushResult {
  const ProductsPushResult({
    required this.pushed,
    required this.duplicates,
    required this.batchId,
    this.response,
  });

  final int pushed;
  final int duplicates;
  final String batchId;
  final ProductsPushResponse? response;
}

/// يرفع أحداث `sync_outbox` (catalog + partners + products) إلى Miza Cloud.
class ProductsPushWorker {
  ProductsPushWorker({
    required ProductsSyncRepository repository,
    CatalogSyncRegistry? catalogRegistry,
    PartnersSyncRegistry? partnersRegistry,
    TransactionRegistry? transactionRegistry,
    Uuid? uuid,
  })  : _repository = repository,
        _catalog = catalogRegistry,
        _partners = partnersRegistry,
        _transactions = transactionRegistry,
        _uuid = uuid ?? const Uuid();

  final ProductsSyncRepository _repository;
  final CatalogSyncRegistry? _catalog;
  final PartnersSyncRegistry? _partners;
  final TransactionRegistry? _transactions;
  final Uuid _uuid;

  Future<ProductsPushResult> run({
    required String companyId,
    required String branchId,
    required String deviceId,
    int batchLimit = 50,
  }) async {
    var totalPushed = 0;
    var totalDuplicates = 0;
    var lastBatchId = '';

    final catalog = _catalog;
    if (catalog != null) {
      final result = await CatalogEntityOrchestrator.runPushWorkers(
        workers: [
          catalog.productCategoriesPush,
          catalog.productUnitsPush,
          catalog.taxesPush,
          catalog.priceListsPush,
        ],
        companyId: companyId,
        branchId: branchId,
        deviceId: deviceId,
        batchLimit: batchLimit,
      );
      totalPushed += result.pushed;
      totalDuplicates += result.duplicates;
      lastBatchId = result.lastBatchId;
    }

    final partners = _partners;
    if (partners != null) {
      final result = await CatalogEntityOrchestrator.runPushWorkers(
        workers: partners.pushWorkers,
        companyId: companyId,
        branchId: branchId,
        deviceId: deviceId,
        batchLimit: batchLimit,
      );
      totalPushed += result.pushed;
      totalDuplicates += result.duplicates;
      if (result.lastBatchId.isNotEmpty) lastBatchId = result.lastBatchId;
    }

    final transactions = _transactions;
    if (transactions != null && !transactions.isEmpty) {
      final result = await TransactionOrchestrator.runPushWorkers(
        workers: transactions.pushWorkers,
        companyId: companyId,
        branchId: branchId,
        deviceId: deviceId,
        batchLimit: batchLimit,
      );
      totalPushed += result.pushed;
      totalDuplicates += result.duplicates;
      if (result.lastBatchId.isNotEmpty) lastBatchId = result.lastBatchId;
    }

    final pending = await _repository.fetchPendingProducts(limit: batchLimit);
    if (pending.isEmpty) {
      return ProductsPushResult(
        pushed: totalPushed,
        duplicates: totalDuplicates,
        batchId: lastBatchId,
      );
    }

    final batchId = _uuid.v4();
    final request = ProductsPushRequest(
      companyId: companyId,
      branchId: branchId,
      deviceId: deviceId,
      batchId: batchId,
      events: pending.map((row) => row.toPushEvent()).toList(),
    );

    final response = await _repository.pushRemote(
      request,
      idempotencyKey: batchId,
    );

    if (!response.ok || response.data == null) {
      final code = response.error?.code ?? 'push_failed';
      for (final row in pending) {
        await _repository.markOutboxFailed(row.id, code);
      }
      throw ProductsSyncException(code);
    }

    final data = response.data!;
    if (data.accepted > 0 ||
        data.duplicates > 0 ||
        data.status == 'duplicate') {
      await _repository.markOutboxSynced(
        outboxIds: pending.map((e) => e.id).toList(),
        batchId: batchId,
      );
    }

    return ProductsPushResult(
      pushed: totalPushed + data.accepted,
      duplicates: totalDuplicates + data.duplicates,
      batchId: batchId,
      response: data,
    );
  }
}

class ProductsSyncException implements Exception {
  ProductsSyncException(this.code);

  final String code;

  @override
  String toString() => 'ProductsSyncException($code)';
}
