import '../detect_changes.dart';

/// Filter criteria containing glob path patterns and an evaluation [mode].
class const Filters({
  required final FilterMode mode,
  required final List<String> paths,
}) {
  /// Parses filter definitions from JSON/YAML data.
  ///
  /// Supports:
  /// - `List<dynamic>` of glob paths.
  /// - `Map<String, dynamic>` containing `paths` and optional `mode`.
  /// - Single `String` path.
  factory Filters.fromJson(
    dynamic json, {
    FilterMode defaultMode = FilterMode.or,
  }) {
    if (json is List) {
      return Filters(
        mode: defaultMode,
        paths: json.map((e) => e.toString()).toList(),
      );
    } else if (json is Map) {
      return Filters(
        mode: json.containsKey('mode')
            ? FilterMode.lookup(json['mode']?.toString())
            : defaultMode,
        paths: json['paths'] is List
            ? (json['paths'] as List).map((e) => e.toString()).toList()
            : json['paths'] != null
            ? [json['paths'].toString()]
            : const [],
      );
    } else if (json is String) {
      return Filters(mode: defaultMode, paths: [json]);
    }
    return Filters(mode: defaultMode, paths: const []);
  }
}
