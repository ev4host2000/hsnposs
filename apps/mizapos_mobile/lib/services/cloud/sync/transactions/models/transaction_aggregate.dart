/// Abstract aggregate sections — ADR-TX-002 / ADR-TX-011.
abstract class TransactionAggregateHeader {
  String get id;
  String get companyId;
  String get branchId;
  String get documentType;
  String get status;
  int get transactionVersion;
  int get rowVersion;

  Map<String, dynamic> toJson();
}

abstract class TransactionAggregateLine {
  String get lineId;

  Map<String, dynamic> toJson();
}

abstract class TransactionAggregateMetadata {
  int get payloadSchemaVersion;
  String? get originDeviceId;
  String? get occurredAt;

  Map<String, dynamic> toJson();
}

/// Full transaction aggregate (header + lines + metadata).
abstract class TransactionAggregate {
  TransactionAggregateHeader get header;
  List<TransactionAggregateLine> get lines;
  TransactionAggregateMetadata get metadata;

  Map<String, dynamic> toJson();
}

/// Generic map-backed aggregate for framework/tests — not a business document.
class MapTransactionAggregate implements TransactionAggregate {
  MapTransactionAggregate({
    required this.header,
    required this.lines,
    required this.metadata,
  });

  factory MapTransactionAggregate.fromParts({
    required Map<String, dynamic> header,
    List<Map<String, dynamic>> lines = const [],
    Map<String, dynamic>? metadata,
  }) {
    return MapTransactionAggregate(
      header: MapTransactionHeader.fromJson(header),
      lines: lines.map(MapTransactionLine.fromJson).toList(),
      metadata: MapTransactionMetadata.fromJson(metadata ?? const {}),
    );
  }

  @override
  final MapTransactionHeader header;
  @override
  final List<MapTransactionLine> lines;
  @override
  final MapTransactionMetadata metadata;

  @override
  Map<String, dynamic> toJson() => {
        'header': header.toJson(),
        'lines': lines.map((l) => l.toJson()).toList(),
        'metadata': metadata.toJson(),
      };
}

class MapTransactionHeader implements TransactionAggregateHeader {
  MapTransactionHeader({
    required this.id,
    required this.companyId,
    required this.branchId,
    required this.documentType,
    required this.status,
    required this.transactionVersion,
    required this.rowVersion,
    this.extra = const {},
  });

  factory MapTransactionHeader.fromJson(Map<String, dynamic> json) {
    return MapTransactionHeader(
      id: (json['id'] ?? '').toString(),
      companyId: (json['company_id'] ?? '').toString(),
      branchId: (json['branch_id'] ?? '').toString(),
      documentType: (json['document_type'] ?? '').toString(),
      status: (json['status'] ?? 'draft').toString(),
      transactionVersion: _asInt(json['transaction_version']),
      rowVersion: _asInt(json['row_version']),
      extra: Map<String, dynamic>.from(json)
        ..removeWhere((key, _) => _knownHeaderKeys.contains(key)),
    );
  }

  static const _knownHeaderKeys = {
    'id',
    'company_id',
    'branch_id',
    'document_type',
    'status',
    'transaction_version',
    'row_version',
  };

  @override
  final String id;
  @override
  final String companyId;
  @override
  final String branchId;
  @override
  final String documentType;
  @override
  final String status;
  @override
  final int transactionVersion;
  @override
  final int rowVersion;
  final Map<String, dynamic> extra;

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'company_id': companyId,
        'branch_id': branchId,
        'document_type': documentType,
        'status': status,
        'transaction_version': transactionVersion,
        'row_version': rowVersion,
        ...extra,
      };
}

class MapTransactionLine implements TransactionAggregateLine {
  MapTransactionLine({required this.lineId, this.fields = const {}});

  factory MapTransactionLine.fromJson(Map<String, dynamic> json) {
    final id = (json['line_id'] ?? json['id'] ?? '').toString();
    return MapTransactionLine(
      lineId: id,
      fields: Map<String, dynamic>.from(json),
    );
  }

  @override
  final String lineId;
  final Map<String, dynamic> fields;

  @override
  Map<String, dynamic> toJson() => {
        'line_id': lineId,
        ...fields,
      };
}

class MapTransactionMetadata implements TransactionAggregateMetadata {
  MapTransactionMetadata({
    required this.payloadSchemaVersion,
    this.originDeviceId,
    this.occurredAt,
    this.extra = const {},
  });

  factory MapTransactionMetadata.fromJson(Map<String, dynamic> json) {
    return MapTransactionMetadata(
      payloadSchemaVersion:
          _asInt(json['payload_schema_version'], fallback: 1),
      originDeviceId: _optionalString(json['origin_device_id']),
      occurredAt: _optionalString(json['occurred_at']),
      extra: Map<String, dynamic>.from(json)
        ..removeWhere((key, _) => _knownMetadataKeys.contains(key)),
    );
  }

  static const _knownMetadataKeys = {
    'payload_schema_version',
    'origin_device_id',
    'occurred_at',
  };

  @override
  final int payloadSchemaVersion;
  @override
  final String? originDeviceId;
  @override
  final String? occurredAt;
  final Map<String, dynamic> extra;

  @override
  Map<String, dynamic> toJson() => {
        'payload_schema_version': payloadSchemaVersion,
        if (originDeviceId != null) 'origin_device_id': originDeviceId,
        if (occurredAt != null) 'occurred_at': occurredAt,
        ...extra,
      };
}

int _asInt(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  final s = value.toString().trim();
  return s.isEmpty ? null : s;
}
