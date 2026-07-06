import 'package:uuid/uuid.dart';

/// Deterministic UUIDs for idempotent customer-payment post effects.
class CustomerPaymentPostIds {
  CustomerPaymentPostIds._();

  static const _namespace = '6ba7b810-9dad-11d1-80b4-00c04fd430ca';

  static String cashTransactionId(String paymentId) {
    return const Uuid().v5(_namespace, 'cp:$paymentId:cash');
  }

  static String accountingEntryId(String paymentId) {
    return const Uuid().v5(_namespace, 'cp:$paymentId:ledger');
  }
}
