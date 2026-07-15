import 'package:mizapos_desktop/services/cloud/sync/models/sync_changelog_entry.dart';
import 'package:mizapos_desktop/services/cloud/sync/sync_pull_apply.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/models/transaction_operation.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/models/transaction_type_definition.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/models/transaction_validation_result.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/transaction_apply_handler.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/transaction_payload_serializer.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/transaction_validator.dart';
import 'package:sqflite/sqflite.dart';

/// Routes pull/push operations to the registered apply handler — ADR-TX-002.
class TransactionOperationDispatcher {
  TransactionOperationDispatcher({
    TransactionValidator? validator,
    TransactionPayloadSerializer? serializer,
  })  : _validator = validator ?? const TransactionValidator(),
        _serializer = serializer ?? const TransactionPayloadSerializer();

  final TransactionValidator _validator;
  final TransactionPayloadSerializer _serializer;

  TransactionValidationResult validateBeforeDispatch({
    required String operation,
    required SyncChangelogEntry entry,
    required TransactionTypeDefinition type,
  }) {
    final op = TransactionOperation.parse(operation);
    if (op == null) {
      return TransactionValidationResult.invalid(
        'unsupported_operation',
        operation,
      );
    }
    if (entry.entityType != type.entityType) {
      return TransactionValidationResult.invalid(
        'entity_type_mismatch',
        entry.entityType,
      );
    }

    try {
      final aggregate = _serializer.deserializeEnvelope(entry.payloadJson);
      return _validator.validateAggregateHeader(
        aggregate.header,
        expectedEntityType: type.entityType,
        expectedScopeEntityId: entry.entityId,
      );
    } on FormatException catch (e) {
      return TransactionValidationResult.invalid('invalid_payload', e.message);
    }
  }

  Future<SyncPullApplyOutcome> dispatchPullApply({
    required SyncChangelogEntry entry,
    required TransactionTypeDefinition type,
    required DatabaseExecutor txn,
  }) async {
    final validation = validateBeforeDispatch(
      operation: entry.operation,
      entry: entry,
      type: type,
    );
    if (!validation.ok) {
      return SyncPullApplyOutcome.failed;
    }

    final operation = TransactionOperation.parseRequired(entry.operation);
    final aggregate = _serializer.deserializeEnvelope(entry.payloadJson);

    return type.applyHandler.applyFromChangelog(
      operation,
      entry,
      aggregate,
      txn,
    );
  }
}
