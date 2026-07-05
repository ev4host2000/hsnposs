/// GET `/sync/versions` — لمقارنة إصدار catalog قبل pull.
class CatalogVersionsRequest {
  const CatalogVersionsRequest({
    required this.companyId,
    this.branchId,
  });

  final String companyId;
  final String? branchId;

  Map<String, String> toQueryParameters() {
    final params = <String, String>{'company_id': companyId};
    final branch = branchId?.trim();
    if (branch != null && branch.isNotEmpty) {
      params['branch_id'] = branch;
    }
    return params;
  }
}
