import 'package:mizapos_desktop/services/cloud/sync/posting/opening_stock/stages/opening_stock_finalize_posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/opening_stock/stages/opening_stock_integrity_posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/opening_stock/stages/opening_stock_inventory_posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/opening_stock/stages/opening_stock_validation_posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_pipeline.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_pipeline_runner.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/transaction_posting_pipeline.dart';

/// Opening-stock posting pipeline — validation → inventory → integrity → finalize.
class OpeningStockPostingPipeline extends TransactionPostingPipeline {
  const OpeningStockPostingPipeline._();

  static const OpeningStockPostingPipeline instance =
      OpeningStockPostingPipeline._();

  static PostingPipeline create({PostingPipelineRunner? runner}) {
    return instance.toPipeline(runner: runner);
  }

  @override
  List<PostingStage> buildStages() => [
        OpeningStockValidationPostingStage(),
        OpeningStockInventoryPostingStage(),
        OpeningStockIntegrityPostingStage(),
        OpeningStockFinalizePostingStage(),
      ];
}
