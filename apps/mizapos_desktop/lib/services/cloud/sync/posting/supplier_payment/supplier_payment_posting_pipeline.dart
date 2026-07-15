import 'package:mizapos_desktop/services/cloud/sync/posting/posting_pipeline.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_pipeline_runner.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/supplier_payment/stages/supplier_payment_accounting_posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/supplier_payment/stages/supplier_payment_finalize_posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/supplier_payment/stages/supplier_payment_integrity_posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/supplier_payment/stages/supplier_payment_validation_posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/transaction_posting_pipeline.dart';

/// Supplier-payment posting pipeline — validation → accounting → integrity → finalize.
class SupplierPaymentPostingPipeline extends TransactionPostingPipeline {
  const SupplierPaymentPostingPipeline._();

  static const SupplierPaymentPostingPipeline instance =
      SupplierPaymentPostingPipeline._();

  static PostingPipeline create({PostingPipelineRunner? runner}) {
    return instance.toPipeline(runner: runner);
  }

  @override
  List<PostingStage> buildStages() => [
        SupplierPaymentValidationPostingStage(),
        SupplierPaymentAccountingPostingStage(),
        SupplierPaymentIntegrityPostingStage(),
        SupplierPaymentFinalizePostingStage(),
      ];
}
