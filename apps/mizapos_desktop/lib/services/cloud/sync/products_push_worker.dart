import 'package:flutter/foundation.dart';
import 'package:mizapos_desktop/services/cloud/sync/cash_sync_registry.dart';
import 'package:mizapos_desktop/services/cloud/sync/catalog_entity_orchestrator.dart';
import 'package:mizapos_desktop/services/cloud/sync/catalog_sync_registry.dart';
import 'package:mizapos_desktop/services/cloud/sync/expense_sync_registry.dart';
import 'package:mizapos_desktop/services/cloud/sync/models/sync_outbox_row.dart';
import 'package:mizapos_desktop/services/cloud/sync/models/sync_push_event.dart';
import 'package:mizapos_desktop/services/cloud/sync/partners_sync_registry.dart';
import 'package:mizapos_desktop/services/cloud/sync/product_image_cloud_sync.dart';
import 'package:mizapos_desktop/services/cloud/sync/products_sync_repository.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/transaction_orchestrator.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/transaction_registry.dart';
import 'package:mizapos_desktop/services/cloud/sync/requests/products_push_request.dart';
import 'package:mizapos_desktop/services/cloud/sync/responses/products_push_response.dart';
import 'package:mizapos_desktop/services/cloud/sync/sync_push_batch_outcome.dart';
import 'package:mizapos_desktop/services/cloud/sync/sync_push_partial_settler.dart';
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
    ProductImageCloudSync? imageSync,
    CatalogSyncRegistry? catalogRegistry,
    PartnersSyncRegistry? partnersRegistry,
    CashSyncRegistry? cashRegistry,
    ExpenseSyncRegistry? expenseRegistry,
    TransactionRegistry? transactionRegistry,
    Uuid? uuid,
    int imageUploadConcurrency = 3,
  })  : _repository = repository,
        _imageSync = imageSync,
        _catalog = catalogRegistry,
        _partners = partnersRegistry,
        _cash = cashRegistry,
        _expenses = expenseRegistry,
        _transactions = transactionRegistry,
        _uuid = uuid ?? const Uuid(),
        _imageUploadConcurrency =
            imageUploadConcurrency < 1 ? 1 : imageUploadConcurrency;

  final ProductsSyncRepository _repository;
  final ProductImageCloudSync? _imageSync;
  final CatalogSyncRegistry? _catalog;
  final PartnersSyncRegistry? _partners;
  final CashSyncRegistry? _cash;
  final ExpenseSyncRegistry? _expenses;
  final TransactionRegistry? _transactions;
  final Uuid _uuid;
  final int _imageUploadConcurrency;

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
      // استنزاف الشركاء قبل المنتجات/المعاملات — وإلا تفشل الفواتير بـ FK.
      const maxPartnerBatches = 40;
      for (var batch = 0; batch < maxPartnerBatches; batch++) {
        final before = await _repository.countPendingPartners();
        if (before == 0) break;
        final result = await CatalogEntityOrchestrator.runPushWorkers(
          workers: partners.pushWorkers,
          companyId: companyId,
          branchId: branchId,
          deviceId: deviceId,
          batchLimit: batchLimit,
          parallel: false,
        );
        totalPushed += result.pushed;
        totalDuplicates += result.duplicates;
        if (result.lastBatchId.isNotEmpty) lastBatchId = result.lastBatchId;
        final after = await _repository.countPendingPartners();
        if (after >= before && result.pushed == 0 && result.duplicates == 0) {
          break;
        }
      }
    }

    final cash = _cash;
    if (cash != null) {
      final result = await CatalogEntityOrchestrator.runPushWorkers(
        workers: cash.pushWorkers,
        companyId: companyId,
        branchId: branchId,
        deviceId: deviceId,
        batchLimit: batchLimit,
      );
      totalPushed += result.pushed;
      totalDuplicates += result.duplicates;
      if (result.lastBatchId.isNotEmpty) lastBatchId = result.lastBatchId;
    }

    final expenses = _expenses;
    if (expenses != null) {
      final result = await CatalogEntityOrchestrator.runPushWorkers(
        workers: expenses.pushWorkers,
        companyId: companyId,
        branchId: branchId,
        deviceId: deviceId,
        batchLimit: batchLimit,
      );
      totalPushed += result.pushed;
      totalDuplicates += result.duplicates;
      if (result.lastBatchId.isNotEmpty) lastBatchId = result.lastBatchId;
    }

    // استنزاف كل المنتجات المعلّقة قبل أي معاملة — وإلا تفشل الفواتير بـ product_not_found.
    ProductsPushResponse? productsResponse;
    const maxProductBatches = 40;
    for (var batch = 0; batch < maxProductBatches; batch++) {
      final pending = await _repository.fetchPendingProducts(limit: batchLimit);
      if (pending.isEmpty) break;

      final claimedIds = pending.map((e) => e.id).toList();
      var settled = false;
      try {
        final batchId = _uuid.v4();
        final events = await _buildProductPushEvents(pending);
        final request = ProductsPushRequest(
          companyId: companyId,
          branchId: branchId,
          deviceId: deviceId,
          batchId: batchId,
          events: events,
        );

        final response = await _repository.pushRemote(
          request,
          idempotencyKey: batchId,
        );

        if (!response.ok || response.data == null) {
          final data = response.data;
          final code = response.error?.code ?? 'push_failed';
          if (data != null &&
              SyncPushBatchOutcome.canSettleByRejectedEvents(
                claimedCount: claimedIds.length,
                rejectedEventCount: data.rejectedEvents.length,
              )) {
            // Settle then continue: do not throw — pull must still run
            // (version_conflict recovery depends on pull applying cloud state).
            await SyncPushPartialSettler.settle(
              claimedIds: claimedIds,
              rejectedEvents: data.rejectedEvents,
              accepted: data.accepted,
              duplicates: data.duplicates,
              batchId: data.batchId.isNotEmpty ? data.batchId : batchId,
              markFailed: _repository.markOutboxFailed,
              markSynced: _repository.markOutboxSynced,
              releaseClaims: _repository.releaseOutboxClaims,
              operationByOutboxId: {
                for (final row in pending) row.id: row.operation,
              },
            );
            settled = true;
            totalPushed += data.accepted;
            totalDuplicates += data.duplicates;
            lastBatchId =
                data.batchId.isNotEmpty ? data.batchId : batchId;
            if (data.accepted == 0 && data.duplicates == 0) break;
            continue;
          }
          for (final row in pending) {
            await _repository.markOutboxFailed(row.id, code);
          }
          settled = true;
          throw ProductsSyncException(code);
        }

        final data = response.data!;
        productsResponse = data;
        if (SyncPushBatchOutcome.canSettleByRejectedEvents(
              claimedCount: claimedIds.length,
              rejectedEventCount: data.rejectedEvents.length,
            ) &&
            (data.rejected > 0 ||
                SyncPushBatchOutcome.isAmbiguousPartial(
                  pendingCount: pending.length,
                  accepted: data.accepted,
                  duplicates: data.duplicates,
                  rejected: data.rejected,
                ))) {
          // Settle rejected/accepted then continue so SyncEngine can pull.
          await SyncPushPartialSettler.settle(
            claimedIds: claimedIds,
            rejectedEvents: data.rejectedEvents,
            accepted: data.accepted,
            duplicates: data.duplicates,
            batchId: batchId,
            markFailed: _repository.markOutboxFailed,
            markSynced: _repository.markOutboxSynced,
            releaseClaims: _repository.releaseOutboxClaims,
            operationByOutboxId: {
              for (final row in pending) row.id: row.operation,
            },
          );
          settled = true;
          totalPushed += data.accepted;
          totalDuplicates += data.duplicates;
          lastBatchId = batchId;
          if (data.accepted == 0 && data.duplicates == 0) break;
          continue;
        }
        if (SyncPushBatchOutcome.isFullyRejected(
          accepted: data.accepted,
          duplicates: data.duplicates,
          rejected: data.rejected,
        )) {
          for (final row in pending) {
            await _repository.markOutboxFailed(row.id, 'push_rejected');
          }
          settled = true;
          throw ProductsSyncException('push_rejected');
        }
        if (SyncPushBatchOutcome.isAmbiguousPartial(
          pendingCount: pending.length,
          accepted: data.accepted,
          duplicates: data.duplicates,
          rejected: data.rejected,
        )) {
          await _repository.releaseOutboxClaims(claimedIds);
          settled = true;
          throw ProductsSyncException('push_partial');
        }
        if (SyncPushBatchOutcome.canMarkAllSynced(
          pendingCount: pending.length,
          accepted: data.accepted,
          duplicates: data.duplicates,
          rejected: data.rejected,
          status: data.status,
        )) {
          await _repository.markOutboxSynced(
            outboxIds: claimedIds,
            batchId: batchId,
          );
          settled = true;
          final imageSync = _imageSync;
          if (imageSync != null) {
            final createdIds = pending
                .where((row) => row.operation == 'create')
                .map((row) => row.entityId);
            await imageSync.enqueueUpdatesForUnsyncedImages(
              organizationId: companyId,
              branchId: branchId,
              productIds: createdIds,
            );
          }
        } else {
          await _repository.releaseOutboxClaims(claimedIds);
          settled = true;
        }
        totalPushed += data.accepted;
        totalDuplicates += data.duplicates;
        lastBatchId = batchId;

        if (data.accepted == 0 && data.duplicates == 0) break;
      } on Object {
        if (!settled) {
          await _repository.releaseOutboxClaims(claimedIds);
        }
        rethrow;
      }
    }

    // لا نرفع معاملات طالما بقيت منتجات أو شركاء معلّقون.
    final pendingProductsLeft = await _repository.countPendingProducts();
    final pendingPartnersLeft = await _repository.countPendingPartners();
    final transactions = _transactions;
    if (pendingProductsLeft == 0 &&
        pendingPartnersLeft == 0 &&
        transactions != null &&
        !transactions.isEmpty) {
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

    // الصور بعد الفواتير — لا تبطئ الرفع الأساسي.
    final imageSync = _imageSync;
    if (imageSync != null) {
      List<String> imageClaimedIds = const [];
      try {
        await imageSync.flushPendingImageUploads(
          organizationId: companyId,
          branchId: branchId,
        );
        final imagePending =
            await _repository.fetchPendingProducts(limit: batchLimit);
        if (imagePending.isNotEmpty) {
          imageClaimedIds = imagePending.map((e) => e.id).toList();
          final batchId = _uuid.v4();
          final events = await _buildProductPushEvents(imagePending);
          final request = ProductsPushRequest(
            companyId: companyId,
            branchId: branchId,
            deviceId: deviceId,
            batchId: batchId,
            events: events,
          );
          final response = await _repository.pushRemote(
            request,
            idempotencyKey: batchId,
          );
          if (response.ok && response.data != null) {
            final data = response.data!;
            if (SyncPushBatchOutcome.canMarkAllSynced(
              pendingCount: imagePending.length,
              accepted: data.accepted,
              duplicates: data.duplicates,
              rejected: data.rejected,
              status: data.status,
            )) {
              await _repository.markOutboxSynced(
                outboxIds: imageClaimedIds,
                batchId: batchId,
              );
            } else {
              await _repository.releaseOutboxClaims(imageClaimedIds);
            }
            totalPushed += data.accepted;
            totalDuplicates += data.duplicates;
            lastBatchId = batchId;
            productsResponse = data;
          } else {
            await _repository.releaseOutboxClaims(imageClaimedIds);
          }
        }
      } on Object catch (e, st) {
        if (imageClaimedIds.isNotEmpty) {
          await _repository.releaseOutboxClaims(imageClaimedIds);
        }
        if (kDebugMode) {
          debugPrint('ProductsPushWorker: image flush skipped: $e\n$st');
        }
        // فشل رفع الصور لا يوقف نتيجة الدورة.
      }
    }

    return ProductsPushResult(
      pushed: totalPushed,
      duplicates: totalDuplicates,
      batchId: lastBatchId,
      response: productsResponse,
    );
  }

  Future<List<SyncPushEvent>> _buildProductPushEvents(
    List<SyncOutboxRow> pending,
  ) async {
    final imageSync = _imageSync;
    final events = <SyncPushEvent>[];
    for (var i = 0; i < pending.length; i += _imageUploadConcurrency) {
      final chunk = pending.skip(i).take(_imageUploadConcurrency).toList();
      final chunkEvents = await Future.wait(
        chunk.map((row) async {
          var payload = Map<String, dynamic>.from(row.payloadJson);
          if (row.operation != 'delete' &&
              row.operation != 'patch' &&
              imageSync != null) {
            payload = await imageSync.enrichProductPayload(
              productId: row.entityId,
              payload: payload,
              operation: row.operation,
            );
          }
          return SyncPushEvent(
            outboxId: row.id,
            entityType: row.entityType,
            entityId: row.entityId,
            operation: row.operation,
            payloadJson: payload,
            clientRowVersion: row.clientRowVersion,
            idempotencyKey: row.idempotencyKey,
            occurredAt: DateTime.now().toUtc().toIso8601String(),
            changedFields: payload['changed_fields'] is Map
                ? Map<String, dynamic>.from(payload['changed_fields'] as Map)
                : null,
            baseRowVersion: payload['base_row_version'] is int
                ? payload['base_row_version'] as int
                : int.tryParse('${payload['base_row_version'] ?? ''}'),
            operationId: (payload['operation_id'] ?? row.id).toString(),
            dictionaryVersion: payload['dictionary_version']?.toString(),
            contractVersion: payload['contract_version'] is int
                ? payload['contract_version'] as int
                : int.tryParse('${payload['contract_version'] ?? ''}'),
          );
        }),
      );
      events.addAll(chunkEvents);
    }
    return events;
  }
}

class ProductsSyncException implements Exception {
  ProductsSyncException(this.code);

  final String code;

  @override
  String toString() => 'ProductsSyncException($code)';
}
