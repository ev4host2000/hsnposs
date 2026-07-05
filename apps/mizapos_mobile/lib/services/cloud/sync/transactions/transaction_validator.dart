import 'package:mizapos_mobile/services/cloud/sync/transactions/models/transaction_aggregate.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/models/transaction_operation.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/models/transaction_validation_result.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/transaction_payload_serializer.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/transaction_sync_constants.dart';

/// Framework validation — versions, idempotency, operations — ADR-TX-004/008.
class TransactionValidator {
  const TransactionValidator();

  TransactionValidationResult validateOperation(String operation) {
    if (!TransactionSyncConstants.supportedOperations.contains(operation)) {
      return TransactionValidationResult.invalid(
        'unsupported_operation',
        'Operation $operation is not supported',
      );
    }
    return const TransactionValidationResult.valid();
  }

  TransactionValidationResult validateOperationEnum(TransactionOperation operation) {
    return validateOperation(operation.wireValue);
  }

  TransactionValidationResult validateIdempotencyKey(String? key) {
    if (key == null || key.trim().isEmpty) {
      return TransactionValidationResult.invalid(
        'missing_idempotency_key',
        'Idempotency key is required',
      );
    }
    final parts = key.split(':');
    if (parts.length < 3) {
      return TransactionValidationResult.invalid(
        'invalid_idempotency_key',
        'Expected device:entity:operation[:outbox] format',
      );
    }
    return const TransactionValidationResult.valid();
  }

  TransactionValidationResult validateRowVersion({
    required int incoming,
    int? local,
    bool allowEqual = false,
  }) {
    if (incoming < 1) {
      return TransactionValidationResult.invalid(
        'invalid_row_version',
        'row_version must be >= 1',
      );
    }
    if (local == null) return const TransactionValidationResult.valid();
    if (allowEqual) {
      if (incoming < local) {
        return TransactionValidationResult.invalid(
          'stale_row_version',
          'Incoming row_version $incoming < local $local',
        );
      }
    } else if (incoming <= local) {
      return TransactionValidationResult.invalid(
        'stale_row_version',
        'Incoming row_version must exceed local $local',
      );
    }
    return const TransactionValidationResult.valid();
  }

  TransactionValidationResult validateTransactionVersion({
    required int incoming,
    int? local,
    required TransactionOperation operation,
  }) {
    if (incoming < 0) {
      return TransactionValidationResult.invalid(
        'invalid_transaction_version',
        'transaction_version must be >= 0',
      );
    }
    if (local == null) return const TransactionValidationResult.valid();

    switch (operation) {
      case TransactionOperation.create:
        if (incoming != 0 && incoming != local) {
          return TransactionValidationResult.invalid(
            'create_version_conflict',
            'Create expects transaction_version 0',
          );
        }
      case TransactionOperation.update:
        if (incoming < local) {
          return TransactionValidationResult.invalid(
            'stale_transaction_version',
            'Draft update must not regress transaction_version',
          );
        }
      case TransactionOperation.post:
      case TransactionOperation.cancel:
        if (incoming <= local) {
          return TransactionValidationResult.invalid(
            'stale_transaction_version',
            'Post/cancel requires higher transaction_version',
          );
        }
    }
    return const TransactionValidationResult.valid();
  }

  TransactionValidationResult validateAggregateHeader(
    TransactionAggregateHeader header, {
    required String expectedEntityType,
    required String expectedScopeEntityId,
  }) {
    if (header.id.isEmpty) {
      return TransactionValidationResult.invalid('missing_id', 'Header id required');
    }
    if (header.id != expectedScopeEntityId) {
      return TransactionValidationResult.invalid(
        'entity_id_mismatch',
        'Header id must match entity_id',
      );
    }
    if (header.documentType.isEmpty) {
      return TransactionValidationResult.invalid(
        'missing_document_type',
        'document_type required',
      );
    }
    if (header.documentType != expectedEntityType) {
      return TransactionValidationResult.invalid(
        'document_type_mismatch',
        'document_type must match entity_type',
      );
    }
    final row = validateRowVersion(incoming: header.rowVersion);
    if (!row.ok) return row;
    return const TransactionValidationResult.valid();
  }

  TransactionValidationResult validatePushPayload({
    required String operation,
    required Map<String, dynamic> payloadJson,
    required String entityId,
    required String entityType,
    required String idempotencyKey,
    required int clientRowVersion,
    int? localTransactionVersion,
    int? localRowVersion,
  }) {
    final opResult = validateOperation(operation);
    if (!opResult.ok) return opResult;

    final idem = validateIdempotencyKey(idempotencyKey);
    if (!idem.ok) return idem;

    if (clientRowVersion < 1) {
      return TransactionValidationResult.invalid(
        'invalid_client_row_version',
        'client_row_version must be >= 1',
      );
    }

    final op = TransactionOperation.parseRequired(operation);
    try {
      final aggregate = const TransactionPayloadSerializer()
          .deserializeEnvelope(payloadJson);
      final headerCheck = validateAggregateHeader(
        aggregate.header,
        expectedEntityType: entityType,
        expectedScopeEntityId: entityId,
      );
      if (!headerCheck.ok) return headerCheck;

      final txnVer = validateTransactionVersion(
        incoming: aggregate.header.transactionVersion,
        local: localTransactionVersion,
        operation: op,
      );
      if (!txnVer.ok) return txnVer;

      final rowVer = validateRowVersion(
        incoming: aggregate.header.rowVersion,
        local: localRowVersion,
        allowEqual: op == TransactionOperation.update,
      );
      if (!rowVer.ok) return rowVer;
    } on FormatException catch (e) {
      return TransactionValidationResult.invalid('invalid_payload', e.message);
    }

    return const TransactionValidationResult.valid();
  }
}
