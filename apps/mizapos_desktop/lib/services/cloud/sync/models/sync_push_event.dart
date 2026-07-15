/// Ø­Ø¯Ø« outbox ÙˆØ§Ø­Ø¯ Ø¶Ù…Ù† batch push â€” catalog entity types ÙÙ‚Ø·.
///
/// Update Contract v2 optional fields (Products M1 Dual-mode):
/// [changedFields], [baseRowVersion], [operationId], [dictionaryVersion], [contractVersion].
class SyncPushEvent {
  const SyncPushEvent({
    required this.outboxId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payloadJson,
    required this.clientRowVersion,
    this.idempotencyKey,
    this.occurredAt,
    this.changedFields,
    this.baseRowVersion,
    this.operationId,
    this.dictionaryVersion,
    this.contractVersion,
  });

  factory SyncPushEvent.fromJson(Map<String, dynamic> json) {
    final payload = json['payload_json'];
    final changed = json['changed_fields'] ??
        (payload is Map ? payload['changed_fields'] : null);
    return SyncPushEvent(
      outboxId: (json['outbox_id'] ?? '').toString(),
      entityType: (json['entity_type'] ?? '').toString(),
      entityId: (json['entity_id'] ?? '').toString(),
      operation: (json['operation'] ?? '').toString(),
      payloadJson: payload is Map<String, dynamic>
          ? payload
          : payload is Map
              ? Map<String, dynamic>.from(payload)
              : const <String, dynamic>{},
      clientRowVersion: _asInt(json['client_row_version']),
      idempotencyKey: _optionalString(json['idempotency_key']),
      occurredAt: _optionalString(json['occurred_at']),
      changedFields: _asMap(changed),
      baseRowVersion: _optionalInt(
        json['base_row_version'] ??
            (payload is Map ? payload['base_row_version'] : null),
      ),
      operationId: _optionalString(
        json['operation_id'] ??
            (payload is Map ? payload['operation_id'] : null),
      ),
      dictionaryVersion: _optionalString(
        json['dictionary_version'] ??
            (payload is Map ? payload['dictionary_version'] : null),
      ),
      contractVersion: _optionalInt(
        json['contract_version'] ??
            (payload is Map ? payload['contract_version'] : null),
      ),
    );
  }

  final String outboxId;
  final String entityType;
  final String entityId;
  final String operation;
  final Map<String, dynamic> payloadJson;
  final int clientRowVersion;
  final String? idempotencyKey;
  final String? occurredAt;
  final Map<String, dynamic>? changedFields;
  final int? baseRowVersion;
  final String? operationId;
  final String? dictionaryVersion;
  final int? contractVersion;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'outbox_id': outboxId,
      'entity_type': entityType,
      'entity_id': entityId,
      'operation': operation,
      'payload_json': payloadJson,
      'client_row_version': clientRowVersion,
      if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      if (occurredAt != null) 'occurred_at': occurredAt,
    };

    // Native patch: emit Update Contract v2 fields at event top-level.
    if (operation == 'patch' || changedFields != null) {
      final changed = changedFields ??
          (payloadJson['changed_fields'] is Map
              ? Map<String, dynamic>.from(
                  payloadJson['changed_fields'] as Map,
                )
              : null);
      if (changed != null) {
        json['changed_fields'] = changed;
      }
      final base = baseRowVersion ??
          _optionalInt(payloadJson['base_row_version']);
      if (base != null) {
        json['base_row_version'] = base;
      }
      final opId = operationId ??
          _optionalString(payloadJson['operation_id']) ??
          outboxId;
      json['operation_id'] = opId;
      final dict = dictionaryVersion ??
          _optionalString(payloadJson['dictionary_version']);
      if (dict != null) {
        json['dictionary_version'] = dict;
      }
      final cv = contractVersion ??
          _optionalInt(payloadJson['contract_version']) ??
          2;
      json['contract_version'] = cv;
    }

    return json;
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _optionalInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  final s = value.toString().trim();
  return s.isEmpty ? null : s;
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}
