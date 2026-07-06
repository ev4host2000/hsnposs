import 'package:sqflite/sqflite.dart';

/// Shared fixtures: draft opening stock for post/sync tests.
class OpeningStockTestSeed {
  OpeningStockTestSeed._();

  static Future<void> seedOpeningStockDraft(
    Database db, {
    required String openingStockId,
    required String companyId,
    required String branchId,
    required String productId,
    required String userId,
    double openingQuantity = 5,
    String? notes,
  }) async {
    await db.insert('openingStocks', {
      'id': openingStockId,
      'organizationId': companyId,
      'branchId': branchId,
      'productId': productId,
      'openingQuantity': openingQuantity,
      'openingDate': DateTime.now().toIso8601String(),
      'notes': notes,
      'openingStatus': 'draft',
      'createdBy': userId,
      'transactionVersion': 0,
      'rowVersion': 1,
    });
  }
}
