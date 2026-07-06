import 'package:mizapos_desktop/services/cloud/sync/transactions/models/transaction_aggregate.dart';
import 'package:sqflite/sqflite.dart';

/// Mutable execution context passed through posting stages.
class PostingContext {
  PostingContext({
    required this.aggregate,
    required this.txn,
    required this.entityType,
    Map<String, Object?>? stageData,
  }) : stageData = stageData ?? <String, Object?>{};

  final TransactionAggregate aggregate;
  final DatabaseExecutor txn;
  final String entityType;

  /// Shared scratch space — stages may read/write without side effects on DB.
  final Map<String, Object?> stageData;
}
