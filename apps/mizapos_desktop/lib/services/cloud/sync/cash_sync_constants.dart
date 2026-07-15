/// Cash box / cash_transaction sync identifiers.
class CashSyncConstants {
  CashSyncConstants._();

  static const entityType = 'cash_transaction';
  static const scopeKey = 'cash_transactions';
  static const pushPath = '/sync/push/cash-transactions';
  static const pullPath = '/sync/pull/cash-transactions';

  /// Payment-post cash is already synced via customer/supplier payment aggregates.
  static const paymentSyncedReferenceTypes = {
    'customer_payment',
    'supplier_payment',
  };
}
