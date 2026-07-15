import 'package:uuid/uuid.dart';

/// Deterministic UUIDs for idempotent sales-invoice post effects.
class SalesInvoicePostIds {
  SalesInvoicePostIds._();

  static const _namespace = '6ba7b810-9dad-11d1-80b4-00c04fd430c8';

  static String stockMovementId(String invoiceId, String lineId) {
    return const Uuid().v5(_namespace, 'si:$invoiceId:stock:$lineId');
  }

  static String accountingEntryId(String invoiceId, String role) {
    return const Uuid().v5(_namespace, 'si:$invoiceId:acct:$role');
  }

  /// Deterministic cash-box reverse for voided cash sales.
  static String voidCashTransactionId(String invoiceId) {
    return const Uuid().v5(_namespace, 'si:$invoiceId:void-cash');
  }

  /// Pseudo supplier bucket for sales revenue credits (partner_ledger v1).
  static String salesRevenuePartnerId(String organizationId) {
    return const Uuid().v5(_namespace, 'si:sales-revenue:$organizationId');
  }

  /// Pseudo supplier bucket for tax payable credits (partner_ledger v1).
  static String taxPayablePartnerId(String organizationId) {
    return const Uuid().v5(_namespace, 'si:tax-payable:$organizationId');
  }
}
