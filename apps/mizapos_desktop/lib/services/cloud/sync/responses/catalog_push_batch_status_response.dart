/// استجابة GET `/sync/push/{batch_id}`.
class CatalogPushBatchStatusResponse {
  const CatalogPushBatchStatusResponse({
    required this.batchId,
    required this.status,
    required this.applied,
    required this.rejected,
    required this.conflicts,
    this.processedAt,
    this.changelogSequences = const [],
  });

  factory CatalogPushBatchStatusResponse.fromJson(Object? json) {
    if (json is! Map) {
      return const CatalogPushBatchStatusResponse(
        batchId: '',
        status: '',
        applied: 0,
        rejected: 0,
        conflicts: 0,
      );
    }
    final map = Map<String, dynamic>.from(json);
    final rawSequences = map['changelog_sequences'];
    final sequences = <int>[];
    if (rawSequences is List) {
      for (final item in rawSequences) {
        sequences.add(_asInt(item));
      }
    }

    return CatalogPushBatchStatusResponse(
      batchId: (map['batch_id'] ?? '').toString(),
      status: (map['status'] ?? '').toString(),
      applied: _asInt(map['applied']),
      rejected: _asInt(map['rejected']),
      conflicts: _asInt(map['conflicts']),
      processedAt: _optionalString(map['processed_at']),
      changelogSequences: sequences,
    );
  }

  final String batchId;
  final String status;
  final int applied;
  final int rejected;
  final int conflicts;
  final String? processedAt;
  final List<int> changelogSequences;

  Map<String, dynamic> toJson() => {
        'batch_id': batchId,
        'status': status,
        'applied': applied,
        'rejected': rejected,
        'conflicts': conflicts,
        if (processedAt != null) 'processed_at': processedAt,
        if (changelogSequences.isNotEmpty)
          'changelog_sequences': changelogSequences,
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
