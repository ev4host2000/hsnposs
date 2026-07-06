import 'package:mizapos_mobile/services/cloud/storage/cloud_secure_storage_placeholder.dart';
import 'package:mizapos_mobile/services/cloud/sync/purchase_invoice_draft_payload.dart';
import 'package:mizapos_mobile/services/cloud/sync/purchase_invoice_post_local_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/purchase_invoice_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_invoice_draft_payload.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_invoice_post_local_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_invoice_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/transaction_sync_outbox_writer.dart';
import 'package:mizapos_mobile/services/database_service.dart';
import 'package:sqflite/sqflite.dart';

import 'return_test_seed.dart';

/// Seeds a draft parent invoice locally and enqueues create + post outbox rows.
Future<void> stagePostedPurchaseInvoiceForSync({
  required DatabaseService databaseService,
  required CloudSecureStoragePlaceholder storage,
  required String originalInvoiceId,
  required String parentLineId,
  required String companyId,
  required String branchId,
  required String supplierId,
  required String productId,
  required String userId,
  required String deviceId,
  double total = 50,
}) async {
  final db = await databaseService.database;
  await ReturnTestSeed.seedDraftParentPurchaseInvoice(
    db,
    originalInvoiceId: originalInvoiceId,
    parentLineId: parentLineId,
    companyId: companyId,
    branchId: branchId,
    supplierId: supplierId,
    productId: productId,
    userId: userId,
    total: total,
  );

  await TransactionSyncOutboxWriter.record(
    entityType: PurchaseInvoiceSyncConstants.entityType,
    operation: 'create',
    entityId: originalInvoiceId,
    organizationId: companyId,
    branchId: branchId,
    payload: purchaseInvoiceDraftPushEnvelope(
      aggregateJson: purchaseInvoiceDraftAggregate(
        id: originalInvoiceId,
        organizationId: companyId,
        branchId: branchId,
        createdBy: userId,
        supplierId: supplierId,
        lineSubtotal: total,
        total: total,
        lines: [
          purchaseInvoiceLinePayload(
            lineId: parentLineId,
            productId: productId,
            quantity: 2,
            unitCost: total / 2,
          ),
        ],
        originDeviceId: deviceId,
      ),
      operation: 'create',
      clientRowVersion: 1,
    ),
    databaseService: databaseService,
    storage: storage,
  );

  final postResult = await PurchaseInvoicePostLocalService(
    databaseService: databaseService,
  ).postDraft(invoiceId: originalInvoiceId);
  if (!postResult.ok) {
    throw StateError(
      'stagePostedPurchaseInvoiceForSync post failed: ${postResult.failureCode}',
    );
  }
}

/// Seeds a draft parent sales invoice locally and enqueues create + post outbox rows.
Future<void> stagePostedSalesInvoiceForSync({
  required DatabaseService databaseService,
  required CloudSecureStoragePlaceholder storage,
  required String originalInvoiceId,
  required String parentLineId,
  required String companyId,
  required String branchId,
  required String customerId,
  required String productId,
  required String userId,
  required String deviceId,
  double total = 50,
}) async {
  final db = await databaseService.database;
  await ReturnTestSeed.seedDraftParentSalesInvoice(
    db,
    originalInvoiceId: originalInvoiceId,
    parentLineId: parentLineId,
    companyId: companyId,
    branchId: branchId,
    customerId: customerId,
    productId: productId,
    userId: userId,
    total: total,
  );

  await TransactionSyncOutboxWriter.record(
    entityType: SalesInvoiceSyncConstants.entityType,
    operation: 'create',
    entityId: originalInvoiceId,
    organizationId: companyId,
    branchId: branchId,
    payload: salesInvoiceDraftPushEnvelope(
      aggregateJson: salesInvoiceDraftAggregate(
        id: originalInvoiceId,
        organizationId: companyId,
        branchId: branchId,
        createdBy: userId,
        customerId: customerId,
        lineSubtotal: total,
        total: total,
        lines: [
          salesInvoiceLinePayload(
            lineId: parentLineId,
            productId: productId,
            quantity: 2,
            unitPrice: total / 2,
          ),
        ],
        originDeviceId: deviceId,
      ),
      operation: 'create',
      clientRowVersion: 1,
    ),
    databaseService: databaseService,
    storage: storage,
  );

  final postResult = await SalesInvoicePostLocalService(
    databaseService: databaseService,
  ).postDraft(invoiceId: originalInvoiceId);
  if (!postResult.ok) {
    throw StateError(
      'stagePostedSalesInvoiceForSync post failed: ${postResult.failureCode}',
    );
  }
}
