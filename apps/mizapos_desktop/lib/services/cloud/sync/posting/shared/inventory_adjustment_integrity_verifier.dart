import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_integrity_exception.dart';
import 'package:sqflite/sqflite.dart';

/// Shared pre-finalize integrity checks for inventory-adjustment pipelines.
class InventoryAdjustmentIntegrityVerifier {
  InventoryAdjustmentIntegrityVerifier._();

  static Future<void> verify({
    required PostingContext context,
    required String referenceType,
    required Future<Map<String, Object?>?> Function(
      DatabaseExecutor txn,
      String documentId,
    ) loadAdjustment,
    required String statusColumn,
    required double quantityDelta,
    required InventoryAdjustmentEffectView inventory,
  }) async {
    final idempotentReplay = context.stageData['idempotent_replay'] == true;
    final adjustmentId = context.aggregate.header.id;

    if (quantityDelta.abs() < 1e-9) {
      throw const PostingIntegrityException('quantity_delta must be non-zero');
    }

    final expectedType = quantityDelta > 0 ? 'in' : 'out';
    if (inventory.movementType != expectedType) {
      throw PostingIntegrityException(
        'Movement type mismatch: expected $expectedType got ${inventory.movementType}',
      );
    }
    if ((inventory.quantity - quantityDelta.abs()).abs() > 1e-9) {
      throw PostingIntegrityException(
        'Movement quantity mismatch: movement=${inventory.quantity} delta=$quantityDelta',
      );
    }

    if (context.stageData.containsKey('cash') ||
        context.stageData.containsKey('accounting')) {
      throw const PostingIntegrityException(
        'Inventory adjustment post must not include cash or accounting effects',
      );
    }

    if (inventory.movementId.isEmpty) {
      throw const PostingIntegrityException('Stock movement UUID is required');
    }

    if (!idempotentReplay) {
      final document = await loadAdjustment(context.txn, adjustmentId);
      final dbStatus = (document?[statusColumn] ?? '').toString();
      if (dbStatus == 'posted') {
        throw const PostingIntegrityException('Document is already posted');
      }
    }

    final cashRows = await context.txn.query(
      'cashTransactions',
      columns: const ['id'],
      where: 'referenceType = ? AND referenceId = ?',
      whereArgs: [referenceType, adjustmentId],
    );
    if (cashRows.isNotEmpty) {
      throw PostingIntegrityException(
        'Unexpected cash transactions for adjustment: ${cashRows.length}',
      );
    }

    final ledgerRows = await context.txn.query(
      'partnerLedger',
      columns: const ['id'],
      where: 'referenceType = ? AND referenceId = ?',
      whereArgs: [referenceType, adjustmentId],
    );
    if (ledgerRows.isNotEmpty) {
      throw PostingIntegrityException(
        'Unexpected ledger entries for adjustment: ${ledgerRows.length}',
      );
    }

    final movementRows = await context.txn.query(
      'stockMovements',
      columns: const ['id'],
      where: 'referenceType = ? AND referenceId = ?',
      whereArgs: [referenceType, adjustmentId],
    );
    if (movementRows.length > 1) {
      throw PostingIntegrityException(
        'Unexpected stock movements in DB: ${movementRows.length}',
      );
    }
  }
}

class InventoryAdjustmentEffectView {
  const InventoryAdjustmentEffectView({
    required this.movementId,
    required this.movementType,
    required this.quantity,
  });

  final String movementId;
  final String movementType;
  final double quantity;
}
