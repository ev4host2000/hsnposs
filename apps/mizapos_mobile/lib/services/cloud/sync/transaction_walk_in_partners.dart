import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Deterministic walk-in partner rows required for transaction post validation.
class TransactionWalkInPartners {
  TransactionWalkInPartners._();

  static const _salesNamespace = '6ba7b810-9dad-11d1-80b4-00c04fd430c8';
  static const _purchaseNamespace = '6ba7b810-9dad-11d1-80b4-00c04fd430c9';

  static String walkInCustomerId(String organizationId) {
    return const Uuid().v5(_salesNamespace, 'si:walk-in-customer:$organizationId');
  }

  static String walkInSupplierId(String organizationId) {
    return const Uuid().v5(_purchaseNamespace, 'pi:walk-in-supplier:$organizationId');
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
    if (rows.isEmpty) {
      await txn.insert('customers', {
        'id': id,
        'organizationId': organizationId,
        'branchId': branchId,
        'name': 'عميل نقدي',
        'creditLimit': 0,
        'createdAt': DateTime.now().toIso8601String(),
      });
    }
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
