/// Final outcome after running all posting stages (or stopping on failure).
class PostingResult {
  const PostingResult({
    required this.ok,
    this.failureCode,
    this.failureMessage,
    this.failedStageId,
    this.completedStageIds = const [],
    this.idempotentReplay = false,
  });

  const PostingResult.success({
    required List<String> completedStageIds,
    bool idempotentReplay = false,
  }) : this(
          ok: true,
          completedStageIds: completedStageIds,
          idempotentReplay: idempotentReplay,
        );

  const PostingResult.failed({
    required String failedStageId,
    required String failureCode,
    String? failureMessage,
    required List<String> completedStageIds,
  }) : this(
          ok: false,
          failedStageId: failedStageId,
          failureCode: failureCode,
          failureMessage: failureMessage,
          completedStageIds: completedStageIds,
        );

  final bool ok;
  final String? failureCode;
  final String? failureMessage;
  final String? failedStageId;
  final List<String> completedStageIds;

  /// True when post replayed against an already-posted invoice (no new effects).
  final bool idempotentReplay;
}
