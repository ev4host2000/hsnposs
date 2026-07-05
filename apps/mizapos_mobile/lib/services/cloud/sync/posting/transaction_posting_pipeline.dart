import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_result.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/posting_pipeline.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/posting_pipeline_runner.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/posting_stage.dart';

/// Extension point for document-type posting pipelines (golden reference).
///
/// Future: [PurchaseInvoicePostingPipeline], [ReturnPostingPipeline], etc.
abstract class TransactionPostingPipeline {
  const TransactionPostingPipeline();

  /// Ordered stages for this document type.
  List<PostingStage> buildStages();

  PostingPipeline toPipeline({PostingPipelineRunner? runner}) {
    return PostingPipeline(runner: runner, stages: buildStages());
  }

  Future<PostingResult> run(
    PostingContext context, {
    PostingPipelineRunner? runner,
  }) {
    return toPipeline(runner: runner).run(context);
  }
}
