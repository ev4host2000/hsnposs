import 'package:mizapos_desktop/services/cloud/sync/posting/apply_handler_posting_bridge.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_transaction_guard.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/opening_stock/opening_stock_posting_pipeline.dart';
import 'package:mizapos_desktop/services/cloud/sync/opening_stock_sync_constants.dart';
import 'package:mizapos_desktop/services/cloud/sync/sync_pull_apply.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/models/transaction_aggregate.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/transaction_apply_handler.dart';
import 'package:sqflite/sqflite.dart';

/// Applies opening stock draft/post aggregates locally.
class OpeningStockDraftApplyHandler extends TransactionApplyHandler
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
    final openingStockId = aggregate.header.id;
    final existing = await txn.query(
      'openingStocks',
      columns: const ['openingStatus'],
      where: 'id = ?',
      whereArgs: [openingStockId],
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
      entityType: OpeningStockSyncConstants.entityType,
      pipeline: OpeningStockPostingPipeline.create(),
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
    final openingStockId = header.id;
    final row = <String, Object?>{
      'id': openingStockId,
      'organizationId': header.companyId,
      'branchId': header.branchId,
      'productId': _optionalString(extra['product_id']),
      'openingQuantity': _asDouble(extra['opening_quantity']),
      'openingDate': _optionalString(extra['opening_date']) ??
          DateTime.now().toIso8601String(),
      'notes': _optionalString(extra['notes']),
      'openingStatus': 'draft',
      'createdBy': _optionalString(extra['created_by_user_id']) ?? 'sync',
      'transactionVersion': forPostMaterialization &&
              header.status == 'posted' &&
              header.transactionVersion > 0
          ? header.transactionVersion - 1
          : header.transactionVersion,
      'rowVersion': header.rowVersion,
    };

    final existing = await txn.query(
      'openingStocks',
      where: 'id = ?',
      whereArgs: [openingStockId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final localStatus =
          (existing.first['openingStatus'] ?? '').toString();
      if (!forPostMaterialization &&
          (localStatus == 'posted' ||
              localStatus == 'voided' ||
              localStatus == 'void')) {
        return SyncPullApplyOutcome.applied;
      }
    }
    if (existing.isEmpty) {
      await txn.insert('openingStocks', row);
    } else {
      await txn.update(
        'openingStocks',
        row,
        where: 'id = ?',
        whereArgs: [openingStockId],
      );
    }

    return SyncPullApplyOutcome.applied;
  }

  Future<SyncPullApplyOutcome> _deleteDraft(
    TransactionAggregate aggregate,
    DatabaseExecutor txn,
  ) async {
    final openingStockId = aggregate.header.id;
    await txn.delete(
      'openingStocks',
      where: 'id = ?',
      whereArgs: [openingStockId],
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

    final productId = _optionalString(extra['product_id']);
    if (productId != null) {
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
