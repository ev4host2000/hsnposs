import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_result.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_pipeline.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/models/transaction_aggregate.dart';
import 'package:sqflite/sqflite.dart';

/// Lets [TransactionApplyHandler] implementations invoke posting without framework changes.
///
/// Not used by document handlers yet — available for future `applyPost()` implementations.
class ApplyHandlerPostingBridge {
  const ApplyHandlerPostingBridge({PostingPipeline? pipeline})
      : _pipeline = pipeline;

  final PostingPipeline? _pipeline;

  static final PostingPipeline sharedStandardPipeline = PostingPipeline.standard();

  PostingPipeline get pipeline => _pipeline ?? sharedStandardPipeline;

  Future<PostingResult> runPost({
    required TransactionAggregate aggregate,
    required DatabaseExecutor txn,
    required String entityType,
    PostingPipeline? pipeline,
  }) {
    final active = pipeline ?? this.pipeline;
    return active.run(
      PostingContext(
        aggregate: aggregate,
        txn: txn,
        entityType: entityType,
      ),
    );
  }
}

/// Optional mixin for apply handlers that will post via the pipeline later.
mixin TransactionApplyHandlerPostingAccess {
  ApplyHandlerPostingBridge get postingBridge =>
      const ApplyHandlerPostingBridge();

  Future<PostingResult> runPostingPipeline({
    required TransactionAggregate aggregate,
    required DatabaseExecutor txn,
    required String entityType,
    PostingPipeline? pipeline,
  }) {
    return postingBridge.runPost(
      aggregate: aggregate,
      txn: txn,
      entityType: entityType,
      pipeline: pipeline,
    );
  }
}
