import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_stage_result.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/sales_invoice/sales_invoice_post_db.dart';

/// Sets invoice_status=posted, posted_at, bumps transaction_version and row_version.
class SalesInvoiceFinalizePostingStage extends PostingStage {
  SalesInvoiceFinalizePostingStage();

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
      final existing = await SalesInvoicePostDb.loadInvoice(
        context.txn,
        header.id,
      );
      final localStatus = (existing?['invoiceStatus'] ?? '').toString();
      if (localStatus == 'draft') {
        // Stock already exists; finish posting without re-applying effects.
        await SalesInvoicePostDb.finalizeInvoice(
          context.txn,
          invoiceId: header.id,
          transactionVersion: nextTxnVersion,
          rowVersion: nextRowVersion,
          postedAt: postedAt,
        );
        context.stageData['next_transaction_version'] = nextTxnVersion;
        context.stageData['next_row_version'] = nextRowVersion;
        context.stageData['posted_at'] = postedAt;
      }
      context.stageData['posted'] = true;
      context.stageData['final_status'] = 'posted';
      context.stageData['finalized_at'] = postedAt;
      return const PostingStageResult.proceed();
    }

    final finalized = await SalesInvoicePostDb.finalizeInvoice(
      context.txn,
      invoiceId: header.id,
      transactionVersion: nextTxnVersion,
      rowVersion: nextRowVersion,
      postedAt: postedAt,
    );
    if (!finalized) {
      return const PostingStageResult.failure(
        code: 'posting_conflict',
        message: 'Invoice was already posted or modified concurrently',
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
