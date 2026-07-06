import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_result.dart';

/// Thrown inside [Database.transaction] to roll back on posting failure.
class PostingPipelineAbortException implements Exception {
  PostingPipelineAbortException(this.result);

  final PostingResult result;

  @override
  String toString() =>
      'PostingPipelineAbortException(${result.failureCode ?? 'failed'})';
}

/// Rolls back the surrounding SQLite transaction when [result] is not ok.
void abortPostingTransactionIfFailed(PostingResult result) {
  if (!result.ok) {
    throw PostingPipelineAbortException(result);
  }
}
