import 'package:mizapos_mobile/services/cloud/sync/posting/posting_pipeline.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/posting_pipeline_runner.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/customer_payment/stages/customer_payment_accounting_posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/customer_payment/stages/customer_payment_finalize_posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/customer_payment/stages/customer_payment_integrity_posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/customer_payment/stages/customer_payment_validation_posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/transaction_posting_pipeline.dart';

/// Customer-payment posting pipeline — validation → accounting → integrity → finalize.
class CustomerPaymentPostingPipeline extends TransactionPostingPipeline {
  const CustomerPaymentPostingPipeline._();

  static const CustomerPaymentPostingPipeline instance =
      CustomerPaymentPostingPipeline._();

  static PostingPipeline create({PostingPipelineRunner? runner}) {
    return instance.toPipeline(runner: runner);
  }

  @override
  List<PostingStage> buildStages() => [
        CustomerPaymentValidationPostingStage(),
        CustomerPaymentAccountingPostingStage(),
        CustomerPaymentIntegrityPostingStage(),
        CustomerPaymentFinalizePostingStage(),
      ];
}
