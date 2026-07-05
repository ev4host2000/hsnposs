import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_stage_result.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/models/transaction_aggregate.dart';

/// Framework-level post validation — no inventory/accounting effects.
class ValidationPostingStage extends PostingStage {
  ValidationPostingStage();

  @override
  String get stageId => 'validation';

  @override
  Future<PostingStageResult> run(PostingContext context) async {
    final header = context.aggregate.header;

    if (header.id.isEmpty) {
      return const PostingStageResult.failure(
        code: 'missing_id',
        message: 'Header id is required for post',
      );
    }

    if (header.documentType != context.entityType) {
      return const PostingStageResult.failure(
        code: 'document_type_mismatch',
        message: 'document_type must match entity_type',
      );
    }

    if (header.status != 'draft') {
      return PostingStageResult.failure(
        code: 'invalid_status_for_post',
        message: 'Post requires draft status, got ${header.status}',
      );
    }

    if (header.transactionVersion < 0) {
      return const PostingStageResult.failure(
        code: 'invalid_transaction_version',
        message: 'transaction_version must be >= 0',
      );
    }

    if (_hasEffectSections(context)) {
      return const PostingStageResult.failure(
        code: 'effects_not_allowed_in_pipeline_v1',
        message: 'inventory/accounting sections are not supported in this sprint',
      );
    }

    context.stageData['validated_at'] = DateTime.now().toIso8601String();
    return const PostingStageResult.proceed();
  }

  bool _hasEffectSections(PostingContext context) {
    final aggregate = context.aggregate;
    if (aggregate is MapTransactionAggregate) {
      final json = aggregate.toJson();
      return json.containsKey('inventory') || json.containsKey('accounting');
    }
    return false;
  }
}
