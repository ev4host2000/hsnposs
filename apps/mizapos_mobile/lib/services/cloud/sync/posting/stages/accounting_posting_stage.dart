import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_stage_result.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/posting_stage.dart';

/// Placeholder — real journal entries will be implemented in a later sprint.
class AccountingPostingStage extends PostingStage {
  AccountingPostingStage();

  @override
  String get stageId => 'accounting';

  @override
  Future<PostingStageResult> run(PostingContext context) async {
    context.stageData['accounting_posted'] = false;
    context.stageData['journal_entries'] = <Map<String, dynamic>>[];
    return const PostingStageResult.proceed();
  }
}
