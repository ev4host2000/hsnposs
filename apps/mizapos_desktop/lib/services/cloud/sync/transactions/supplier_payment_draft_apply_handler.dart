import 'package:mizapos_desktop/services/cloud/sync/posting/apply_handler_posting_bridge.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_transaction_guard.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/supplier_payment/supplier_payment_posting_pipeline.dart';
import 'package:mizapos_desktop/services/cloud/sync/supplier_payment_sync_constants.dart';
import 'package:mizapos_desktop/services/cloud/sync/sync_pull_apply.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/models/transaction_aggregate.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/transaction_apply_handler.dart';
import 'package:sqflite/sqflite.dart';

/// Applies supplier payment draft/post aggregates locally.
class SupplierPaymentDraftApplyHandler extends TransactionApplyHandler
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
    final paymentId = aggregate.header.id;
    final existing = await txn.query(
      'supplierPayments',
      columns: const ['paymentStatus'],
      where: 'id = ?',
      whereArgs: [paymentId],
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
      entityType: SupplierPaymentSyncConstants.entityType,
      pipeline: SupplierPaymentPostingPipeline.create(),
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
    final paymentId = header.id;
    final row = <String, Object?>{
      'id': paymentId,
      'organizationId': header.companyId,
      'branchId': header.branchId,
      'supplierId': _optionalString(extra['supplier_id']),
      'amount': _asDouble(extra['amount']),
      'paymentDate': _optionalString(extra['payment_date']) ??
          DateTime.now().toIso8601String(),
      'paymentMethod': (_optionalString(extra['payment_method']) ?? 'cash'),
      'voucherNumber': _optionalString(extra['voucher_number']),
      'notes': _optionalString(extra['notes']),
      'paymentStatus': 'draft',
      'createdBy': _optionalString(extra['created_by_user_id']) ?? 'sync',
      'transactionVersion': forPostMaterialization &&
              header.status == 'posted' &&
              header.transactionVersion > 0
          ? header.transactionVersion - 1
          : header.transactionVersion,
      'rowVersion': header.rowVersion,
    };

    final existing = await txn.query(
      'supplierPayments',
      where: 'id = ?',
      whereArgs: [paymentId],
      limit: 1,
    );
    if (existing.isEmpty) {
      await txn.insert('supplierPayments', row);
    } else {
      await txn.update(
        'supplierPayments',
        row,
        where: 'id = ?',
        whereArgs: [paymentId],
      );
    }

    return SyncPullApplyOutcome.applied;
  }

  Future<SyncPullApplyOutcome> _deleteDraft(
    TransactionAggregate aggregate,
    DatabaseExecutor txn,
  ) async {
    final paymentId = aggregate.header.id;
    await txn.delete(
      'supplierPayments',
      where: 'id = ?',
      whereArgs: [paymentId],
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
