import 'package:sqflite/sqflite.dart';

/// Clears tenant-scoped pull/push cursors when the active organization changes.
///
/// Binding markers are retained only as account-switch history. Their cursor
/// fields are reset and are never consumed by sync workers.
abstract final class TenantSyncCursorReset {
  static const String bindingScope = 'cloud_tenant_bind';

  static Future<void> forOrganizationChange(
    DatabaseExecutor db, {
    required String fromOrganizationId,
    required String toOrganizationId,
  }) async {
    final from = fromOrganizationId.trim();
    final to = toOrganizationId.trim();
    if (from.isEmpty || to.isEmpty || from == to) return;

    // Remove every operational cursor for both sides of the switch. Clearing
    // the destination too guarantees that returning to a previously used
    // tenant starts from sequence zero instead of reusing its stale cursor.
    await db.delete(
      'sync_meta',
      where: 'scope_key != ? AND organization_id IN (?, ?)',
      whereArgs: [bindingScope, from, to],
    );

    // Keep bind history for account-switch confirmation, but make it
    // impossible for those rows to carry local or remote cursor state.
    await db.update(
      'sync_meta',
      {
        'last_pulled_sequence': 0,
        'last_pushed_sequence': 0,
        'last_pulled_at': null,
        'last_pushed_at': null,
        'cloud_version_catalog': 0,
        'cloud_version_invoices': 0,
        'cloud_version_users': 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'scope_key = ? AND organization_id IN (?, ?)',
      whereArgs: [bindingScope, from, to],
    );

    // Team-user sync uses a remote version token outside sync_meta.
    if (await _tableExists(db, 'team_users_sync_meta')) {
      await db.delete(
        'team_users_sync_meta',
        where: 'organization_id IN (?, ?)',
        whereArgs: [from, to],
      );
    }

    // Deferred entries belong to the sequence that produced them. They cannot
    // be carried into a full replay for another tenant.
    if (await _tableExists(db, 'sync_deferred_pull')) {
      await db.delete(
        'sync_deferred_pull',
        where: 'organization_id IN (?, ?)',
        whereArgs: [from, to],
      );
    }
  }

  static Future<bool> _tableExists(
    DatabaseExecutor db,
    String tableName,
  ) async {
    final rows = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
      [tableName],
    );
    return rows.isNotEmpty;
  }
}
