import 'package:uuid/uuid.dart';

/// Deterministic UUIDs for idempotent sales-return post effects.
class SalesReturnPostIds {
  SalesReturnPostIds._();

  static const _namespace = '6ba7b810-9dad-11d1-80b4-00c04fd430c8';

  static String stockMovementId(String returnId, String lineId) {
    return const Uuid().v5(_namespace, 'sr:$returnId:stock:$lineId');
  }

  static String accountingEntryId(String returnId, String role) {
    return const Uuid().v5(_namespace, 'sr:$returnId:acct:$role');
  }

  /// Pseudo supplier bucket for sales revenue debits (partner_ledger v1).
  static String salesRevenuePartnerId(String organizationId) {
    return const Uuid().v5(_namespace, 'sr:sales-revenue:$organizationId');
  }

  /// Pseudo supplier bucket for tax payable debits (partner_ledger v1).
  static String taxPayablePartnerId(String organizationId) {
    return const Uuid().v5(_namespace, 'sr:tax-payable:$organizationId');
  }
}
