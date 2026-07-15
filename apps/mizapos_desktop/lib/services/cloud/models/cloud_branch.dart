/// فرع تابع لشركة على Miza Cloud — يطابق `branches` في PostgreSQL.
class CloudBranch {
  const CloudBranch({
    required this.id,
    required this.companyId,
    required this.code,
    required this.name,
    this.address,
    this.phone,
    this.isDefault = false,
    this.status = 'active',
    this.createdAt = '',
    this.updatedAt = '',
    this.rowVersion = 0,
  });

  factory CloudBranch.fromJson(Map<String, dynamic> json) {
    return CloudBranch(
      id: (json['id'] ?? '').toString(),
      companyId: (json['company_id'] ?? '').toString(),
      code: (json['code'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      address: _optionalString(json['address']),
      phone: _optionalString(json['phone']),
      isDefault:
          json['is_default'] == true || json['is_default'] == 1,
      status: (json['status'] ?? 'active').toString(),
      createdAt: (json['created_at'] ?? '').toString(),
      updatedAt: (json['updated_at'] ?? '').toString(),
      rowVersion: _asInt(json['row_version']),
    );
  }

  final String id;
  final String companyId;
  final String code;
  final String name;
  final String? address;
  final String? phone;
  final bool isDefault;
  final String status;
  final String createdAt;
  final String updatedAt;
  final int rowVersion;

  Map<String, dynamic> toJson() => {
        'id': id,
        'company_id': companyId,
        'code': code,
        'name': name,
        if (address != null) 'address': address,
        if (phone != null) 'phone': phone,
        'is_default': isDefault,
        'status': status,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'row_version': rowVersion,
      };

  CloudBranch copyWith({
    String? id,
    String? companyId,
    String? code,
    String? name,
    String? address,
    String? phone,
    bool? isDefault,
    String? status,
    String? createdAt,
    String? updatedAt,
    int? rowVersion,
  }) {
    return CloudBranch(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      code: code ?? this.code,
      name: name ?? this.name,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      isDefault: isDefault ?? this.isDefault,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowVersion: rowVersion ?? this.rowVersion,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudBranch &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          companyId == other.companyId &&
          code == other.code &&
          name == other.name &&
          address == other.address &&
          phone == other.phone &&
          isDefault == other.isDefault &&
          status == other.status &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt &&
          rowVersion == other.rowVersion;

  @override
  int get hashCode => Object.hash(
        id,
        companyId,
        code,
        name,
        address,
        phone,
        isDefault,
        status,
        createdAt,
        updatedAt,
        rowVersion,
      );
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  final s = value.toString().trim();
  return s.isEmpty ? null : s;
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
