/// Field metadata entry â€” Field Dictionary Specification v1.0 (Products subset).
class FieldSpec {
  const FieldSpec({
    required this.name,
    required this.type,
    required this.nullable,
    required this.comparisonRule,
    required this.patchable,
    required this.syncable,
    this.defaultValue,
    this.decimalScale,
    this.emptyAsNull = false,
    this.deprecated = false,
    this.forbiddenOnEntityPaths = const [],
  });

  final String name;
  final String type;
  final bool nullable;
  final Object? defaultValue;
  final String comparisonRule;
  final bool patchable;
  final bool syncable;
  final int? decimalScale;
  final bool emptyAsNull;
  final bool deprecated;
  final List<String> forbiddenOnEntityPaths;
}
