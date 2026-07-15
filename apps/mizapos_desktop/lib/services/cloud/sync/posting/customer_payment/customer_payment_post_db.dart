import 'package:mizapos_desktop/services/cloud/sync/posting/customer_payment/customer_payment_post_effects.dart';
import 'package:sqflite/sqflite.dart';

/// SQLite helpers for customer-payment post effects (idempotent).
class CustomerPaymentPostDb {
  CustomerPaymentPostDb._();

  static Future<Map<String, Object?>?> loadPayment(
    DatabaseExecutor txn,
    String paymentId,
  ) async {
    final rows = await txn.query(
      'customerPayments',
      where: 'id = ?',
      whereArgs: [paymentId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<bool> partnerExists(
    DatabaseExecutor txn,
    String customerId,
  ) async {
    final rows = await txn.query(
      'customers',
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [customerId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  static Future<bool> cashTransactionExists(
    DatabaseExecutor txn,
    String cashTransactionId,
  ) async {
    final rows = await txn.query(
      'cashTransactions',
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [cashTransactionId],
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

  static Future<bool> hasPostEffectsForPayment(
    DatabaseExecutor txn,
    String paymentId,
  ) async {
    final cashRows = await txn.query(
      'cashTransactions',
      columns: const ['id'],
      where: 'referenceType = ? AND referenceId = ?',
      whereArgs: ['customer_payment', paymentId],
      limit: 1,
    );
    if (cashRows.isNotEmpty) return true;

    final ledgerRows = await txn.query(
      'partnerLedger',
      columns: const ['id'],
      where: 'referenceType = ? AND referenceId = ?',
      whereArgs: ['customer_payment', paymentId],
      limit: 1,
    );
    return ledgerRows.isNotEmpty;
  }

  static Future<void> applyCashEffect(
    DatabaseExecutor txn, {
    required CustomerPaymentCashEffect effect,
    required String organizationId,
    required String branchId,
  }) async {
    if (await cashTransactionExists(txn, effect.cashTransactionId)) return;

    await txn.insert('cashTransactions', {
      'id': effect.cashTransactionId,
      'organizationId': organizationId,
      'branchId': branchId,
      'transactionType': effect.transactionType,
      'amount': effect.amount,
      'description': effect.description,
      'referenceType': effect.referenceType,
      'referenceId': effect.referenceId,
      'transactionDate': effect.transactionDate,
      'createdBy': effect.createdBy,
    });
  }

  static Future<void> applyAccountingEffect(
    DatabaseExecutor txn, {
    required CustomerPaymentAccountingEffect effect,
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
      'voucherNumber': effect.voucherNumber,
      'entryDate': effect.entryDate,
      'createdBy': effect.createdBy,
    });
  }

  /// Returns true when exactly one draft row was finalized (optimistic lock).
  static Future<bool> finalizePayment(
    DatabaseExecutor txn, {
    required String paymentId,
    required int transactionVersion,
    required int rowVersion,
    required String postedAt,
  }) async {
    final rowsAffected = await txn.update(
      'customerPayments',
      {
        'paymentStatus': 'posted',
        'postedAt': postedAt,
        'transactionVersion': transactionVersion,
        'rowVersion': rowVersion,
      },
      where: 'id = ? AND paymentStatus = ?',
      whereArgs: [paymentId, 'draft'],
    );
    return rowsAffected == 1;
  }
}
