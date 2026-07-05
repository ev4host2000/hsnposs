/// GET `/sync/pull/{entity}`
class CatalogPullRequest {
  const CatalogPullRequest({
    required this.companyId,
    required this.branchId,
    required this.sinceSequence,
    this.limit,
  });

  final String companyId;
  final String branchId;
  final int sinceSequence;
  final int? limit;

  Map<String, String> toQueryParameters() {
    return {
      'company_id': companyId,
      'branch_id': branchId,
      'since_sequence': sinceSequence.toString(),
      if (limit != null) 'limit': limit.toString(),
    };
  }
}
