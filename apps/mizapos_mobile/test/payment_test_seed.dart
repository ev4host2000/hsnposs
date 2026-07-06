import 'package:sqflite/sqflite.dart';

/// Shared fixtures: draft customer/supplier payment for post/sync tests.
class PaymentTestSeed {
  PaymentTestSeed._();

  static Future<void> seedCustomerPaymentDraft(
    Database db, {
    required String paymentId,
    required String companyId,
    required String branchId,
    required String customerId,
    required String userId,
    double amount = 50,
    String paymentMethod = 'cash',
    String? notes,
    String? voucherNumber,
  }) async {
    await db.insert('customerPayments', {
      'id': paymentId,
      'organizationId': companyId,
      'branchId': branchId,
      'customerId': customerId,
      'amount': amount,
      'paymentDate': DateTime.now().toIso8601String(),
      'paymentMethod': paymentMethod,
      'voucherNumber': voucherNumber,
      'notes': notes,
      'paymentStatus': 'draft',
      'createdBy': userId,
      'transactionVersion': 0,
      'rowVersion': 1,
    });
  }

  static Future<void> seedSupplierPaymentDraft(
    Database db, {
    required String paymentId,
    required String companyId,
    required String branchId,
    required String supplierId,
    required String userId,
    double amount = 50,
    String paymentMethod = 'cash',
    String? notes,
    String? voucherNumber,
  }) async {
    await db.insert('supplierPayments', {
      'id': paymentId,
      'organizationId': companyId,
      'branchId': branchId,
      'supplierId': supplierId,
      'amount': amount,
      'paymentDate': DateTime.now().toIso8601String(),
      'paymentMethod': paymentMethod,
      'voucherNumber': voucherNumber,
      'notes': notes,
      'paymentStatus': 'draft',
      'createdBy': userId,
      'transactionVersion': 0,
      'rowVersion': 1,
    });
  }
}
