import 'package:mizapos_mobile/services/cloud/sync/transactions/models/transaction_aggregate.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/transaction_sync_constants.dart';

/// Serializes aggregate payloads for outbox/changelog — ADR-TX-011.
class TransactionPayloadSerializer {
  const TransactionPayloadSerializer();

  Map<String, dynamic> serialize(TransactionAggregate aggregate) {
    return aggregate.toJson();
  }

  MapTransactionAggregate deserialize(Map<String, dynamic> json) {
    final headerRaw = json['header'];
    final linesRaw = json['lines'];
    final metadataRaw = json['metadata'];

    if (headerRaw is! Map) {
      throw FormatException('Transaction payload missing header');
    }

    final header = Map<String, dynamic>.from(headerRaw);
    final lines = <Map<String, dynamic>>[];
    if (linesRaw is List) {
      for (final item in linesRaw) {
        if (item is Map) {
          lines.add(Map<String, dynamic>.from(item));
        }
      }
    }

    final metadata = metadataRaw is Map
        ? Map<String, dynamic>.from(metadataRaw)
        : <String, dynamic>{};

    return MapTransactionAggregate.fromParts(
      header: header,
      lines: lines,
      metadata: metadata,
    );
  }

  Map<String, dynamic> envelope({
    required TransactionAggregate aggregate,
    required String operation,
    required int clientRowVersion,
    String? idempotencyKey,
  }) {
    return {
      'payload_schema_version': TransactionSyncConstants.payloadSchemaVersion,
      'operation': operation,
      'client_row_version': clientRowVersion,
      if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      'aggregate': serialize(aggregate),
    };
  }

  MapTransactionAggregate deserializeEnvelope(Map<String, dynamic> envelope) {
    final aggregateRaw = envelope['aggregate'];
    if (aggregateRaw is Map<String, dynamic>) {
      return deserialize(aggregateRaw);
    }
    if (aggregateRaw is Map) {
      return deserialize(Map<String, dynamic>.from(aggregateRaw));
    }
    return deserialize(envelope);
  }
}
