import 'package:mizapos_mobile/services/cloud/sync/models/sync_changelog_entry.dart';

/// Result of applying a single pulled changelog entry locally.
enum SyncPullApplyOutcome {
  applied,
  deferred,
  failed,
}

/// Thrown inside a pull transaction to trigger full rollback.
class SyncPullApplyException implements Exception {
  SyncPullApplyException(this.code, {this.entry});

  final String code;
  final SyncChangelogEntry? entry;

  @override
  String toString() => 'SyncPullApplyException($code)';
}
