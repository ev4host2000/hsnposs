import 'package:mizapos_mobile/services/cloud/sync/posting/posting_pipeline.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/posting_pipeline_runner.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/purchase_return/stages/purchase_return_accounting_posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/purchase_return/stages/purchase_return_finalize_posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/purchase_return/stages/purchase_return_integrity_posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/purchase_return/stages/purchase_return_inventory_posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/purchase_return/stages/purchase_return_validation_posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/transaction_posting_pipeline.dart';

/// Purchase-invoice posting pipeline — validation → inventory → accounting → integrity → finalize.
class PurchaseReturnPostingPipeline extends TransactionPostingPipeline {
  const PurchaseReturnPostingPipeline._();

  static const PurchaseReturnPostingPipeline instance =
      PurchaseReturnPostingPipeline._();

  static PostingPipeline create({PostingPipelineRunner? runner}) {
    return instance.toPipeline(runner: runner);
  }

  @override
  List<PostingStage> buildStages() => [
        PurchaseReturnValidationPostingStage(),
        PurchaseReturnInventoryPostingStage(),
        PurchaseReturnAccountingPostingStage(),
        PurchaseReturnIntegrityPostingStage(),
        PurchaseReturnFinalizePostingStage(),
      ];
}
