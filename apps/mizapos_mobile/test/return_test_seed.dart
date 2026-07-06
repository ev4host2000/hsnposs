import 'package:sqflite/sqflite.dart';

/// Shared fixtures: posted parent invoice + draft return for return post/sync tests.
class ReturnTestSeed {
  ReturnTestSeed._();

  static Future<void> seedDraftParentPurchaseInvoice(
    Database db, {
    required String originalInvoiceId,
    required String parentLineId,
    required String companyId,
    required String branchId,
    required String supplierId,
    required String productId,
    required String userId,
    double total = 50,
  }) async {
    await db.insert('purchaseInvoices', {
      'id': originalInvoiceId,
      'organizationId': companyId,
      'branchId': branchId,
      'supplierId': supplierId,
      'invoiceDate': DateTime.now().toIso8601String(),
      'total': total,
      'paymentType': 'cash',
      'invoiceStatus': 'draft',
      'createdBy': userId,
      'discountAmount': 0,
      'taxPercent': 0,
      'lineSubtotal': total,
      'paidAmount': 0,
      'transactionVersion': 0,
      'rowVersion': 1,
    });
    await db.insert('purchaseInvoiceItems', {
      'id': parentLineId,
      'invoiceId': originalInvoiceId,
      'productId': productId,
      'quantity': 2,
      'unitCost': total / 2,
      'lineTotal': total,
    });
  }

  static Future<void> seedPostedParentPurchaseInvoice(
    Database db, {
    required String originalInvoiceId,
    required String parentLineId,
    required String companyId,
    required String branchId,
    required String supplierId,
    required String productId,
    required String userId,
    double total = 50,
  }) async {
    await db.insert('purchaseInvoices', {
      'id': originalInvoiceId,
      'organizationId': companyId,
      'branchId': branchId,
      'supplierId': supplierId,
      'invoiceDate': DateTime.now().toIso8601String(),
      'total': total,
      'paymentType': 'cash',
      'invoiceStatus': 'posted',
      'postedAt': DateTime.now().toIso8601String(),
      'createdBy': userId,
      'discountAmount': 0,
      'taxPercent': 0,
      'lineSubtotal': total,
      'paidAmount': total,
      'transactionVersion': 1,
      'rowVersion': 2,
    });
    await db.insert('purchaseInvoiceItems', {
      'id': parentLineId,
      'invoiceId': originalInvoiceId,
      'productId': productId,
      'quantity': 2,
      'unitCost': total / 2,
      'lineTotal': total,
    });
  }

  static Future<void> seedPurchaseReturnDraft(
    Database db, {
    required String returnId,
    required String returnLineId,
    required String originalInvoiceId,
    required String companyId,
    required String branchId,
    required String supplierId,
    required String productId,
    required String userId,
    double total = 50,
  }) async {
    await db.insert('purchaseReturns', {
      'id': returnId,
      'organizationId': companyId,
      'branchId': branchId,
      'supplierId': supplierId,
      'originalInvoiceId': originalInvoiceId,
      'returnDate': DateTime.now().toIso8601String(),
      'total': total,
      'refundPaymentType': 'cash',
      'returnStatus': 'draft',
      'createdBy': userId,
      'discountAmount': 0,
      'taxPercent': 0,
      'lineSubtotal': total,
      'paidAmount': 0,
      'transactionVersion': 0,
      'rowVersion': 1,
    });
    await db.insert('purchaseReturnItems', {
      'id': returnLineId,
      'returnId': returnId,
      'productId': productId,
      'quantity': 2,
      'unitCost': total / 2,
      'lineTotal': total,
    });
  }

  static Future<void> seedDraftParentSalesInvoice(
    Database db, {
    required String originalInvoiceId,
    required String parentLineId,
    required String companyId,
    required String branchId,
    required String customerId,
    required String productId,
    required String userId,
    double total = 50,
  }) async {
    await db.insert('salesInvoices', {
      'id': originalInvoiceId,
      'organizationId': companyId,
      'branchId': branchId,
      'customerId': customerId,
      'invoiceDate': DateTime.now().toIso8601String(),
      'total': total,
      'paymentType': 'cash',
      'invoiceStatus': 'draft',
      'createdBy': userId,
      'discountAmount': 0,
      'taxPercent': 0,
      'lineSubtotal': total,
      'paidAmount': 0,
      'transactionVersion': 0,
      'rowVersion': 1,
    });
    await db.insert('salesInvoiceItems', {
      'id': parentLineId,
      'invoiceId': originalInvoiceId,
      'productId': productId,
      'quantity': 2,
      'unitPrice': total / 2,
      'lineTotal': total,
    });
  }

  static Future<void> seedPostedParentSalesInvoice(
    Database db, {
    required String originalInvoiceId,
    required String parentLineId,
    required String companyId,
    required String branchId,
    required String customerId,
    required String productId,
    required String userId,
    double total = 50,
  }) async {
    await db.insert('salesInvoices', {
      'id': originalInvoiceId,
      'organizationId': companyId,
      'branchId': branchId,
      'customerId': customerId,
      'invoiceDate': DateTime.now().toIso8601String(),
      'total': total,
      'paymentType': 'cash',
      'invoiceStatus': 'posted',
      'postedAt': DateTime.now().toIso8601String(),
      'createdBy': userId,
      'discountAmount': 0,
      'taxPercent': 0,
      'lineSubtotal': total,
      'paidAmount': total,
      'transactionVersion': 1,
      'rowVersion': 2,
    });
    await db.insert('salesInvoiceItems', {
      'id': parentLineId,
      'invoiceId': originalInvoiceId,
      'productId': productId,
      'quantity': 2,
      'unitPrice': total / 2,
      'lineTotal': total,
    });
  }

  static Future<void> seedSalesReturnDraft(
    Database db, {
    required String returnId,
    required String returnLineId,
    required String originalInvoiceId,
    required String companyId,
    required String branchId,
    required String customerId,
    required String productId,
    required String userId,
    double total = 50,
  }) async {
    await db.insert('salesReturns', {
      'id': returnId,
      'organizationId': companyId,
      'branchId': branchId,
      'customerId': customerId,
      'originalInvoiceId': originalInvoiceId,
      'returnDate': DateTime.now().toIso8601String(),
      'total': total,
      'refundPaymentType': 'cash',
      'returnStatus': 'draft',
      'createdBy': userId,
      'discountAmount': 0,
      'taxPercent': 0,
      'lineSubtotal': total,
      'paidAmount': 0,
      'transactionVersion': 0,
      'rowVersion': 1,
    });
    await db.insert('salesReturnItems', {
      'id': returnLineId,
      'returnId': returnId,
      'productId': productId,
      'quantity': 2,
      'unitPrice': total / 2,
      'lineTotal': total,
    });
  }
}
