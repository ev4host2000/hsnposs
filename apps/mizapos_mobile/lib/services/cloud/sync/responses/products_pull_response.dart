import 'package:mizapos_mobile/services/cloud/sync/models/sync_changelog_entry.dart';

/// استجابة GET `/sync/pull/products`.
class ProductsPullResponse {
  const ProductsPullResponse({
    required this.companyId,
    required this.branchId,
    required this.entityScope,
    required this.entries,
  });

  factory ProductsPullResponse.fromJson(Object? json) {
    if (json is! Map) {
      return const ProductsPullResponse(
        companyId: '',
        branchId: '',
        entityScope: 'products',
        entries: [],
      );
    }
    final map = Map<String, dynamic>.from(json);
    final rawEntries = map['entries'];
    final entries = <SyncChangelogEntry>[];
    if (rawEntries is List) {
      for (final item in rawEntries) {
        if (item is Map<String, dynamic>) {
          entries.add(SyncChangelogEntry.fromJson(item));
        } else if (item is Map) {
          entries.add(
            SyncChangelogEntry.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    return ProductsPullResponse(
      companyId: (map['company_id'] ?? '').toString(),
      branchId: (map['branch_id'] ?? '').toString(),
      entityScope: (map['entity_scope'] ?? 'products').toString(),
      entries: entries,
    );
  }

  final String companyId;
  final String branchId;
  final String entityScope;
  final List<SyncChangelogEntry> entries;
}
