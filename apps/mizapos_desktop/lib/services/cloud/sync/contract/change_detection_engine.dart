import 'package:mizapos_desktop/services/cloud/sync/contract/field_spec.dart';
import 'package:mizapos_desktop/services/cloud/sync/contract/product_field_dictionary.dart';

/// Field Change Detection Engine — Spec v1.0 (client mirror).
///
/// Defaults to Products patchable fields; pass [fields] for Partners / others.
abstract final class ChangeDetectionEngine {
  /// Returns changed_fields map (field → normalized next value).
  static Map<String, Object?> detect({
    required Map<String, Object?> baseSnapshot,
    required Map<String, Object?> nextSnapshot,
    List<FieldSpec>? fields,
  }) {
    final changed = <String, Object?>{};
    final specs = fields ?? ProductFieldDictionary.patchableFields;
    for (final field in specs) {
      final baseRaw = baseSnapshot.containsKey(field.name)
          ? baseSnapshot[field.name]
          : field.defaultValue;
      final nextRaw = nextSnapshot.containsKey(field.name)
          ? nextSnapshot[field.name]
          : field.defaultValue;
      final baseNorm = normalize(field, baseRaw);
      final nextNorm = normalize(field, nextRaw);
      if (!valuesEqual(field, baseNorm, nextNorm)) {
        changed[field.name] = nextNorm;
      }
    }
    return changed;
  }

  static Object? normalize(FieldSpec field, Object? value) {
    if (value == null) {
      if (!field.nullable && field.defaultValue != null) {
        return normalize(field, field.defaultValue);
      }
      return null;
    }
    if (field.emptyAsNull && value is String && value.trim().isEmpty) {
      return null;
    }

    switch (field.comparisonRule) {
      case 'string_default':
        return value.toString();
      case 'decimal_scale':
        return _normalizeDecimal(value, field.decimalScale ?? 4);
      case 'boolean_default':
        return _normalizeBool(value);
      case 'integer_default':
        return _normalizeInt(value);
      case 'uuid_canonical':
        return _normalizeUuid(value);
      case 'image_url_special':
        return _normalizeImageUrl(value, field.emptyAsNull);
      case 'datetime_iso8601':
        return _normalizeDateTime(value);
      default:
        throw ArgumentError(
          'Unsupported comparison_rule ${field.comparisonRule} for ${field.name}',
        );
    }
  }

  static bool valuesEqual(FieldSpec field, Object? a, Object? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    switch (field.comparisonRule) {
      case 'decimal_scale':
        return a.toString() == b.toString();
      case 'boolean_default':
        return a == b;
      case 'integer_default':
        return a == b;
      default:
        return a == b;
    }
  }

  static String _normalizeDecimal(Object? value, int scale) {
    if (value is bool) {
      throw ArgumentError('decimal field requires numeric value');
    }
    final n = value is num ? value.toDouble() : double.tryParse(value.toString());
    if (n == null) {
      throw ArgumentError('decimal field requires numeric value');
    }
    return n.toStringAsFixed(scale);
  }

  static bool _normalizeBool(Object? value) {
    if (value is bool) return value;
    if (value is num) {
      if (value == 1) return true;
      if (value == 0) return false;
      throw ArgumentError('boolean field numeric must be 0 or 1');
    }
    final v = value.toString().trim().toLowerCase();
    if (v == '1' || v == 'true' || v == 'yes') return true;
    if (v == '0' || v == 'false' || v == 'no' || v.isEmpty) return false;
    throw ArgumentError('boolean field has invalid value');
  }

  static int _normalizeInt(Object? value) {
    if (value is int) return value;
    if (value is num) {
      if (value != value.roundToDouble()) {
        throw ArgumentError('integer field cannot be fractional');
      }
      return value.toInt();
    }
    final parsed = int.tryParse(value.toString().trim());
    if (parsed == null) {
      throw ArgumentError('integer field has invalid value');
    }
    return parsed;
  }

  static String? _normalizeUuid(Object? value) {
    if (value == null) return null;
    final v = value.toString().trim().toLowerCase();
    if (v.isEmpty) return null;
    final re = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    );
    if (!re.hasMatch(v)) {
      throw ArgumentError('uuid field has invalid format');
    }
    return v;
  }

  static String? _normalizeImageUrl(Object? value, bool emptyAsNull) {
    if (value == null) return null;
    final v = value.toString().trim();
    if (v.isEmpty) return emptyAsNull ? null : '';
    return v;
  }

  static String? _normalizeDateTime(Object? value) {
    if (value == null) return null;
    final raw = value.toString().trim();
    if (raw.isEmpty) {
      throw ArgumentError('datetime field must be non-empty ISO-8601 string or null');
    }
    final dt = DateTime.tryParse(raw);
    if (dt == null) {
      throw ArgumentError('datetime field has invalid value');
    }
    return dt.toUtc().toIso8601String().replaceFirst(RegExp(r'\.\d+'), '');
  }
}
