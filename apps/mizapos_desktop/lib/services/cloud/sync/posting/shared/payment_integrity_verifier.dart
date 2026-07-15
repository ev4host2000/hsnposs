import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_integrity_exception.dart';
import 'package:sqflite/sqflite.dart';

/// Shared pre-finalize integrity checks for customer/supplier payment pipelines.
class PaymentIntegrityVerifier {
  PaymentIntegrityVerifier._();

  static Future<void> verify({
    required PostingContext context,
    required String referenceType,
    required Future<Map<String, Object?>?> Function(
      DatabaseExecutor txn,
      String documentId,
    ) loadPayment,
    required String statusColumn,
    required double amount,
    required String cashTransactionType,
    required PaymentCashEffectView cash,
    required PaymentAccountingEffectView accounting,
  }) async {
    final idempotentReplay = context.stageData['idempotent_replay'] == true;
    final paymentId = context.aggregate.header.id;

    if (amount <= 0) {
      throw const PostingIntegrityException('Payment amount must be > 0');
    }

    if (cash.amount != amount) {
      throw PostingIntegrityException(
        'Cash amount mismatch: cash=${cash.amount} header=$amount',
      );
    }
    if (cash.transactionType != cashTransactionType) {
      throw PostingIntegrityException(
        'Cash direction mismatch: expected $cashTransactionType got ${cash.transactionType}',
      );
    }
    if ((accounting.amountSigned + amount).abs() > 1e-9) {
      throw PostingIntegrityException(
        'Ledger amount mismatch: ledger=${accounting.amountSigned} expected=${-amount}',
      );
    }

    if (context.stageData.containsKey('inventory')) {
      throw const PostingIntegrityException(
        'Payment post must not include inventory effects',
      );
    }

    final seenIds = <String>{};
    if (cash.cashTransactionId.isEmpty) {
      throw const PostingIntegrityException('Cash transaction UUID is required');
    }
    if (!seenIds.add(cash.cashTransactionId)) {
      throw PostingIntegrityException(
        'Duplicate cash UUID ${cash.cashTransactionId}',
      );
    }
    if (accounting.entryId.isEmpty) {
      throw const PostingIntegrityException('Accounting entry UUID is required');
    }
    if (!seenIds.add(accounting.entryId)) {
      throw PostingIntegrityException(
        'Duplicate accounting UUID ${accounting.entryId}',
      );
    }

    if (!idempotentReplay) {
      final document = await loadPayment(context.txn, paymentId);
      final dbStatus = (document?[statusColumn] ?? '').toString();
      if (dbStatus == 'posted') {
        throw const PostingIntegrityException('Document is already posted');
      }
    }

    final movementRows = await context.txn.query(
      'stockMovements',
      columns: const ['id'],
      where: 'referenceType = ? AND referenceId = ?',
      whereArgs: [referenceType, paymentId],
    );
    if (movementRows.isNotEmpty) {
      throw PostingIntegrityException(
        'Unexpected stock movements for payment: ${movementRows.length}',
      );
    }

    final cashRows = await context.txn.query(
      'cashTransactions',
      columns: const ['id'],
      where: 'referenceType = ? AND referenceId = ?',
      whereArgs: [referenceType, paymentId],
    );
    if (cashRows.length > 1) {
      throw PostingIntegrityException(
        'Unexpected cash transactions in DB: ${cashRows.length}',
      );
    }

    final ledgerRows = await context.txn.query(
      'partnerLedger',
      columns: const ['id'],
      where: 'referenceType = ? AND referenceId = ?',
      whereArgs: [referenceType, paymentId],
    );
    if (ledgerRows.length > 1) {
      throw PostingIntegrityException(
        'Unexpected ledger entries in DB: ${ledgerRows.length}',
      );
    }
  }
}

class PaymentCashEffectView {
  const PaymentCashEffectView({
    required this.cashTransactionId,
    required this.transactionType,
    required this.amount,
  });

  final String cashTransactionId;
  final String transactionType;
  final double amount;
}

class PaymentAccountingEffectView {
  const PaymentAccountingEffectView({
    required this.entryId,
    required this.amountSigned,
  });

  final String entryId;
  final double amountSigned;
}
