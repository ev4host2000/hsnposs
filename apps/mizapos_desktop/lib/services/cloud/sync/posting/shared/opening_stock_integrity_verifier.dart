import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_integrity_exception.dart';
import 'package:sqflite/sqflite.dart';

/// Shared pre-finalize integrity checks for opening-stock pipelines.
class OpeningStockIntegrityVerifier {
  OpeningStockIntegrityVerifier._();

  static Future<void> verify({
    required PostingContext context,
    required String referenceType,
    required Future<Map<String, Object?>?> Function(
      DatabaseExecutor txn,
      String documentId,
    ) loadOpeningStock,
    required String statusColumn,
    required double openingQuantity,
    required OpeningStockEffectView inventory,
  }) async {
    final idempotentReplay = context.stageData['idempotent_replay'] == true;
    final openingStockId = context.aggregate.header.id;

    if (openingQuantity < 1e-9) {
      throw const PostingIntegrityException(
        'opening_quantity must be positive',
      );
    }

    if (inventory.movementType != 'in') {
      throw PostingIntegrityException(
        'Movement type mismatch: expected in got ${inventory.movementType}',
      );
    }
    if ((inventory.quantity - openingQuantity).abs() > 1e-9) {
      throw PostingIntegrityException(
        'Movement quantity mismatch: movement=${inventory.quantity} opening=$openingQuantity',
      );
    }

    if (context.stageData.containsKey('cash') ||
        context.stageData.containsKey('accounting')) {
      throw const PostingIntegrityException(
        'Opening stock post must not include cash or accounting effects',
      );
    }

    if (inventory.movementId.isEmpty) {
      throw const PostingIntegrityException('Stock movement UUID is required');
    }

    if (!idempotentReplay) {
      final document = await loadOpeningStock(context.txn, openingStockId);
      final dbStatus = (document?[statusColumn] ?? '').toString();
      if (dbStatus == 'posted') {
        throw const PostingIntegrityException('Document is already posted');
      }
    }

    final cashRows = await context.txn.query(
      'cashTransactions',
      columns: const ['id'],
      where: 'referenceType = ? AND referenceId = ?',
      whereArgs: [referenceType, openingStockId],
    );
    if (cashRows.isNotEmpty) {
      throw PostingIntegrityException(
        'Unexpected cash transactions for opening stock: ${cashRows.length}',
      );
    }

    final ledgerRows = await context.txn.query(
      'partnerLedger',
      columns: const ['id'],
      where: 'referenceType = ? AND referenceId = ?',
      whereArgs: [referenceType, openingStockId],
    );
    if (ledgerRows.isNotEmpty) {
      throw PostingIntegrityException(
        'Unexpected ledger entries for opening stock: ${ledgerRows.length}',
      );
    }

    final movementRows = await context.txn.query(
      'stockMovements',
      columns: const ['id'],
      where: 'referenceType = ? AND referenceId = ?',
      whereArgs: [referenceType, openingStockId],
    );
    if (movementRows.length > 1) {
      throw PostingIntegrityException(
        'Unexpected stock movements in DB: ${movementRows.length}',
      );
    }
  }
}

class OpeningStockEffectView {
  const OpeningStockEffectView({
    required this.movementId,
    required this.movementType,
    required this.quantity,
  });

  final String movementId;
  final String movementType;
  final double quantity;
}
