import 'package:uuid/uuid.dart';

/// Deterministic UUIDs for idempotent purchase-return post effects.
class PurchaseReturnPostIds {
  PurchaseReturnPostIds._();

  static const _namespace = '6ba7b810-9dad-11d1-80b4-00c04fd430c9';

  static String stockMovementId(String returnId, String lineId) {
    return const Uuid().v5(_namespace, 'pr:$returnId:stock:$lineId');
  }

  static String accountingEntryId(String returnId, String role) {
    return const Uuid().v5(_namespace, 'pr:$returnId:acct:$role');
  }

  /// Pseudo supplier bucket for purchase expense credits (partner_ledger v1).
  static String purchaseExpensePartnerId(String organizationId) {
    return const Uuid().v5(_namespace, 'pr:purchase-expense:$organizationId');
  }

  /// Pseudo supplier bucket for input tax credits (partner_ledger v1).
  static String taxInputPartnerId(String organizationId) {
    return const Uuid().v5(_namespace, 'pr:tax-input:$organizationId');
  }
}
