import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_stage_result.dart';

/// One step in the transaction posting pipeline.
abstract class PostingStage {
  String get stageId;

  Future<PostingStageResult> run(PostingContext context);
}
