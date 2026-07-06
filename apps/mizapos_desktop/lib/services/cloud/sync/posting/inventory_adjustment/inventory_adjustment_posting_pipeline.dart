import 'package:mizapos_desktop/services/cloud/sync/posting/inventory_adjustment/stages/inventory_adjustment_finalize_posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/inventory_adjustment/stages/inventory_adjustment_integrity_posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/inventory_adjustment/stages/inventory_adjustment_inventory_posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/inventory_adjustment/stages/inventory_adjustment_validation_posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_pipeline.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_pipeline_runner.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/transaction_posting_pipeline.dart';

/// Inventory-adjustment posting pipeline — validation → inventory → integrity → finalize.
class InventoryAdjustmentPostingPipeline extends TransactionPostingPipeline {
  const InventoryAdjustmentPostingPipeline._();

  static const InventoryAdjustmentPostingPipeline instance =
      InventoryAdjustmentPostingPipeline._();

  static PostingPipeline create({PostingPipelineRunner? runner}) {
    return instance.toPipeline(runner: runner);
  }

  @override
  List<PostingStage> buildStages() => [
        InventoryAdjustmentValidationPostingStage(),
        InventoryAdjustmentInventoryPostingStage(),
        InventoryAdjustmentIntegrityPostingStage(),
        InventoryAdjustmentFinalizePostingStage(),
      ];
}
