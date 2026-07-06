import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_stage_result.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/opening_stock/opening_stock_post_db.dart';

/// Sets openingStatus=posted, posted_at, bumps transaction_version and row_version.
class OpeningStockFinalizePostingStage extends PostingStage {
  OpeningStockFinalizePostingStage();

  @override
  String get stageId => 'finalize';

  @override
  Future<PostingStageResult> run(PostingContext context) async {
    final header = context.aggregate.header;
    final postedAt = DateTime.now().toIso8601String();
    final nextTxnVersion = header.status == 'posted'
        ? header.transactionVersion
        : header.transactionVersion + 1;
    final nextRowVersion = header.status == 'posted'
        ? header.rowVersion
        : header.rowVersion + 1;

    if (context.stageData['idempotent_replay'] == true) {
      context.stageData['posted'] = true;
      context.stageData['final_status'] = 'posted';
      context.stageData['finalized_at'] = postedAt;
      return const PostingStageResult.proceed();
    }

    final finalized = await OpeningStockPostDb.finalizeOpeningStock(
      context.txn,
      openingStockId: header.id,
      transactionVersion: nextTxnVersion,
      rowVersion: nextRowVersion,
      postedAt: postedAt,
    );
    if (!finalized) {
      return const PostingStageResult.failure(
        code: 'posting_conflict',
        message: 'Opening stock was already posted or modified concurrently',
      );
    }

    context.stageData['posted'] = true;
    context.stageData['final_status'] = 'posted';
    context.stageData['finalized_at'] = postedAt;
    context.stageData['next_transaction_version'] = nextTxnVersion;
    context.stageData['next_row_version'] = nextRowVersion;
    context.stageData['posted_at'] = postedAt;
    return const PostingStageResult.proceed();
  }
}
