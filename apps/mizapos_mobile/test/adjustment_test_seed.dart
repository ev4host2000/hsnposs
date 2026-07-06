import 'package:sqflite/sqflite.dart';

/// Shared fixtures: draft inventory adjustment for post/sync tests.
class AdjustmentTestSeed {
  AdjustmentTestSeed._();

  static Future<void> seedInventoryAdjustmentDraft(
    Database db, {
    required String adjustmentId,
    required String companyId,
    required String branchId,
    required String productId,
    required String userId,
    double quantityDelta = 5,
    String adjustmentReason = 'correction',
    String? notes,
  }) async {
    await db.insert('inventoryAdjustments', {
      'id': adjustmentId,
      'organizationId': companyId,
      'branchId': branchId,
      'productId': productId,
      'quantityDelta': quantityDelta,
      'adjustmentReason': adjustmentReason,
      'adjustmentDate': DateTime.now().toIso8601String(),
      'notes': notes,
      'adjustmentStatus': 'draft',
      'createdBy': userId,
      'transactionVersion': 0,
      'rowVersion': 1,
    });
  }
}
