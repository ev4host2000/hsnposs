/// استجابة GET `/sync/pull/snapshot` — catalog scope.
class CatalogSnapshotResponse {
  const CatalogSnapshotResponse({
    required this.entityScope,
    required this.products,
    required this.customers,
    required this.suppliers,
    required this.snapshotSequence,
    required this.generatedAt,
  });

  factory CatalogSnapshotResponse.fromJson(Object? json) {
    if (json is! Map) {
      return const CatalogSnapshotResponse(
        entityScope: 'catalog',
        products: [],
        customers: [],
        suppliers: [],
        snapshotSequence: 0,
        generatedAt: '',
      );
    }
    final map = Map<String, dynamic>.from(json);

    return CatalogSnapshotResponse(
      entityScope: (map['entity_scope'] ?? 'catalog').toString(),
      products: _parseList(map['products']),
      customers: _parseList(map['customers']),
      suppliers: _parseList(map['suppliers']),
      snapshotSequence: _asInt(map['snapshot_sequence']),
      generatedAt: (map['generated_at'] ?? '').toString(),
    );
  }

  final String entityScope;
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> customers;
  final List<Map<String, dynamic>> suppliers;
  final int snapshotSequence;
  final String generatedAt;

  Map<String, dynamic> toJson() => {
        'entity_scope': entityScope,
        'products': products,
        'customers': customers,
        'suppliers': suppliers,
        'snapshot_sequence': snapshotSequence,
        'generated_at': generatedAt,
      };
}

List<Map<String, dynamic>> _parseList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
