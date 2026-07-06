import 'package:mizapos_desktop/services/cloud/sync/posting/inventory_adjustment/inventory_adjustment_post_effects.dart';
import 'package:sqflite/sqflite.dart';

/// SQLite helpers for inventory-adjustment post effects (idempotent).
class InventoryAdjustmentPostDb {
  InventoryAdjustmentPostDb._();

  static Future<Map<String, Object?>?> loadAdjustment(
    DatabaseExecutor txn,
    String adjustmentId,
  ) async {
    final rows = await txn.query(
      'inventoryAdjustments',
      where: 'id = ?',
      whereArgs: [adjustmentId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<bool> productExists(
    DatabaseExecutor txn,
    String productId,
  ) async {
    final rows = await txn.query(
      'products',
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

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

  static Future<bool> hasPostMovementsForAdjustment(
    DatabaseExecutor txn,
    String adjustmentId,
  ) async {
    final rows = await txn.query(
      'stockMovements',
      columns: const ['id'],
      where: 'referenceType = ? AND referenceId = ?',
      whereArgs: ['inventory_adjustment', adjustmentId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Inserts movement if missing; updates stock once per new movement.
  static Future<void> applyInventoryEffect(
    DatabaseExecutor txn, {
    required InventoryAdjustmentInventoryEffect effect,
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
    final newStock = effect.movementType == 'in'
        ? currentStock + effect.quantity
        : currentStock - effect.quantity;
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

  /// Returns true when exactly one draft row was finalized (optimistic lock).
  static Future<bool> finalizeAdjustment(
    DatabaseExecutor txn, {
    required String adjustmentId,
    required int transactionVersion,
    required int rowVersion,
    required String postedAt,
  }) async {
    final rowsAffected = await txn.update(
      'inventoryAdjustments',
      {
        'adjustmentStatus': 'posted',
        'postedAt': postedAt,
        'transactionVersion': transactionVersion,
        'rowVersion': rowVersion,
      },
      where: 'id = ? AND adjustmentStatus = ?',
      whereArgs: [adjustmentId, 'draft'],
    );
    return rowsAffected == 1;
  }
}
