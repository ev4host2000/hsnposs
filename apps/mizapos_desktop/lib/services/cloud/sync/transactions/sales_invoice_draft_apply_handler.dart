import 'package:mizapos_desktop/services/cloud/sync/posting/apply_handler_posting_bridge.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_transaction_guard.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/sales_invoice/sales_invoice_posting_pipeline.dart';
import 'package:mizapos_desktop/services/cloud/sync/sales_invoice_sync_constants.dart';
import 'package:mizapos_desktop/services/cloud/sync/sync_pull_apply.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/models/transaction_aggregate.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/transaction_apply_handler.dart';
import 'package:sqflite/sqflite.dart';

/// Applies sales invoice draft/post aggregates locally.
class SalesInvoiceDraftApplyHandler extends TransactionApplyHandler
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
    final invoiceId = aggregate.header.id;
    final existing = await txn.query(
      'salesInvoices',
      columns: const ['invoiceStatus'],
      where: 'id = ?',
      whereArgs: [invoiceId],
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
      entityType: SalesInvoiceSyncConstants.entityType,
      pipeline: SalesInvoicePostingPipeline.create(),
    );
    abortPostingTransactionIfFailed(result);
    return SyncPullApplyOutcome.applied;
  }

  @override
  Future<SyncPullApplyOutcome> applyCancel(
    TransactionAggregate aggregate,
    DatabaseExecutor txn,
  ) {
    final status = aggregate.header.status;
    if (status == 'void' || status == 'voided') {
      return applyVoid(aggregate, txn);
    }
    return _deleteDraft(aggregate, txn);
  }

  @override
  Future<SyncPullApplyOutcome> applyVoid(
    TransactionAggregate aggregate,
    DatabaseExecutor txn,
  ) async {
    final invoiceId = aggregate.header.id;
    final existing = await txn.query(
      'salesInvoices',
      columns: const ['invoiceStatus'],
      where: 'id = ?',
      whereArgs: [invoiceId],
      limit: 1,
    );
    if (existing.isEmpty) {
      // Materialize as voided without running post first.
      final created = await _upsertDraft(
        aggregate,
        txn,
        forPostMaterialization: true,
      );
      if (created != SyncPullApplyOutcome.applied) {
        return created;
      }
    } else {
      final status = (existing.first['invoiceStatus'] ?? '').toString();
      if (status == 'voided' || status == 'void') {
        // Still apply void cash if present (idempotent by cash id).
        await _applyVoidCashSection(aggregate, txn);
        return SyncPullApplyOutcome.applied;
      }
    }

    final header = aggregate.header;
    final extra = header is MapTransactionHeader ? header.extra : const {};
    final when = DateTime.now().toIso8601String();
    final createdBy =
        _optionalString(extra['created_by_user_id']) ?? 'sync';

    // Apply reverse inventory if present.
    List<dynamic> inventory = const [];
    if (aggregate is MapTransactionAggregate) {
      final json = aggregate.toJson();
      if (json['inventory'] is List) {
        inventory = json['inventory'] as List;
      } else if (aggregate.metadata is MapTransactionMetadata) {
        final extraMeta = (aggregate.metadata as MapTransactionMetadata).extra;
        if (extraMeta['inventory'] is List) {
          inventory = extraMeta['inventory'] as List;
        }
      }
    }
    for (final raw in inventory) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final movementId = (m['movement_id'] ?? m['id'] ?? '').toString();
      final productId = (m['product_id'] ?? '').toString();
      final qty = _asDouble(m['quantity']);
      if (movementId.isEmpty || productId.isEmpty || qty <= 0) continue;
      final exists = await txn.query(
        'stockMovements',
        columns: const ['id'],
        where: 'id = ?',
        whereArgs: [movementId],
        limit: 1,
      );
      if (exists.isNotEmpty) continue;
      await txn.rawUpdate(
        'UPDATE products SET stockQty = stockQty + ? WHERE id = ?',
        [qty, productId],
      );
      await txn.insert('stockMovements', {
        'id': movementId,
        'organizationId': header.companyId,
        'branchId': header.branchId,
        'productId': productId,
        'movementType': 'in',
        'quantity': qty,
        'referenceType': (m['reference_type'] ?? 'sale_void').toString(),
        'referenceId': invoiceId,
        'movementDate':
            (m['movement_date'] ?? when).toString(),
        'createdBy': createdBy,
      });
    }

    List<dynamic> accounting = const [];
    if (aggregate is MapTransactionAggregate) {
      final json = aggregate.toJson();
      if (json['accounting'] is List) {
        accounting = json['accounting'] as List;
      } else if (aggregate.metadata is MapTransactionMetadata) {
        final extraMeta = (aggregate.metadata as MapTransactionMetadata).extra;
        if (extraMeta['accounting'] is List) {
          accounting = extraMeta['accounting'] as List;
        }
      }
    }
    for (final raw in accounting) {
      if (raw is! Map) continue;
      final e = Map<String, dynamic>.from(raw);
      final entryId = (e['entry_id'] ?? e['id'] ?? '').toString();
      final partnerId = (e['partner_id'] ?? '').toString();
      if (entryId.isEmpty || partnerId.isEmpty) continue;
      final exists = await txn.query(
        'partnerLedger',
        columns: const ['id'],
        where: 'id = ?',
        whereArgs: [entryId],
        limit: 1,
      );
      if (exists.isNotEmpty) continue;
      await txn.insert('partnerLedger', {
        'id': entryId,
        'organizationId': header.companyId,
        'branchId': header.branchId,
        'partnerKind': (e['partner_kind'] ?? 'customer').toString(),
        'partnerId': partnerId,
        'entryType': (e['entry_type'] ?? 'sale_void').toString(),
        'referenceType': (e['reference_type'] ?? 'sale').toString(),
        'referenceId': invoiceId,
        'amountSigned': _asDouble(e['amount_signed']),
        'entryDate': (e['entry_date'] ?? when).toString(),
        'createdBy': createdBy,
        'notes': e['notes']?.toString(),
      });
    }

    await _applyVoidCashSection(
      aggregate,
      txn,
      fallbackCreatedBy: createdBy,
      fallbackWhen: when,
    );

    await txn.update(
      'salesInvoices',
      {
        'invoiceStatus': 'voided',
        'transactionVersion': header.transactionVersion,
        'rowVersion': header.rowVersion,
      },
      where: 'id = ?',
      whereArgs: [invoiceId],
    );
    return SyncPullApplyOutcome.applied;
  }

  Future<void> _applyVoidCashSection(
    TransactionAggregate aggregate,
    DatabaseExecutor txn, {
    String? fallbackCreatedBy,
    String? fallbackWhen,
  }) async {
    final header = aggregate.header;
    final invoiceId = header.id;
    final when = fallbackWhen ?? DateTime.now().toIso8601String();
    final createdBy = fallbackCreatedBy ??
        ((header is MapTransactionHeader)
            ? (_optionalString(header.extra['created_by_user_id']) ?? 'sync')
            : 'sync');

    List<dynamic> cash = const [];
    if (aggregate is MapTransactionAggregate) {
      final json = aggregate.toJson();
      if (json['cash'] is List) {
        cash = json['cash'] as List;
      } else if (aggregate.metadata is MapTransactionMetadata) {
        final extraMeta = (aggregate.metadata as MapTransactionMetadata).extra;
        if (extraMeta['cash'] is List) {
          cash = extraMeta['cash'] as List;
        }
      }
    }
    for (final raw in cash) {
      if (raw is! Map) continue;
      final c = Map<String, dynamic>.from(raw);
      final cashId = (c['cash_transaction_id'] ?? c['id'] ?? '').toString();
      final type = (c['transaction_type'] ?? '').toString().toLowerCase();
      final amount = _asDouble(c['amount']);
      if (cashId.isEmpty || amount <= 0 || (type != 'in' && type != 'out')) {
        continue;
      }
      final exists = await txn.query(
        'cashTransactions',
        columns: const ['id'],
        where: 'id = ?',
        whereArgs: [cashId],
        limit: 1,
      );
      if (exists.isNotEmpty) continue;
      await txn.insert('cashTransactions', {
        'id': cashId,
        'organizationId': header.companyId,
        'branchId': header.branchId,
        'transactionType': type,
        'amount': amount,
        'description': (c['description'] ?? '').toString(),
        'referenceType':
            (c['reference_type'] ?? 'sale_void').toString(),
        'referenceId': invoiceId,
        'transactionDate':
            (c['transaction_date'] ?? when).toString(),
        'createdBy':
            (c['created_by_user_id'] ?? createdBy).toString(),
      });
    }
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
    final invoiceId = header.id;
    final row = <String, Object?>{
      'id': invoiceId,
      'organizationId': header.companyId,
      'branchId': header.branchId,
      'customerId': _optionalString(extra['customer_id']),
      'invoiceDate': _optionalString(extra['invoice_date']) ??
          DateTime.now().toIso8601String(),
      'total': _asDouble(extra['total']),
      'paymentType': (_optionalString(extra['payment_type']) ?? 'cash'),
      'invoiceStatus': 'draft',
      'createdBy': _optionalString(extra['created_by_user_id']) ?? 'sync',
      'notes': _optionalString(extra['notes']),
      'discountAmount': _asDouble(extra['discount_amount']),
      'taxPercent': _asDouble(extra['tax_percent']),
      'lineSubtotal': _asDouble(extra['line_subtotal']),
      'paidAmount': _asDouble(extra['paid_amount']),
      'priceListId': _optionalString(extra['price_list_id']),
      'transactionVersion': forPostMaterialization &&
              header.status == 'posted' &&
              header.transactionVersion > 0
          ? header.transactionVersion - 1
          : header.transactionVersion,
      'rowVersion': header.rowVersion,
    };

    final existing = await txn.query(
      'salesInvoices',
      where: 'id = ?',
      whereArgs: [invoiceId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final localStatus =
          (existing.first['invoiceStatus'] ?? '').toString();
      // Never downgrade a posted/voided invoice when a draft create/update
      // arrives from cloud — that caused post_effects_exist on the next post.
      if (!forPostMaterialization &&
          (localStatus == 'posted' ||
              localStatus == 'voided' ||
              localStatus == 'void')) {
        return SyncPullApplyOutcome.applied;
      }
    }
    if (existing.isEmpty) {
      await txn.insert('salesInvoices', row);
    } else {
      await txn.update(
        'salesInvoices',
        row,
        where: 'id = ?',
        whereArgs: [invoiceId],
      );
    }

    await txn.delete(
      'salesInvoiceItems',
      where: 'invoiceId = ?',
      whereArgs: [invoiceId],
    );

    for (final line in aggregate.lines) {
      final fields = line is MapTransactionLine ? line.fields : const {};
      final lineId = line.lineId.isNotEmpty
          ? line.lineId
          : (fields['id'] ?? fields['line_id'] ?? '').toString();
      if (lineId.isEmpty) continue;

      final quantity = _asDouble(fields['quantity']);
      final unitPrice = _asDouble(fields['unit_price']);
      final lineTotal = _asDouble(fields['line_total'], fallback: quantity * unitPrice);

      await txn.insert('salesInvoiceItems', {
        'id': lineId,
        'invoiceId': invoiceId,
        'productId': (fields['product_id'] ?? '').toString(),
        'quantity': quantity,
        'unitPrice': unitPrice,
        'lineTotal': lineTotal,
      });
    }

    return SyncPullApplyOutcome.applied;
  }

  Future<SyncPullApplyOutcome> _deleteDraft(
    TransactionAggregate aggregate,
    DatabaseExecutor txn,
  ) async {
    final invoiceId = aggregate.header.id;
    await txn.delete(
      'salesInvoiceItems',
      where: 'invoiceId = ?',
      whereArgs: [invoiceId],
    );
    final count = await txn.delete(
      'salesInvoices',
      where: 'id = ?',
      whereArgs: [invoiceId],
    );
    if (count > 0) return SyncPullApplyOutcome.applied;

    final existing = await txn.query(
      'salesInvoices',
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [invoiceId],
      limit: 1,
    );
    return existing.isEmpty
        ? SyncPullApplyOutcome.applied
        : SyncPullApplyOutcome.failed;
  }

  Future<SyncPullApplyOutcome> _ensureDependencies(
    TransactionAggregate aggregate,
    DatabaseExecutor txn,
  ) async {
    final header = aggregate.header;
    final extra = header is MapTransactionHeader ? header.extra : const {};
    final customerId = _optionalString(extra['customer_id']);
    if (customerId != null) {
      final customer = await txn.query(
        'customers',
        columns: const ['id'],
        where: 'id = ?',
        whereArgs: [customerId],
        limit: 1,
      );
      if (customer.isEmpty) {
        return SyncPullApplyOutcome.deferred;
      }
    }

    for (final line in aggregate.lines) {
      final fields = line is MapTransactionLine ? line.fields : const {};
      final productId = (fields['product_id'] ?? '').toString();
      if (productId.isEmpty) continue;
      final product = await txn.query(
        'products',
        columns: const ['id'],
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      if (product.isEmpty) {
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
