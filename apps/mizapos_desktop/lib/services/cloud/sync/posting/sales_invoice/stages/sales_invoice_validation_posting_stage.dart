import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_stage_result.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/sales_invoice/sales_invoice_post_db.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/sales_invoice/sales_invoice_post_effects.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/models/transaction_aggregate.dart';

/// Sales-invoice post validation — real DB checks, plans effects in stageData.
class SalesInvoiceValidationPostingStage extends PostingStage {
  SalesInvoiceValidationPostingStage();

  @override
  String get stageId => 'validation';

  @override
  Future<PostingStageResult> run(PostingContext context) async {
    final header = context.aggregate.header;
    final invoiceId = header.id;
    if (invoiceId.isEmpty) {
      return const PostingStageResult.failure(
        code: 'missing_id',
        message: 'Header id is required for post',
      );
    }

    if (header.documentType != context.entityType) {
      return const PostingStageResult.failure(
        code: 'document_type_mismatch',
        message: 'document_type must match entity_type',
      );
    }

    final extra = header is MapTransactionHeader ? header.extra : const {};
    final customerId = _optionalString(extra['customer_id']);
    if (customerId == null) {
      return const PostingStageResult.failure(
        code: 'missing_customer',
        message: 'customer_id is required for post',
      );
    }

    final txn = context.txn;
    final invoice = await SalesInvoicePostDb.loadInvoice(txn, invoiceId);
    if (invoice == null) {
      return const PostingStageResult.failure(
        code: 'invoice_not_found',
        message: 'Invoice does not exist locally',
      );
    }

    final dbStatus = (invoice['invoiceStatus'] ?? '').toString();
    final dbTxnVersion =
        (invoice['transactionVersion'] as int?) ??
        int.tryParse('${invoice['transactionVersion']}') ??
        0;

    if (dbStatus == 'posted') {
      if (header.transactionVersion <= dbTxnVersion) {
        context.stageData['idempotent_replay'] = true;
        _loadPlannedEffects(context);
        return const PostingStageResult.proceed();
      }
      return const PostingStageResult.failure(
        code: 'already_posted',
        message: 'Invoice already posted with newer transaction_version',
      );
    }

    if (dbStatus != 'draft') {
      return PostingStageResult.failure(
        code: 'invalid_status_for_post',
        message: 'Post requires draft status, got $dbStatus',
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

    if (await SalesInvoicePostDb.hasPostMovementsForInvoice(txn, invoiceId)) {
      // Draft remaining after stock was applied (e.g. interrupted finalize, or
      // draft-pull overwritten status). Recover as idempotent post.
      context.stageData['idempotent_replay'] = true;
      _loadPlannedEffects(context);
      return const PostingStageResult.proceed();
    }

    if (!await SalesInvoicePostDb.partnerExists(txn, 'customers', customerId)) {
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
      if (!await SalesInvoicePostDb.productExists(txn, productId)) {
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
    var inventory = SalesInvoicePostEffects.readInventory(context.aggregate);
    var accounting = SalesInvoicePostEffects.readAccounting(context.aggregate);

    if (inventory.isEmpty || accounting.isEmpty) {
      final header = context.aggregate.header;
      final extra = header is MapTransactionHeader ? header.extra : const {};
      final lines = _aggregateLineMaps(context.aggregate);
      final createdBy =
          _optionalString(extra['created_by_user_id']) ?? 'sync';
      final customerId = _optionalString(extra['customer_id']) ?? '';
      final amounts = SalesInvoicePostEffects.computeAmounts(
        lines: lines,
        discountAmount: _asDouble(extra['discount_amount']),
        taxPercent: _asDouble(extra['tax_percent']),
        headerTotal: _asDouble(extra['total']),
      );
      inventory = SalesInvoicePostEffects.buildInventory(
        invoiceId: header.id,
        organizationId: header.companyId,
        branchId: header.branchId,
        lines: lines,
        createdBy: createdBy,
      );
      accounting = SalesInvoicePostEffects.buildAccounting(
        invoiceId: header.id,
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
