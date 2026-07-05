/// Push response for catalog entity sync endpoints.
class CatalogPushResponse {
  const CatalogPushResponse({
    required this.batchId,
    required this.status,
    required this.accepted,
    required this.duplicates,
  });

  factory CatalogPushResponse.fromJson(Object? json) {
    if (json is! Map) {
      return const CatalogPushResponse(
        batchId: '',
        status: '',
        accepted: 0,
        duplicates: 0,
      );
    }
    final map = Map<String, dynamic>.from(json);
    return CatalogPushResponse(
      batchId: (map['batch_id'] ?? '').toString(),
      status: (map['status'] ?? '').toString(),
      accepted: (map['accepted'] as num?)?.toInt() ?? 0,
      duplicates: (map['duplicates'] as num?)?.toInt() ?? 0,
    );
  }

  final String batchId;
  final String status;
  final int accepted;
  final int duplicates;

  bool get ok => status == 'accepted' || status == 'duplicate';
}
