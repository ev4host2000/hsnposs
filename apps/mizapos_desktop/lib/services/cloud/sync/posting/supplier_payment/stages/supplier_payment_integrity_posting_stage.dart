import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_integrity_exception.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_stage_result.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/shared/payment_integrity_verifier.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/supplier_payment/supplier_payment_post_effects.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/models/transaction_aggregate.dart';

/// Pre-finalize integrity checks — amount, cash, ledger, no inventory.
class SupplierPaymentIntegrityPostingStage extends PostingStage {
  SupplierPaymentIntegrityPostingStage();

  @override
  String get stageId => 'integrity';

  @override
  Future<PostingStageResult> run(PostingContext context) async {
    try {
      final cash = context.stageData['cash'];
      final accounting = context.stageData['accounting'];
      if (cash is! SupplierPaymentCashEffect ||
          accounting is! SupplierPaymentAccountingEffect) {
        throw const PostingIntegrityException(
          'Cash and accounting effects must be planned before integrity',
        );
      }

      await PaymentIntegrityVerifier.verify(
        context: context,
        referenceType: 'supplier_payment',
        loadPayment: (txn, id) async {
          final rows = await txn.query(
            'supplierPayments',
            where: 'id = ?',
            whereArgs: [id],
            limit: 1,
          );
          return rows.isEmpty ? null : rows.first;
        },
        statusColumn: 'paymentStatus',
        amount: _headerAmount(context),
        cashTransactionType: 'out',
        cash: PaymentCashEffectView(
          cashTransactionId: cash.cashTransactionId,
          transactionType: cash.transactionType,
          amount: cash.amount,
        ),
        accounting: PaymentAccountingEffectView(
          entryId: accounting.entryId,
          amountSigned: accounting.amountSigned,
        ),
      );
    } on PostingIntegrityException catch (e) {
      return PostingStageResult.failure(code: e.code, message: e.message);
    }

    context.stageData['integrity_verified'] = true;
    return const PostingStageResult.proceed();
  }

  double _headerAmount(PostingContext context) {
    final extra = context.aggregate.header is MapTransactionHeader
        ? (context.aggregate.header as MapTransactionHeader).extra
        : const {};
    final value = extra['amount'];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
