import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_stage_result.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/sales_return/sales_return_post_db.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/sales_return/sales_return_post_effects.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/models/transaction_aggregate.dart';

/// Sales-return post validation — real DB checks, plans effects in stageData.
class SalesReturnValidationPostingStage extends PostingStage {
  SalesReturnValidationPostingStage();

  @override
  String get stageId => 'validation';

  @override
  Future<PostingStageResult> run(PostingContext context) async {
    final header = context.aggregate.header;
    final returnId = header.id;
    if (returnId.isEmpty) {
      return const PostingStageResult.failure(
        code: 'missing_id',
        message: 'Header id is required for post',
      );
    }

    if (header.documentType != context.entityType) {
      return const PostingStageResult.failure(
        code: 'document_type_mismatch',
        message: 'document_type must be sales_return',
      );
    }

    final extra = header is MapTransactionHeader ? header.extra : const {};
    final originalInvoiceId = _optionalString(extra['original_invoice_id']);
    if (originalInvoiceId == null) {
      return const PostingStageResult.failure(
        code: 'missing_original_invoice',
        message: 'original_invoice_id is required for post',
      );
    }

    final customerId = _optionalString(extra['customer_id']);
    if (customerId == null) {
      return const PostingStageResult.failure(
        code: 'missing_customer',
        message: 'customer_id is required for post',
      );
    }

    final txn = context.txn;
    final returnDoc = await SalesReturnPostDb.loadReturn(txn, returnId);
    if (returnDoc == null) {
      return const PostingStageResult.failure(
        code: 'return_not_found',
        message: 'Return does not exist locally',
      );
    }

    final dbStatus = (returnDoc['returnStatus'] ?? '').toString();
    final dbTxnVersion =
        (returnDoc['transactionVersion'] as int?) ??
        int.tryParse('${returnDoc['transactionVersion']}') ??
        0;

    if (dbStatus == 'posted') {
      if (header.transactionVersion <= dbTxnVersion) {
        context.stageData['idempotent_replay'] = true;
        _loadPlannedEffects(context);
        return const PostingStageResult.proceed();
      }
      return const PostingStageResult.failure(
        code: 'already_posted',
        message: 'Return already posted with newer transaction_version',
      );
    }

    if (dbStatus != 'draft') {
      return PostingStageResult.failure(
        code: 'invalid_status_for_post',
        message: 'Post requires draft returnStatus, got $dbStatus',
      );
    }

    if (header.status != 'draft' && header.status != 'posted') {
      return PostingStageResult.failure(
        code: 'invalid_aggregate_status',
        message: 'Aggregate status must be draft or posted, got ${header.status}',
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

    if (await SalesReturnPostDb.hasPostMovementsForReturn(txn, returnId)) {
      return const PostingStageResult.failure(
        code: 'post_effects_exist',
        message: 'Stock movements already exist for this return',
      );
    }

    if (!await SalesReturnPostDb.partnerExists(txn, 'customers', customerId)) {
      return const PostingStageResult.failure(
        code: 'customer_not_found',
        message: 'Customer does not exist',
      );
    }

    final aggregateLines = _aggregateLineMaps(context.aggregate);
    if (aggregateLines.isEmpty) {
      return const PostingStageResult.failure(
        code: 'missing_lines',
        message: 'At least one line is required',
      );
    }

    for (final line in aggregateLines) {
      final productId = (line['product_id'] ?? '').toString();
      final quantity = _asDouble(line['quantity']);
      final unitPrice = _asDouble(line['unit_price']);
      if (productId.isEmpty) {
        return const PostingStageResult.failure(
          code: 'missing_product_id',
          message: 'Line product_id is required',
        );
      }
      if (quantity <= 0) {
        return const PostingStageResult.failure(
          code: 'invalid_quantity',
          message: 'Line quantity must be > 0',
        );
      }
      if (unitPrice < 0) {
        return const PostingStageResult.failure(
          code: 'invalid_price',
          message: 'Line unit_price must be >= 0',
        );
      }
      if (!await SalesReturnPostDb.productExists(txn, productId)) {
        return PostingStageResult.failure(
          code: 'product_not_found',
          message: 'Product $productId does not exist',
        );
      }
    }

    _loadPlannedEffects(context);
    context.stageData['validated_at'] = DateTime.now().toIso8601String();
    return const PostingStageResult.proceed();
  }

  void _loadPlannedEffects(PostingContext context) {
    var inventory = SalesReturnPostEffects.readInventory(context.aggregate);
    var accounting = SalesReturnPostEffects.readAccounting(context.aggregate);

    if (inventory.isEmpty || accounting.isEmpty) {
      final header = context.aggregate.header;
      final extra = header is MapTransactionHeader ? header.extra : const {};
      final lines = _aggregateLineMaps(context.aggregate);
      final createdBy =
          _optionalString(extra['created_by_user_id']) ?? 'sync';
      final customerId = _optionalString(extra['customer_id']) ?? '';
      final amounts = SalesReturnPostEffects.computeAmounts(
        lines: lines,
        discountAmount: _asDouble(extra['discount_amount']),
        taxPercent: _asDouble(extra['tax_percent']),
        headerTotal: _asDouble(extra['total']),
      );
      inventory = SalesReturnPostEffects.buildInventory(
        returnId: header.id,
        organizationId: header.companyId,
        branchId: header.branchId,
        lines: lines,
        createdBy: createdBy,
      );
      accounting = SalesReturnPostEffects.buildAccounting(
        returnId: header.id,
        organizationId: header.companyId,
        customerId: customerId,
        amounts: amounts,
        createdBy: createdBy,
      );
    }

    context.stageData['inventory'] = inventory;
    context.stageData['accounting'] = accounting;
  }

  List<Map<String, dynamic>> _aggregateLineMaps(TransactionAggregate aggregate) {
    return aggregate.lines.map((line) {
      if (line is MapTransactionLine) {
        return Map<String, dynamic>.from(line.fields)
          ..putIfAbsent('line_id', () => line.lineId);
      }
      return line.toJson();
    }).toList();
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
