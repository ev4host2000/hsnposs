import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_stage_result.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/posting_stage.dart';

/// Marks the in-memory post lifecycle complete — no DB status change in this sprint.
class FinalizePostingStage extends PostingStage {
  FinalizePostingStage();

  @override
  String get stageId => 'finalize';

  @override
  Future<PostingStageResult> run(PostingContext context) async {
    context.stageData['posted'] = true;
    context.stageData['final_status'] = 'posted';
    context.stageData['finalized_at'] = DateTime.now().toIso8601String();
    return const PostingStageResult.proceed();
  }
}
