import 'package:mizapos_desktop/services/cloud/sync/models/sync_push_rejected_event.dart';

/// ÙŠØ³ÙˆÙ‘ÙŠ ØµÙÙˆÙ outbox Ø¹Ù†Ø¯ ÙˆØ¬ÙˆØ¯ `rejected_events` ØµØ±ÙŠØ­Ø© Ù…Ù† Ø§Ù„Ø³Ø­Ø§Ø¨Ø©.
abstract final class SyncPushPartialSettler {
  /// ÙŠØ¹Ù„Ù‘Ù… Ø§Ù„Ù…Ø±ÙÙˆØ¶ failedØŒ ÙˆÙŠÙ‚Ø¨Ù„ Ø§Ù„Ø¨Ø§Ù‚ÙŠ synced Ø¥Ù† Ø·Ø§Ø¨Ù‚ Ø§Ù„Ø¹Ø¯Ø¯ØŒ ÙˆØ¥Ù„Ø§ ÙŠØ¹ÙŠØ¯Ù‡ pending.
  ///
  /// - `conflict` Ø¹Ù„Ù‰ `create` â†’ synced (Ø§Ù„Ù…Ø³ØªÙ†Ø¯ Ù…ÙˆØ¬ÙˆØ¯ Ù…Ø³Ø¨Ù‚Ø§Ù‹).
  /// - `version_conflict` â†’ failed + optional [onVersionConflict] rebuild hook.
  /// - `no_op` ÙƒØ±Ù…Ø² Ø±ÙØ¶ Ø¯ÙØ§Ø¹ÙŠ â†’ synced (Ø§Ù„Ø³Ø­Ø§Ø¨Ø© Ø¹Ø§Ø¯Ø©Ù‹ ØªØ¹ÙŠØ¯Ù‡ accepted).
  static Future<void> settle({
    required List<String> claimedIds,
    required List<SyncPushRejectedEvent> rejectedEvents,
    required int accepted,
    required int duplicates,
    required String batchId,
    required Future<void> Function(String outboxId, String error) markFailed,
    required Future<void> Function({
      required List<String> outboxIds,
      required String batchId,
    }) markSynced,
    required Future<void> Function(List<String> outboxIds) releaseClaims,
    Map<String, String>? operationByOutboxId,
    // Rebuild must run post-pull; do not wire on push settle.
    Future<void> Function(String outboxId)? onVersionConflict,
  }) async {
    if (claimedIds.isEmpty || rejectedEvents.isEmpty) return;

    final errorById = <String, String>{};
    for (final event in rejectedEvents) {
      if (event.outboxId.isEmpty) continue;
      errorById[event.outboxId] = event.errorCode;
    }
    if (errorById.isEmpty) return;

    final rejectedIds = <String>[];
    final syncedIds = <String>[];
    final versionConflictIds = <String>[];
    final otherIds = <String>[];
    for (final id in claimedIds) {
      if (!errorById.containsKey(id)) {
        otherIds.add(id);
        continue;
      }
      final code = errorById[id] ?? 'push_rejected';
      final op = operationByOutboxId?[id];
      if (code == 'conflict' && op == 'create') {
        syncedIds.add(id);
      } else if (code == 'no_op') {
        syncedIds.add(id);
      } else if (code == 'version_conflict') {
        versionConflictIds.add(id);
      } else {
        rejectedIds.add(id);
      }
    }

    for (final id in rejectedIds) {
      await markFailed(id, errorById[id] ?? 'push_rejected');
    }
    for (final id in versionConflictIds) {
      await markFailed(id, 'version_conflict');
      if (onVersionConflict != null) {
        await onVersionConflict(id);
      }
    }
    if (syncedIds.isNotEmpty) {
      await markSynced(outboxIds: syncedIds, batchId: batchId);
    }

    if (otherIds.isEmpty) return;

    final confirmed = accepted + duplicates;
    if (confirmed > 0 && otherIds.length == confirmed) {
      await markSynced(outboxIds: otherIds, batchId: batchId);
    } else {
      await releaseClaims(otherIds);
    }
  }
}
