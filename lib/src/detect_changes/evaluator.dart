import 'package:glob/glob.dart';
import 'package:logging/logging.dart';

import '../detect_changes.dart';

/// Evaluates file paths against glob patterns defined in [Filters].
class Evaluator {
  final _logger = Logger('Evaluator');

  /// Evaluates whether the changed [files] match the given [filters].
  ///
  /// In [FilterMode.or] mode, returns `true` if any pattern matches at least
  /// one file.  In [FilterMode.and] mode, returns `true` if every pattern
  /// matches at least one file.  Returns `false` if either [files] or
  /// [Filters.paths] is empty.
  bool evaluate({required List<String> files, required Filters filters}) {
    if (files.isEmpty || filters.paths.isEmpty) {
      return false;
    }

    switch (filters.mode) {
      case FilterMode.or:
        for (final path in filters.paths) {
          final glob = Glob(path);
          if (files.any(glob.matches)) {
            _logger.fine('Matched pattern: $path');
            return true;
          }
        }
        return false;

      case FilterMode.and:
        for (final path in filters.paths) {
          final glob = Glob(path);
          if (!files.any(glob.matches)) {
            _logger.fine('Unmatched pattern: $path');
            return false;
          }
        }
        return true;
    }
  }
}
