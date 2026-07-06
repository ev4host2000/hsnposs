import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_stage_result.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/opening_stock/opening_stock_post_db.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/opening_stock/opening_stock_post_effects.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/models/transaction_aggregate.dart';

/// Opening-stock post validation — real DB checks, plans effects in stageData.
class OpeningStockValidationPostingStage extends PostingStage {
  OpeningStockValidationPostingStage();

  @override
  String get stageId => 'validation';

  @override
  Future<PostingStageResult> run(PostingContext context) async {
    final header = context.aggregate.header;
    final openingStockId = header.id;
    if (openingStockId.isEmpty) {
      return const PostingStageResult.failure(
        code: 'missing_id',
        message: 'Header id is required for post',
      );
    }

    if (header.documentType != context.entityType) {
      return const PostingStageResult.failure(
        code: 'document_type_mismatch',
        message: 'document_type must be opening_stock',
      );
    }

    final extra = header is MapTransactionHeader ? header.extra : const {};
    final txn = context.txn;
    final openingStockDoc =
        await OpeningStockPostDb.loadOpeningStock(txn, openingStockId);
    if (openingStockDoc == null) {
      return const PostingStageResult.failure(
        code: 'opening_stock_not_found',
        message: 'Opening stock does not exist locally',
      );
    }

    final productId = _optionalString(extra['product_id']) ??
        _optionalString(openingStockDoc['productId']);
    if (productId == null) {
      return const PostingStageResult.failure(
        code: 'missing_product',
        message: 'product_id is required for post',
      );
    }

    final headerQty = _asDouble(extra['opening_quantity']);
    final openingQuantity = headerQty >= 1e-9
        ? headerQty
        : _asDouble(openingStockDoc['openingQuantity']);
    if (openingQuantity < 1e-9) {
      return const PostingStageResult.failure(
        code: 'invalid_opening_quantity',
        message: 'opening_quantity must be positive',
      );
    }

    context.stageData['resolved_product_id'] = productId;
    context.stageData['resolved_opening_quantity'] = openingQuantity;

    final dbStatus = (openingStockDoc['openingStatus'] ?? '').toString();
    final dbTxnVersion =
        (openingStockDoc['transactionVersion'] as int?) ??
        int.tryParse('${openingStockDoc['transactionVersion']}') ??
        0;

    if (dbStatus == 'posted') {
      if (header.transactionVersion <= dbTxnVersion) {
        context.stageData['idempotent_replay'] = true;
        _loadPlannedEffects(context);
        return const PostingStageResult.proceed();
      }
      return const PostingStageResult.failure(
        code: 'already_posted',
        message: 'Opening stock already posted with newer transaction_version',
      );
    }

    if (dbStatus != 'draft') {
      return PostingStageResult.failure(
        code: 'invalid_status_for_post',
        message: 'Post requires draft openingStatus, got $dbStatus',
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

    if (await OpeningStockPostDb.hasPostMovementsForOpeningStock(
      txn,
      openingStockId,
    )) {
      return const PostingStageResult.failure(
        code: 'post_effects_exist',
        message: 'Stock movements already exist for this opening stock',
      );
    }

    if (!await OpeningStockPostDb.productExists(txn, productId)) {
      return const PostingStageResult.failure(
        code: 'product_not_found',
        message: 'Product does not exist',
      );
    }

    if (context.aggregate.lines.isNotEmpty) {
      return const PostingStageResult.failure(
        code: 'unexpected_lines',
        message: 'Opening stock must not have line items',
      );
    }

    _loadPlannedEffects(context);
    context.stageData['validated_at'] = DateTime.now().toIso8601String();
    return const PostingStageResult.proceed();
  }

  void _loadPlannedEffects(PostingContext context) {
    final idempotentReplay = context.stageData['idempotent_replay'] == true;
    var inventory = idempotentReplay
        ? OpeningStockPostEffects.readInventory(context.aggregate)
        : null;

    if (inventory == null) {
      final header = context.aggregate.header;
      final extra = header is MapTransactionHeader ? header.extra : const {};
      final createdBy =
          _optionalString(extra['created_by_user_id']) ?? 'sync';
      final productId =
          context.stageData['resolved_product_id']?.toString() ??
          _optionalString(extra['product_id']) ??
          '';
      final openingQuantity =
          context.stageData['resolved_opening_quantity'] as double? ??
          _asDouble(extra['opening_quantity']);
      final openingDate = _optionalString(extra['opening_date']);

      inventory = OpeningStockPostEffects.buildInventory(
        openingStockId: header.id,
        productId: productId,
        openingQuantity: openingQuantity,
        createdBy: createdBy,
        movementDate: openingDate,
      );
    }

    context.stageData['inventory'] = inventory;
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
