/// Transaction sync identifiers — ADR-TX-001 … ADR-TX-017.
///
/// No document types are registered here; concrete types register via
/// [TransactionRegistry] in future sprints.
class TransactionSyncConstants {
  TransactionSyncConstants._();

  static const payloadSchemaVersion = 1;

  static const syncStatePending = 'pending';
  static const syncStateSynced = 'synced';
  static const syncStateFailed = 'failed';

  /// Populated when types register via [TransactionRegistry].
  static const List<String> transactionEntityTypes = [
    'sales_invoice',
    'purchase_invoice',
    'sales_return',
    'purchase_return',
    'customer_payment',
    'supplier_payment',
  ];

  static const List<String> transactionPullScopes = [
    'sales_invoices',
    'purchase_invoices',
    'sales_returns',
    'purchase_returns',
    'customer_payments',
    'supplier_payments',
  ];

  static const List<String> supportedOperations = [
    'create',
    'update',
    'post',
    'cancel',
  ];

  static const List<String> draftOperations = ['create', 'update'];

  static const List<String> effectOperations = ['post', 'cancel'];
}
