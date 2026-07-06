import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_result.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_stage_result.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_stage.dart';

/// Executes posting stages in order; stops on first failure.
class PostingPipelineRunner {
  const PostingPipelineRunner();

  Future<PostingResult> run({
    required List<PostingStage> stages,
    required PostingContext context,
  }) async {
    final completed = <String>[];

    for (final stage in stages) {
      final outcome = await stage.run(context);
      if (outcome.isFailure) {
        return PostingResult.failed(
          failedStageId: stage.stageId,
          failureCode: outcome.code ?? 'stage_failed',
          failureMessage: outcome.message,
          completedStageIds: List.unmodifiable(completed),
        );
      }
      completed.add(stage.stageId);
    }

    return PostingResult.success(
      completedStageIds: List.unmodifiable(completed),
      idempotentReplay: context.stageData['idempotent_replay'] == true,
    );
  }
}
