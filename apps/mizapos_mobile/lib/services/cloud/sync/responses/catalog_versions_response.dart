/// إصدار catalog ضمن GET `/sync/versions`.
class CatalogScopeVersion {
  const CatalogScopeVersion({
    required this.version,
    required this.lastSequence,
  });

  factory CatalogScopeVersion.fromJson(Object? json) {
    if (json is! Map) {
      return const CatalogScopeVersion(version: 0, lastSequence: 0);
    }
    final map = Map<String, dynamic>.from(json);
    return CatalogScopeVersion(
      version: _asInt(map['version']),
      lastSequence: _asInt(map['last_sequence']),
    );
  }

  final int version;
  final int lastSequence;

  Map<String, dynamic> toJson() => {
        'version': version,
        'last_sequence': lastSequence,
      };
}

/// استجابة GET `/sync/versions` — يُستخرَج منها catalog فقط.
class CatalogVersionsResponse {
  const CatalogVersionsResponse({
    required this.companyId,
    required this.branchId,
    required this.catalog,
    required this.serverTime,
  });

  factory CatalogVersionsResponse.fromJson(Object? json) {
    if (json is! Map) {
      return const CatalogVersionsResponse(
        companyId: '',
        branchId: '',
        catalog: CatalogScopeVersion(version: 0, lastSequence: 0),
        serverTime: '',
      );
    }
    final map = Map<String, dynamic>.from(json);
    final versions = map['versions'];
    CatalogScopeVersion catalog = const CatalogScopeVersion(
      version: 0,
      lastSequence: 0,
    );
    if (versions is Map) {
      catalog = CatalogScopeVersion.fromJson(versions['catalog']);
    }

    return CatalogVersionsResponse(
      companyId: (map['company_id'] ?? '').toString(),
      branchId: (map['branch_id'] ?? '').toString(),
      catalog: catalog,
      serverTime: (map['server_time'] ?? '').toString(),
    );
  }

  final String companyId;
  final String branchId;
  final CatalogScopeVersion catalog;
  final String serverTime;

  Map<String, dynamic> toJson() => {
        'company_id': companyId,
        'branch_id': branchId,
        'versions': {'catalog': catalog.toJson()},
        'server_time': serverTime,
      };
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
