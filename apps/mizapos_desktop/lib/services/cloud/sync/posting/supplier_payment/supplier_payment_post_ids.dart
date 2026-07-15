import 'package:uuid/uuid.dart';

/// Deterministic UUIDs for idempotent supplier-payment post effects.
class SupplierPaymentPostIds {
  SupplierPaymentPostIds._();

  static const _namespace = '6ba7b810-9dad-11d1-80b4-00c04fd430cb';

  static String cashTransactionId(String paymentId) {
    return const Uuid().v5(_namespace, 'sp:$paymentId:cash');
  }

  static String accountingEntryId(String paymentId) {
    return const Uuid().v5(_namespace, 'sp:$paymentId:ledger');
  }
}
