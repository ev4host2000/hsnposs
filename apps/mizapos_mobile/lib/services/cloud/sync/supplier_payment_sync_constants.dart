/// Supplier payment draft/post sync identifiers.
class SupplierPaymentSyncConstants {
  SupplierPaymentSyncConstants._();

  static const entityType = 'supplier_payment';
  static const scopeKey = 'supplier_payments';

  static const pushPath = '/sync/push/supplier-payments';
  static const pullPath = '/sync/pull/supplier-payments';
}
