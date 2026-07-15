/// GET `/sync/pull/products`
class ProductsPullRequest {
  const ProductsPullRequest({
    required this.companyId,
    required this.sinceSequence,
    this.branchId,
    this.limit,
  });

  final String companyId;
  final String? branchId;
  final int sinceSequence;
  final int? limit;

  Map<String, String> toQueryParameters() {
    final params = <String, String>{
      'company_id': companyId,
      'since_sequence': sinceSequence.toString(),
    };
    final branch = branchId?.trim();
    if (branch != null && branch.isNotEmpty) {
      params['branch_id'] = branch;
    }
    if (limit != null) {
      params['limit'] = limit.toString();
    }
    return params;
  }
}
