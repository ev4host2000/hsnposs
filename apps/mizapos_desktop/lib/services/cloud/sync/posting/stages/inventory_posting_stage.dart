import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_stage_result.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_stage.dart';

/// Placeholder — real stock movements will be implemented in a later sprint.
class InventoryPostingStage extends PostingStage {
  InventoryPostingStage();

  @override
  String get stageId => 'inventory';

  @override
  Future<PostingStageResult> run(PostingContext context) async {
    context.stageData['inventory_posted'] = false;
    context.stageData['inventory_movements'] = <Map<String, dynamic>>[];
    return const PostingStageResult.proceed();
  }
}
