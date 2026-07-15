/// Shared sync exception for transaction workers.
class TransactionSyncException implements Exception {
  TransactionSyncException(this.code);

  final String code;

  @override
  String toString() => 'TransactionSyncException($code)';
}
