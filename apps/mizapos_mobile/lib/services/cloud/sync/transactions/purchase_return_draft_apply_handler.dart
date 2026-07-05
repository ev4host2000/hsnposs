import 'package:mizapos_mobile/services/cloud/sync/posting/apply_handler_posting_bridge.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/posting_transaction_guard.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/purchase_return/purchase_return_posting_pipeline.dart';
import 'package:mizapos_mobile/services/cloud/sync/purchase_return_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/sync_pull_apply.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/models/transaction_aggregate.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/transaction_apply_handler.dart';
import 'package:sqflite/sqflite.dart';

/// Applies purchase return draft/post aggregates locally.
class PurchaseReturnDraftApplyHandler extends TransactionApplyHandler
    with TransactionApplyHandlerPostingAccess {
  @override
  Future<SyncPullApplyOutcome> applyCreate(
    TransactionAggregate aggregate,
    DatabaseExecutor txn,
  ) {
    return _upsertDraft(aggregate, txn);
  }

  @override
  Future<SyncPullApplyOutcome> applyUpdate(
    TransactionAggregate aggregate,
    DatabaseExecutor txn,
  ) {
    return _upsertDraft(aggregate, txn);
  }

  @override
  Future<SyncPullApplyOutcome> applyPost(
    TransactionAggregate aggregate,
    DatabaseExecutor txn,
  ) async {
    final returnId = aggregate.header.id;
    final existing = await txn.query(
      'purchaseReturns',
      columns: const ['returnStatus'],
      where: 'id = ?',
      whereArgs: [returnId],
      limit: 1,
    );
    if (existing.isEmpty) {
      final materialized = await _upsertDraft(
        aggregate,
        txn,
        forPostMaterialization: true,
      );
      if (materialized != SyncPullApplyOutcome.applied) {
        return materialized;
      }
    }

    final result = await runPostingPipeline(
      aggregate: aggregate,
      txn: txn,
      entityType: PurchaseReturnSyncConstants.entityType,
      pipeline: PurchaseReturnPostingPipeline.create(),
    );
    abortPostingTransactionIfFailed(result);
    return SyncPullApplyOutcome.applied;
  }

  @override
  Future<SyncPullApplyOutcome> applyCancel(
    TransactionAggregate aggregate,
    DatabaseExecutor txn,
  ) {
    return _deleteDraft(aggregate, txn);
  }

  Future<SyncPullApplyOutcome> _upsertDraft(
    TransactionAggregate aggregate,
    DatabaseExecutor txn, {
    bool forPostMaterialization = false,
  }) async {
    final header = aggregate.header;
    if (!forPostMaterialization && header.status != 'draft') {
      return SyncPullApplyOutcome.failed;
    }

    final dependency = await _ensureDependencies(aggregate, txn);
    if (dependency != SyncPullApplyOutcome.applied) {
      return dependency;
    }

    final extra = header is MapTransactionHeader ? header.extra : const {};
    final returnId = header.id;
    final row = <String, Object?>{
      'id': returnId,
      'organizationId': header.companyId,
      'branchId': header.branchId,
      'originalInvoiceId': _optionalString(extra['original_invoice_id']),
      'supplierId': _optionalString(extra['supplier_id']),
      'returnDate': _optionalString(extra['return_date']) ??
          DateTime.now().toIso8601String(),
      'total': _asDouble(extra['total']),
      'refundPaymentType':
          (_optionalString(extra['refund_payment_type']) ?? 'cash'),
      'returnStatus': 'draft',
      'createdBy': _optionalString(extra['created_by_user_id']) ?? 'sync',
      'notes': _optionalString(extra['notes']),
      'discountAmount': _asDouble(extra['discount_amount']),
      'taxPercent': _asDouble(extra['tax_percent']),
      'lineSubtotal': _asDouble(extra['line_subtotal']),
      'paidAmount': _asDouble(extra['paid_amount']),
      'transactionVersion': forPostMaterialization &&
              header.status == 'posted' &&
              header.transactionVersion > 0
          ? header.transactionVersion - 1
          : header.transactionVersion,
      'rowVersion': header.rowVersion,
    };

    final existing = await txn.query(
      'purchaseReturns',
      where: 'id = ?',
      whereArgs: [returnId],
      limit: 1,
    );
    if (existing.isEmpty) {
      await txn.insert('purchaseReturns', row);
    } else {
      await txn.update(
        'purchaseReturns',
        row,
        where: 'id = ?',
        whereArgs: [returnId],
      );
    }

    await txn.delete(
      'purchaseReturnItems',
      where: 'returnId = ?',
      whereArgs: [returnId],
    );

    for (final line in aggregate.lines) {
      final fields = line is MapTransactionLine ? line.fields : const {};
      final lineId = line.lineId.isNotEmpty
          ? line.lineId
          : (fields['id'] ?? fields['line_id'] ?? '').toString();
      if (lineId.isEmpty) continue;

      final quantity = _asDouble(fields['quantity']);
      final unitCost = fields.containsKey('unit_cost')
          ? _asDouble(fields['unit_cost'])
          : _asDouble(fields['unit_price']);
      final lineTotal =
          _asDouble(fields['line_total'], fallback: quantity * unitCost);

      await txn.insert('purchaseReturnItems', {
        'id': lineId,
        'returnId': returnId,
        'productId': (fields['product_id'] ?? '').toString(),
        'quantity': quantity,
        'unitCost': unitCost,
        'lineTotal': lineTotal,
      });
    }

    return SyncPullApplyOutcome.applied;
  }

  Future<SyncPullApplyOutcome> _deleteDraft(
    TransactionAggregate aggregate,
    DatabaseExecutor txn,
  ) async {
    final returnId = aggregate.header.id;
    await txn.delete(
      'purchaseReturnItems',
      where: 'returnId = ?',
      whereArgs: [returnId],
    );
    await txn.delete(
      'purchaseReturns',
      where: 'id = ?',
      whereArgs: [returnId],
    );
    return SyncPullApplyOutcome.applied;
  }

  Future<SyncPullApplyOutcome> _ensureDependencies(
    TransactionAggregate aggregate,
    DatabaseExecutor txn,
  ) async {
    final extra = aggregate.header is MapTransactionHeader
        ? (aggregate.header as MapTransactionHeader).extra
        : const {};
    final originalInvoiceId = _optionalString(extra['original_invoice_id']);
    if (originalInvoiceId != null) {
      final rows = await txn.query(
        'purchaseInvoices',
        columns: const ['id', 'invoiceStatus'],
        where: 'id = ?',
        whereArgs: [originalInvoiceId],
        limit: 1,
      );
      if (rows.isEmpty || (rows.first['invoiceStatus'] ?? '').toString() != 'posted') {
        return SyncPullApplyOutcome.deferred;
      }
    }

    final supplierId = _optionalString(extra['supplier_id']);
    if (supplierId != null) {
      final rows = await txn.query(
        'suppliers',
        columns: const ['id'],
        where: 'id = ?',
        whereArgs: [supplierId],
        limit: 1,
      );
      if (rows.isEmpty) {
        return SyncPullApplyOutcome.deferred;
      }
    }

    for (final line in aggregate.lines) {
      final fields = line is MapTransactionLine ? line.fields : const {};
      final productId = (fields['product_id'] ?? '').toString();
      if (productId.isEmpty) continue;
      final rows = await txn.query(
        'products',
        columns: const ['id'],
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      if (rows.isEmpty) {
        return SyncPullApplyOutcome.deferred;
      }
    }

    return SyncPullApplyOutcome.applied;
  }

  String? _optionalString(Object? value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }

  double _asDouble(Object? value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }
}
