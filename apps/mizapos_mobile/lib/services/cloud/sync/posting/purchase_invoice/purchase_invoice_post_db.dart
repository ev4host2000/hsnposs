import 'package:mizapos_mobile/services/cloud/sync/posting/purchase_invoice/purchase_invoice_post_effects.dart';
import 'package:sqflite/sqflite.dart';

/// SQLite helpers for purchase-invoice post effects (idempotent).
class PurchaseInvoicePostDb {
  PurchaseInvoicePostDb._();

  static Future<Map<String, Object?>?> loadInvoice(
    DatabaseExecutor txn,
    String invoiceId,
  ) async {
    final rows = await txn.query(
      'purchaseInvoices',
      where: 'id = ?',
      whereArgs: [invoiceId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<List<Map<String, Object?>>> loadInvoiceLines(
    DatabaseExecutor txn,
    String invoiceId,
  ) {
    return txn.query(
      'purchaseInvoiceItems',
      where: 'invoiceId = ?',
      whereArgs: [invoiceId],
    );
  }

  static Future<bool> partnerExists(
    DatabaseExecutor txn,
    String table,
    String id,
  ) async {
    final rows = await txn.query(
      table,
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  static Future<bool> productExists(
    DatabaseExecutor txn,
    String productId,
  ) =>
      partnerExists(txn, 'products', productId);

  static Future<bool> movementExists(
    DatabaseExecutor txn,
    String movementId,
  ) async {
    final rows = await txn.query(
      'stockMovements',
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [movementId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  static Future<bool> ledgerEntryExists(
    DatabaseExecutor txn,
    String entryId,
  ) async {
    final rows = await txn.query(
      'partnerLedger',
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [entryId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  static Future<bool> hasPostMovementsForInvoice(
    DatabaseExecutor txn,
    String invoiceId,
  ) async {
    final rows = await txn.query(
      'stockMovements',
      columns: const ['id'],
      where: 'referenceType = ? AND referenceId = ?',
      whereArgs: ['purchase', invoiceId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Inserts movement if missing; increases stock once per new movement.
  static Future<void> applyInventoryEffect(
    DatabaseExecutor txn, {
    required PurchaseInvoiceInventoryEffect effect,
    required String organizationId,
    required String branchId,
  }) async {
    if (await movementExists(txn, effect.movementId)) return;

    final productRows = await txn.query(
      'products',
      where: 'id = ?',
      whereArgs: [effect.productId],
      limit: 1,
    );
    if (productRows.isEmpty) {
      throw StateError('product_not_found:${effect.productId}');
    }
    final currentStock =
        (productRows.first['stockQty'] as num?)?.toDouble() ?? 0.0;
    final newStock = currentStock + effect.quantity;

    await txn.insert('stockMovements', {
      'id': effect.movementId,
      'organizationId': organizationId,
      'branchId': branchId,
      'productId': effect.productId,
      'movementType': effect.movementType,
      'quantity': effect.quantity,
      'referenceType': effect.referenceType,
      'referenceId': effect.referenceId,
      'movementDate': effect.movementDate,
      'createdBy': effect.createdBy,
    });

    await txn.update(
      'products',
      {'stockQty': newStock},
      where: 'id = ?',
      whereArgs: [effect.productId],
    );
  }

  static Future<void> applyAccountingEffect(
    DatabaseExecutor txn, {
    required PurchaseInvoiceAccountingEffect effect,
    required String organizationId,
    required String branchId,
  }) async {
    if (await ledgerEntryExists(txn, effect.entryId)) return;

    await txn.insert('partnerLedger', {
      'id': effect.entryId,
      'organizationId': organizationId,
      'branchId': branchId,
      'partnerKind': effect.partnerKind,
      'partnerId': effect.partnerId,
      'entryType': effect.entryType,
      'referenceType': effect.referenceType,
      'referenceId': effect.referenceId,
      'amountSigned': effect.amountSigned,
      'notes': effect.notes,
      'entryDate': effect.entryDate,
      'createdBy': effect.createdBy,
    });
  }

  static Future<bool> finalizeInvoice(
    DatabaseExecutor txn, {
    required String invoiceId,
    required int transactionVersion,
    required int rowVersion,
    required String postedAt,
  }) async {
    final rowsAffected = await txn.update(
      'purchaseInvoices',
      {
        'invoiceStatus': 'posted',
        'postedAt': postedAt,
        'transactionVersion': transactionVersion,
        'rowVersion': rowVersion,
      },
      where: 'id = ? AND invoiceStatus = ?',
      whereArgs: [invoiceId, 'draft'],
    );
    return rowsAffected == 1;
  }
}
