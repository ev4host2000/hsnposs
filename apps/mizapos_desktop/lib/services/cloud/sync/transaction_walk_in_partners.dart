import 'package:mizapos_desktop/services/cloud/sync/catalog_sync_outbox_writer.dart';
import 'package:mizapos_desktop/services/cloud/sync/partner_sync_outbox_writer.dart';
import 'package:mizapos_desktop/services/cloud/sync/partners_sync_constants.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Deterministic walk-in partner rows required for transaction post validation.
class TransactionWalkInPartners {
  TransactionWalkInPartners._();

  static const _salesNamespace = '6ba7b810-9dad-11d1-80b4-00c04fd430c8';
  static const _purchaseNamespace = '6ba7b810-9dad-11d1-80b4-00c04fd430c9';
  static const _walkInCustomerName = 'عميل نقدي';

  static String walkInCustomerId(String organizationId) {
    return const Uuid()
        .v5(_salesNamespace, 'si:walk-in-customer:$organizationId');
  }

  static String walkInSupplierId(String organizationId) {
    return const Uuid()
        .v5(_purchaseNamespace, 'pi:walk-in-supplier:$organizationId');
  }

  static Future<String> ensureCustomer(
    DatabaseExecutor txn, {
    required String organizationId,
    required String branchId,
  }) async {
    final id = walkInCustomerId(organizationId);
    final rows = await txn.query(
      'customers',
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    var inserted = false;
    if (rows.isEmpty) {
      await txn.insert('customers', {
        'id': id,
        'organizationId': organizationId,
        'branchId': branchId,
        'name': _walkInCustomerName,
        'creditLimit': 0,
        'createdAt': DateTime.now().toIso8601String(),
      });
      inserted = true;
    }
    await _enqueueCustomerCreateIfNeeded(
      txn,
      entityId: id,
      organizationId: organizationId,
      branchId: branchId,
      force: inserted,
    );
    return id;
  }

  static Future<String> ensureSupplier(
    DatabaseExecutor txn, {
    required String organizationId,
    required String branchId,
  }) async {
    final id = walkInSupplierId(organizationId);
    final rows = await txn.query(
      'suppliers',
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      await txn.insert('suppliers', {
        'id': id,
        'organizationId': organizationId,
        'branchId': branchId,
        'name': 'مورد نقدي',
        'creditLimit': 0,
        'createdAt': DateTime.now().toIso8601String(),
      });
    }
    return id;
  }

  /// Same path as normal partner create ([PartnerSyncOutboxWriter.record]).
  ///
  /// [force] = true after a fresh INSERT. When the row already exists (e.g. legacy
  /// Walk-in without outbox), enqueue only if no customer outbox row exists.
  static Future<void> _enqueueCustomerCreateIfNeeded(
    DatabaseExecutor txn, {
    required String entityId,
    required String organizationId,
    required String branchId,
    required bool force,
  }) async {
    if (!force) {
      final existing = await txn.query(
        'sync_outbox',
        columns: const ['id'],
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: [PartnersSyncConstants.entityTypeCustomer, entityId],
        limit: 1,
      );
      if (existing.isNotEmpty) return;
    }

    await PartnerSyncOutboxWriter.record(
      entityType: PartnersSyncConstants.entityTypeCustomer,
      operation: 'create',
      entityId: entityId,
      organizationId: organizationId,
      branchId: branchId,
      executor: txn,
      storage:
          PartnerSyncOutboxWriter.storage ?? CatalogSyncOutboxWriter.storage,
      payload: partnerEntityCloudPayload(
        id: entityId,
        organizationId: organizationId,
        branchId: branchId,
        name: _walkInCustomerName,
        creditLimit: 0,
      ),
    );
  }

  static String resolveCustomerId(String? customerId, String organizationId) {
    final trimmed = customerId?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    return walkInCustomerId(organizationId);
  }

  static String resolveSupplierId(String? supplierId, String organizationId) {
    final trimmed = supplierId?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    return walkInSupplierId(organizationId);
  }
}
