import 'package:mizapos_desktop/services/cloud/sync/posting/purchase_return/purchase_return_post_effects.dart';
import 'package:sqflite/sqflite.dart';

/// SQLite helpers for purchase-return post effects (idempotent).
class PurchaseReturnPostDb {
  PurchaseReturnPostDb._();

  static Future<Map<String, Object?>?> loadReturn(
    DatabaseExecutor txn,
    String returnId,
  ) async {
    final rows = await txn.query(
      'purchaseReturns',
      where: 'id = ?',
      whereArgs: [returnId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<List<Map<String, Object?>>> loadReturnLines(
    DatabaseExecutor txn,
    String returnId,
  ) {
    return txn.query(
      'purchaseReturnItems',
      where: 'returnId = ?',
      whereArgs: [returnId],
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

  static Future<bool> hasPostMovementsForReturn(
    DatabaseExecutor txn,
    String returnId,
  ) async {
    final rows = await txn.query(
      'stockMovements',
      columns: const ['id'],
      where: 'referenceType = ? AND referenceId = ?',
      whereArgs: ['purchase_return', returnId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Inserts movement if missing; subtracts stock once per new movement.
  static Future<void> applyInventoryEffect(
    DatabaseExecutor txn, {
    required PurchaseReturnInventoryEffect effect,
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
    final newStock = currentStock - effect.quantity;
    if (newStock < -1e-9) {
      throw StateError('insufficient_stock:${effect.productId}');
    }

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
    required PurchaseReturnAccountingEffect effect,
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

  static Future<bool> finalizeReturn(
    DatabaseExecutor txn, {
    required String returnId,
    required int transactionVersion,
    required int rowVersion,
    required String postedAt,
  }) async {
    final rowsAffected = await txn.update(
      'purchaseReturns',
      {
        'returnStatus': 'posted',
        'postedAt': postedAt,
        'transactionVersion': transactionVersion,
        'rowVersion': rowVersion,
      },
      where: 'id = ? AND returnStatus = ?',
      whereArgs: [returnId, 'draft'],
    );
    return rowsAffected == 1;
  }
}
