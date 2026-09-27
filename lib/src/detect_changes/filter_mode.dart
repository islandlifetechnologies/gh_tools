/// Aggregation mode for evaluating path filter sets.
enum FilterMode {
  /// All filter patterns must match.
  and,

  /// At least one filter pattern must match.
  or;

  /// Looks up a [FilterMode] from string, defaulting to [FilterMode.and].
  static FilterMode lookup(String? mode) =>
      switch (mode?.toLowerCase().trim()) {
        'or' => FilterMode.or,
        'and' => FilterMode.and,
        _ => FilterMode.and,
      };
}
