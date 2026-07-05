/// حدث outbox واحد ضمن batch push — catalog entity types فقط.
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
  });

  factory SyncPushEvent.fromJson(Map<String, dynamic> json) {
    final payload = json['payload_json'];
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

  Map<String, dynamic> toJson() => {
        'outbox_id': outboxId,
        'entity_type': entityType,
        'entity_id': entityId,
        'operation': operation,
        'payload_json': payloadJson,
        'client_row_version': clientRowVersion,
        if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
        if (occurredAt != null) 'occurred_at': occurredAt,
      };
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  final s = value.toString().trim();
  return s.isEmpty ? null : s;
}
