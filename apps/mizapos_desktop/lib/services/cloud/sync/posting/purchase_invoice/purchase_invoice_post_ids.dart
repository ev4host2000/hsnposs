import 'package:uuid/uuid.dart';

/// Deterministic UUIDs for idempotent purchase-invoice post effects.
class PurchaseInvoicePostIds {
  PurchaseInvoicePostIds._();

  static const _namespace = '6ba7b810-9dad-11d1-80b4-00c04fd430c9';

  static String stockMovementId(String invoiceId, String lineId) {
    return const Uuid().v5(_namespace, 'pi:$invoiceId:stock:$lineId');
  }

  static String accountingEntryId(String invoiceId, String role) {
    return const Uuid().v5(_namespace, 'pi:$invoiceId:acct:$role');
  }

  /// Deterministic cash-box reverse for voided cash purchases.
  static String voidCashTransactionId(String invoiceId) {
    return const Uuid().v5(_namespace, 'pi:$invoiceId:void-cash');
  }

  /// Pseudo supplier bucket for purchase expense debits (partner_ledger v1).
  static String purchaseExpensePartnerId(String organizationId) {
    return const Uuid().v5(_namespace, 'pi:purchase-expense:$organizationId');
  }

  /// Pseudo supplier bucket for input tax debits (partner_ledger v1).
  static String taxInputPartnerId(String organizationId) {
    return const Uuid().v5(_namespace, 'pi:tax-input:$organizationId');
  }
}
