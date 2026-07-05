/// Outcome of a single posting stage — proceed or abort the pipeline.
enum PostingStageDecision {
  proceed,
  failure,
}

class PostingStageResult {
  const PostingStageResult._({
    required this.decision,
    this.code,
    this.message,
  });

  const PostingStageResult.proceed() : this._(decision: PostingStageDecision.proceed);

  const PostingStageResult.failure({
    required String code,
    String? message,
  }) : this._(
          decision: PostingStageDecision.failure,
          code: code,
          message: message,
        );

  final PostingStageDecision decision;
  final String? code;
  final String? message;

  bool get isProceed => decision == PostingStageDecision.proceed;
  bool get isFailure => decision == PostingStageDecision.failure;
}
