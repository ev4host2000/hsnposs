/// Purchase invoice draft/post sync identifiers.
class PurchaseInvoiceSyncConstants {
  PurchaseInvoiceSyncConstants._();

  static const entityType = 'purchase_invoice';
  static const scopeKey = 'purchase_invoices';

  static const pushPath = '/sync/push/purchase-invoices';
  static const pullPath = '/sync/pull/purchase-invoices';
}
