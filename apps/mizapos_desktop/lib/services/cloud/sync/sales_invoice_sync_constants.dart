/// Sales invoice draft sync identifiers.
class SalesInvoiceSyncConstants {
  SalesInvoiceSyncConstants._();

  static const entityType = 'sales_invoice';
  static const scopeKey = 'sales_invoices';

  static const pushPath = '/sync/push/sales-invoices';
  static const pullPath = '/sync/pull/sales-invoices';
}
