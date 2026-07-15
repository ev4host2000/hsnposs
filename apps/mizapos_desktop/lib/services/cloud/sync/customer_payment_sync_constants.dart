/// Customer payment draft/post sync identifiers.
class CustomerPaymentSyncConstants {
  CustomerPaymentSyncConstants._();

  static const entityType = 'customer_payment';
  static const scopeKey = 'customer_payments';

  static const pushPath = '/sync/push/customer-payments';
  static const pullPath = '/sync/pull/customer-payments';
}
