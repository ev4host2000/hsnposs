import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_stage_result.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/supplier_payment/supplier_payment_post_db.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/supplier_payment/supplier_payment_post_effects.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/models/transaction_aggregate.dart';

/// Supplier-payment post validation — real DB checks, plans effects in stageData.
class SupplierPaymentValidationPostingStage extends PostingStage {
  SupplierPaymentValidationPostingStage();

  @override
  String get stageId => 'validation';

  static const _allowedPaymentMethods = {'cash', 'bank'};

  @override
  Future<PostingStageResult> run(PostingContext context) async {
    final header = context.aggregate.header;
    final paymentId = header.id;
    if (paymentId.isEmpty) {
      return const PostingStageResult.failure(
        code: 'missing_id',
        message: 'Header id is required for post',
      );
    }

    if (header.documentType != context.entityType) {
      return const PostingStageResult.failure(
        code: 'document_type_mismatch',
        message: 'document_type must be supplier_payment',
      );
    }

    final extra = header is MapTransactionHeader ? header.extra : const {};
    final supplierId = _optionalString(extra['supplier_id']);
    if (supplierId == null) {
      return const PostingStageResult.failure(
        code: 'missing_supplier',
        message: 'supplier_id is required for post',
      );
    }

    final amount = _asDouble(extra['amount']);
    if (amount <= 0) {
      return const PostingStageResult.failure(
        code: 'invalid_amount',
        message: 'Payment amount must be > 0',
      );
    }

    final paymentMethod =
        (_optionalString(extra['payment_method']) ?? 'cash').toLowerCase();
    if (!_allowedPaymentMethods.contains(paymentMethod)) {
      return PostingStageResult.failure(
        code: 'invalid_payment_method',
        message: 'payment_method must be cash or bank, got $paymentMethod',
      );
    }

    final txn = context.txn;
    final paymentDoc = await SupplierPaymentPostDb.loadPayment(txn, paymentId);
    if (paymentDoc == null) {
      return const PostingStageResult.failure(
        code: 'payment_not_found',
        message: 'Payment does not exist locally',
      );
    }

    final dbStatus = (paymentDoc['paymentStatus'] ?? '').toString();
    final dbTxnVersion =
        (paymentDoc['transactionVersion'] as int?) ??
        int.tryParse('${paymentDoc['transactionVersion']}') ??
        0;

    if (dbStatus == 'posted') {
      if (header.transactionVersion <= dbTxnVersion) {
        context.stageData['idempotent_replay'] = true;
        _loadPlannedEffects(context, amount: amount);
        return const PostingStageResult.proceed();
      }
      return const PostingStageResult.failure(
        code: 'already_posted',
        message: 'Payment already posted with newer transaction_version',
      );
    }

    if (dbStatus != 'draft') {
      return PostingStageResult.failure(
        code: 'invalid_status_for_post',
        message: 'Post requires draft paymentStatus, got $dbStatus',
      );
    }

    if (header.status != 'draft' && header.status != 'posted') {
      return PostingStageResult.failure(
        code: 'invalid_aggregate_status',
        message:
            'Aggregate status must be draft or posted, got ${header.status}',
      );
    }

    final expectedTxnVersion = dbTxnVersion + 1;
    if (header.transactionVersion != dbTxnVersion &&
        header.transactionVersion != expectedTxnVersion) {
      return PostingStageResult.failure(
        code: 'transaction_version_mismatch',
        message:
            'Expected transaction_version $dbTxnVersion or $expectedTxnVersion, got ${header.transactionVersion}',
      );
    }

    if (await SupplierPaymentPostDb.hasPostEffectsForPayment(txn, paymentId)) {
      return const PostingStageResult.failure(
        code: 'post_effects_exist',
        message: 'Cash or ledger effects already exist for this payment',
      );
    }

    if (!await SupplierPaymentPostDb.partnerExists(txn, supplierId)) {
      return const PostingStageResult.failure(
        code: 'supplier_not_found',
        message: 'Supplier does not exist',
      );
    }

    if (context.aggregate.lines.isNotEmpty) {
      return const PostingStageResult.failure(
        code: 'unexpected_lines',
        message: 'Supplier payment must not have line items',
      );
    }

    _loadPlannedEffects(context, amount: amount);
    context.stageData['validated_at'] = DateTime.now().toIso8601String();
    return const PostingStageResult.proceed();
  }

  void _loadPlannedEffects(
    PostingContext context, {
    required double amount,
  }) {
    var cash = SupplierPaymentPostEffects.readCash(context.aggregate);
    var accounting = SupplierPaymentPostEffects.readAccounting(context.aggregate);

    if (cash == null || accounting == null) {
      final header = context.aggregate.header;
      final extra = header is MapTransactionHeader ? header.extra : const {};
      final createdBy =
          _optionalString(extra['created_by_user_id']) ?? 'sync';
      final supplierId = _optionalString(extra['supplier_id']) ?? '';
      final paymentDate = _optionalString(extra['payment_date']);
      final notes = _optionalString(extra['notes']);
      final voucherNumber = _optionalString(extra['voucher_number']);
      final description = notes ?? 'سداد ذمة مورد';

      cash = SupplierPaymentPostEffects.buildCash(
        paymentId: header.id,
        amount: amount,
        createdBy: createdBy,
        description: description,
        transactionDate: paymentDate,
      );
      accounting = SupplierPaymentPostEffects.buildAccounting(
        paymentId: header.id,
        supplierId: supplierId,
        amount: amount,
        createdBy: createdBy,
        entryDate: paymentDate,
        notes: notes ?? 'دفعة مورد',
        voucherNumber: voucherNumber,
      );
    }

    context.stageData['cash'] = cash;
    context.stageData['accounting'] = accounting;
  }

  String? _optionalString(Object? value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }

  double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
