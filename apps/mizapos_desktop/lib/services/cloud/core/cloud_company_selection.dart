import 'package:mizapos_desktop/services/cloud/auth/auth_exception.dart';

/// خيار متجر عند تعدد الحسابات لنفس البريد.
class CloudCompanyOption {
  const CloudCompanyOption({
    required this.companyId,
    required this.companyName,
    required this.branchId,
  });

  factory CloudCompanyOption.fromJson(Map<String, dynamic> json) {
    return CloudCompanyOption(
      companyId: (json['company_id'] ?? '').toString(),
      companyName: (json['company_name'] ?? '').toString(),
      branchId: (json['branch_id'] ?? '').toString(),
    );
  }

  final String companyId;
  final String companyName;
  final String branchId;
}

/// يُرمى عندما يتطلب الخادم اختيار متجر قبل إكمال الدخول.
class CloudCompanySelectionRequired implements Exception {
  const CloudCompanySelectionRequired(this.companies);

  final List<CloudCompanyOption> companies;

  static CloudCompanySelectionRequired? fromAuthException(AuthException e) {
    if (e.code != 'company_selection_required') return null;
    final raw = e.cloudError?.details['companies'];
    if (raw is! List) return null;
    final companies = <CloudCompanyOption>[];
    for (final item in raw) {
      if (item is Map) {
        companies.add(
          CloudCompanyOption.fromJson(Map<String, dynamic>.from(item)),
        );
      }
    }
    if (companies.isEmpty) return null;
    return CloudCompanySelectionRequired(companies);
  }
}

