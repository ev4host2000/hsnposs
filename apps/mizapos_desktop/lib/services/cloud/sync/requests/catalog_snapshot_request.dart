/// GET `/sync/pull/snapshot` — catalog scope (أول sync أو بعد 410).
class CatalogSnapshotRequest {
  const CatalogSnapshotRequest({
    required this.companyId,
    this.branchId,
    this.page,
    this.pageSize,
  });

  final String companyId;
  final String? branchId;
  final int? page;
  final int? pageSize;

  Map<String, String> toQueryParameters() {
    final params = <String, String>{
      'company_id': companyId,
      'entity_scope': CatalogSnapshotRequest.entityScope,
    };
    final branch = branchId?.trim();
    if (branch != null && branch.isNotEmpty) {
      params['branch_id'] = branch;
    }
    if (page != null) {
      params['page'] = page.toString();
    }
    if (pageSize != null) {
      params['page_size'] = pageSize.toString();
    }
    return params;
  }

  static const String entityScope = 'catalog';
}
