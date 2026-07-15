import 'package:mizapos_desktop/services/cloud/sync/models/sync_changelog_entry.dart';
import 'package:mizapos_desktop/services/cloud/sync/sync_pull_apply.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/models/transaction_aggregate.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/models/transaction_operation.dart';
import 'package:sqflite/sqflite.dart';

/// Document-type apply hook — inventory/accounting implemented per type later.
abstract class TransactionApplyHandler {
  Future<SyncPullApplyOutcome> applyCreate(
    TransactionAggregate aggregate,
    DatabaseExecutor txn,
  );

  Future<SyncPullApplyOutcome> applyUpdate(
    TransactionAggregate aggregate,
    DatabaseExecutor txn,
  );

  Future<SyncPullApplyOutcome> applyPost(
    TransactionAggregate aggregate,
    DatabaseExecutor txn,
  );

  Future<SyncPullApplyOutcome> applyCancel(
    TransactionAggregate aggregate,
    DatabaseExecutor txn,
  );

  Future<SyncPullApplyOutcome> applyFromChangelog(
    TransactionOperation operation,
    SyncChangelogEntry entry,
    TransactionAggregate aggregate,
    DatabaseExecutor txn,
  ) {
    switch (operation) {
      case TransactionOperation.create:
        return applyCreate(aggregate, txn);
      case TransactionOperation.update:
        return applyUpdate(aggregate, txn);
      case TransactionOperation.post:
        return applyPost(aggregate, txn);
      case TransactionOperation.cancel:
        return applyCancel(aggregate, txn);
      case TransactionOperation.voidOp:
        return applyVoid(aggregate, txn);
    }
  }

  /// Posted document void (reverse effects). Default: treat like cancel.
  Future<SyncPullApplyOutcome> applyVoid(
    TransactionAggregate aggregate,
    DatabaseExecutor txn,
  ) {
    return applyCancel(aggregate, txn);
  }
}

/// No-op handler for framework tests and placeholder registration.
class NoOpTransactionApplyHandler extends TransactionApplyHandler {
  @override
  Future<SyncPullApplyOutcome> applyCancel(
    TransactionAggregate aggregate,
    DatabaseExecutor txn,
  ) async {
    return SyncPullApplyOutcome.applied;
  }

  @override
  Future<SyncPullApplyOutcome> applyCreate(
    TransactionAggregate aggregate,
    DatabaseExecutor txn,
  ) async {
    return SyncPullApplyOutcome.applied;
  }

  @override
  Future<SyncPullApplyOutcome> applyPost(
    TransactionAggregate aggregate,
    DatabaseExecutor txn,
  ) async {
    return SyncPullApplyOutcome.applied;
  }

  @override
  Future<SyncPullApplyOutcome> applyUpdate(
    TransactionAggregate aggregate,
    DatabaseExecutor txn,
  ) async {
    return SyncPullApplyOutcome.applied;
  }

  @override
  Future<SyncPullApplyOutcome> applyVoid(
    TransactionAggregate aggregate,
    DatabaseExecutor txn,
  ) async {
    return SyncPullApplyOutcome.applied;
  }
}
