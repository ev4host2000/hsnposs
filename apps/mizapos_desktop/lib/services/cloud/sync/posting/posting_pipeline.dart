import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_result.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_pipeline_runner.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/stages/accounting_posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/stages/finalize_posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/stages/inventory_posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/stages/validation_posting_stage.dart';

/// Generic transaction posting pipeline — ADR-TX posting extension.
class PostingPipeline {
  PostingPipeline({
    required List<PostingStage> stages,
    PostingPipelineRunner? runner,
  })  : _stages = List.unmodifiable(stages),
        _runner = runner ?? const PostingPipelineRunner();

  final List<PostingStage> _stages;
  final PostingPipelineRunner _runner;

  List<PostingStage> get stages => _stages;

  Future<PostingResult> run(PostingContext context) {
    return _runner.run(stages: _stages, context: context);
  }

  /// Default stage order for document post (validation → inventory → accounting → finalize).
  factory PostingPipeline.standard({PostingPipelineRunner? runner}) {
    return PostingPipeline(
      runner: runner,
      stages: [
        ValidationPostingStage(),
        InventoryPostingStage(),
        AccountingPostingStage(),
        FinalizePostingStage(),
      ],
    );
  }

  PostingPipeline withAdditionalStages(List<PostingStage> extra) {
    return PostingPipeline(
      runner: _runner,
      stages: [..._stages, ...extra],
    );
  }
}
