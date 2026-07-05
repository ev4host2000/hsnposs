/// مدخل delta من `sync_changelog` — pull catalog scope.
class SyncChangelogEntry {
  const SyncChangelogEntry({
    required this.sequence,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payloadJson,
    required this.rowVersion,
    this.originDeviceId,
    this.occurredAt,
  });

  factory SyncChangelogEntry.fromJson(Map<String, dynamic> json) {
    final payload = json['payload_json'];
    return SyncChangelogEntry(
      sequence: _asInt(json['sequence']),
      entityType: (json['entity_type'] ?? '').toString(),
      entityId: (json['entity_id'] ?? '').toString(),
      operation: (json['operation'] ?? '').toString(),
      payloadJson: payload is Map<String, dynamic>
          ? payload
          : payload is Map
              ? Map<String, dynamic>.from(payload)
              : const <String, dynamic>{},
      rowVersion: _asInt(json['row_version']),
      originDeviceId: _optionalString(json['origin_device_id']),
      occurredAt: _optionalString(json['occurred_at']),
    );
  }

  final int sequence;
  final String entityType;
  final String entityId;
  final String operation;
  final Map<String, dynamic> payloadJson;
  final int rowVersion;
  final String? originDeviceId;
  final String? occurredAt;

  Map<String, dynamic> toJson() => {
        'sequence': sequence,
        'entity_type': entityType,
        'entity_id': entityId,
        'operation': operation,
        'payload_json': payloadJson,
        'row_version': rowVersion,
        if (originDeviceId != null) 'origin_device_id': originDeviceId,
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
