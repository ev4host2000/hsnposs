/// شركة (مستأجر) على Miza Cloud — يطابق `companies` في PostgreSQL.
class CloudCompany {
  const CloudCompany({
    required this.id,
    required this.name,
    this.legalName,
    this.countryCode,
    this.timezone = 'UTC',
    this.defaultCurrencyCode = '',
    this.defaultLocale = 'ar',
    this.status = 'active',
    this.createdAt = '',
    this.updatedAt = '',
    this.rowVersion = 0,
  });

  factory CloudCompany.fromJson(Map<String, dynamic> json) {
    return CloudCompany(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      legalName: _optionalString(json['legal_name']),
      countryCode: _optionalString(json['country_code']),
      timezone: (json['timezone'] ?? 'UTC').toString(),
      defaultCurrencyCode:
          (json['default_currency_code'] ?? '').toString(),
      defaultLocale: (json['default_locale'] ?? 'ar').toString(),
      status: (json['status'] ?? 'active').toString(),
      createdAt: (json['created_at'] ?? '').toString(),
      updatedAt: (json['updated_at'] ?? '').toString(),
      rowVersion: _asInt(json['row_version']),
    );
  }

  final String id;
  final String name;
  final String? legalName;
  final String? countryCode;
  final String timezone;
  final String defaultCurrencyCode;
  final String defaultLocale;
  final String status;
  final String createdAt;
  final String updatedAt;
  final int rowVersion;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (legalName != null) 'legal_name': legalName,
        if (countryCode != null) 'country_code': countryCode,
        'timezone': timezone,
        'default_currency_code': defaultCurrencyCode,
        'default_locale': defaultLocale,
        'status': status,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'row_version': rowVersion,
      };

  CloudCompany copyWith({
    String? id,
    String? name,
    String? legalName,
    String? countryCode,
    String? timezone,
    String? defaultCurrencyCode,
    String? defaultLocale,
    String? status,
    String? createdAt,
    String? updatedAt,
    int? rowVersion,
  }) {
    return CloudCompany(
      id: id ?? this.id,
      name: name ?? this.name,
      legalName: legalName ?? this.legalName,
      countryCode: countryCode ?? this.countryCode,
      timezone: timezone ?? this.timezone,
      defaultCurrencyCode:
          defaultCurrencyCode ?? this.defaultCurrencyCode,
      defaultLocale: defaultLocale ?? this.defaultLocale,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowVersion: rowVersion ?? this.rowVersion,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudCompany &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          legalName == other.legalName &&
          countryCode == other.countryCode &&
          timezone == other.timezone &&
          defaultCurrencyCode == other.defaultCurrencyCode &&
          defaultLocale == other.defaultLocale &&
          status == other.status &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt &&
          rowVersion == other.rowVersion;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        legalName,
        countryCode,
        timezone,
        defaultCurrencyCode,
        defaultLocale,
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
