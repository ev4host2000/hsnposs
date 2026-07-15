import 'package:mizapos_desktop/services/cloud/sync/posting/posting_pipeline.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_pipeline_runner.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/purchase_invoice/stages/purchase_invoice_accounting_posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/purchase_invoice/stages/purchase_invoice_finalize_posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/purchase_invoice/stages/purchase_invoice_integrity_posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/purchase_invoice/stages/purchase_invoice_inventory_posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/purchase_invoice/stages/purchase_invoice_validation_posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/transaction_posting_pipeline.dart';

/// Purchase-invoice posting pipeline — validation → inventory → accounting → integrity → finalize.
class PurchaseInvoicePostingPipeline extends TransactionPostingPipeline {
  const PurchaseInvoicePostingPipeline._();

  static const PurchaseInvoicePostingPipeline instance =
      PurchaseInvoicePostingPipeline._();

  static PostingPipeline create({PostingPipelineRunner? runner}) {
    return instance.toPipeline(runner: runner);
  }

  @override
  List<PostingStage> buildStages() => [
        PurchaseInvoiceValidationPostingStage(),
        PurchaseInvoiceInventoryPostingStage(),
        PurchaseInvoiceAccountingPostingStage(),
        PurchaseInvoiceIntegrityPostingStage(),
        PurchaseInvoiceFinalizePostingStage(),
      ];
}
