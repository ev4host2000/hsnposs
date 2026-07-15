import 'package:mizapos_desktop/services/cloud/sync/posting/posting_pipeline.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_pipeline_runner.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/sales_return/stages/sales_return_accounting_posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/sales_return/stages/sales_return_finalize_posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/sales_return/stages/sales_return_integrity_posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/sales_return/stages/sales_return_inventory_posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/sales_return/stages/sales_return_validation_posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/transaction_posting_pipeline.dart';

/// Sales-invoice posting pipeline — validation → inventory → accounting → integrity → finalize.
class SalesReturnPostingPipeline extends TransactionPostingPipeline {
  const SalesReturnPostingPipeline._();

  static const SalesReturnPostingPipeline instance =
      SalesReturnPostingPipeline._();

  static PostingPipeline create({PostingPipelineRunner? runner}) {
    return instance.toPipeline(runner: runner);
  }

  @override
  List<PostingStage> buildStages() => [
        SalesReturnValidationPostingStage(),
        SalesReturnInventoryPostingStage(),
        SalesReturnAccountingPostingStage(),
        SalesReturnIntegrityPostingStage(),
        SalesReturnFinalizePostingStage(),
      ];
}
