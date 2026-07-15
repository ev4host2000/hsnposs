import 'package:mizapos_desktop/services/cloud/sync/posting/posting_pipeline.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_pipeline_runner.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/sales_invoice/stages/sales_invoice_accounting_posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/sales_invoice/stages/sales_invoice_finalize_posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/sales_invoice/stages/sales_invoice_integrity_posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/sales_invoice/stages/sales_invoice_inventory_posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/sales_invoice/stages/sales_invoice_validation_posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/transaction_posting_pipeline.dart';

/// Sales-invoice posting pipeline — validation → inventory → accounting → integrity → finalize.
class SalesInvoicePostingPipeline extends TransactionPostingPipeline {
  const SalesInvoicePostingPipeline._();

  static const SalesInvoicePostingPipeline instance =
      SalesInvoicePostingPipeline._();

  static PostingPipeline create({PostingPipelineRunner? runner}) {
    return instance.toPipeline(runner: runner);
  }

  @override
  List<PostingStage> buildStages() => [
        SalesInvoiceValidationPostingStage(),
        SalesInvoiceInventoryPostingStage(),
        SalesInvoiceAccountingPostingStage(),
        SalesInvoiceIntegrityPostingStage(),
        SalesInvoiceFinalizePostingStage(),
      ];
}
