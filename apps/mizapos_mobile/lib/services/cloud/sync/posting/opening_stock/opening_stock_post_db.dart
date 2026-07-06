import 'package:mizapos_mobile/services/cloud/sync/posting/opening_stock/opening_stock_post_effects.dart';
import 'package:sqflite/sqflite.dart';

/// SQLite helpers for opening-stock post effects (idempotent).
class OpeningStockPostDb {
  OpeningStockPostDb._();

  static Future<Map<String, Object?>?> loadOpeningStock(
    DatabaseExecutor txn,
    String openingStockId,
  ) async {
    final rows = await txn.query(
      'openingStocks',
      where: 'id = ?',
      whereArgs: [openingStockId],
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

  static Future<bool> hasPostMovementsForOpeningStock(
    DatabaseExecutor txn,
    String openingStockId,
  ) async {
    final rows = await txn.query(
      'stockMovements',
      columns: const ['id'],
      where: 'referenceType = ? AND referenceId = ?',
      whereArgs: ['opening_stock', openingStockId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Inserts movement if missing; updates stock once per new movement.
  static Future<void> applyInventoryEffect(
    DatabaseExecutor txn, {
    required OpeningStockInventoryEffect effect,
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

  /// Returns true when exactly one draft row was finalized (optimistic lock).
  static Future<bool> finalizeOpeningStock(
    DatabaseExecutor txn, {
    required String openingStockId,
    required int transactionVersion,
    required int rowVersion,
    required String postedAt,
  }) async {
    final rowsAffected = await txn.update(
      'openingStocks',
      {
        'openingStatus': 'posted',
        'postedAt': postedAt,
        'transactionVersion': transactionVersion,
        'rowVersion': rowVersion,
      },
      where: 'id = ? AND openingStatus = ?',
      whereArgs: [openingStockId, 'draft'],
    );
    return rowsAffected == 1;
  }
}
