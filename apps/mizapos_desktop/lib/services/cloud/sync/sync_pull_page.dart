import 'package:mizapos_desktop/services/cloud/sync/models/sync_changelog_entry.dart';

/// One page of pull results from the cloud API.
class SyncPullPage {
  const SyncPullPage({
    required this.entries,
    required this.lastSequence,
    required this.hasMore,
  });

  final List<SyncChangelogEntry> entries;
  final int lastSequence;
  final bool hasMore;
}

bool readHasMore(Map<String, dynamic> meta) {
  final raw = meta['has_more'];
  if (raw is bool) return raw;
  if (raw is num) return raw != 0;
  return raw == true || raw == 1 || raw == '1' || raw == 't';
}

int readLastSequence(int sinceSequence, Map<String, dynamic> meta) {
  final fromMeta = meta['last_sequence'];
  if (fromMeta is int) return fromMeta;
  if (fromMeta is num) return fromMeta.toInt();
  return int.tryParse(fromMeta?.toString() ?? '') ?? sinceSequence;
}
