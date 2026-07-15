import 'package:mizapos_desktop/services/cloud/sync/models/sync_changelog_entry.dart';

/// Pull response for catalog entity sync endpoints.
class CatalogPullResponse {
  const CatalogPullResponse({
    required this.companyId,
    required this.branchId,
    required this.entityScope,
    required this.entries,
  });

  factory CatalogPullResponse.fromJson(Object? json) {
    if (json is! Map) {
      return const CatalogPullResponse(
        companyId: '',
        branchId: '',
        entityScope: '',
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

    return CatalogPullResponse(
      companyId: (map['company_id'] ?? '').toString(),
      branchId: (map['branch_id'] ?? '').toString(),
      entityScope: (map['entity_scope'] ?? '').toString(),
      entries: entries,
    );
  }

  final String companyId;
  final String branchId;
  final String entityScope;
  final List<SyncChangelogEntry> entries;
}
