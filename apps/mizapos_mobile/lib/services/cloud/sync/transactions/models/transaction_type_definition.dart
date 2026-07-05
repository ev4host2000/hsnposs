import 'package:mizapos_mobile/services/cloud/sync/transactions/transaction_apply_handler.dart';

/// Registration descriptor for a future transaction document type — ADR-TX-015.
class TransactionTypeDefinition {
  const TransactionTypeDefinition({
    required this.entityType,
    required this.scopeKey,
    required this.pushPath,
    required this.pullPath,
    required this.applyHandler,
    this.payloadSchemaVersion = 1,
  });

  final String entityType;
  final String scopeKey;
  final String pushPath;
  final String pullPath;
  final int payloadSchemaVersion;
  final TransactionApplyHandler applyHandler;
}
