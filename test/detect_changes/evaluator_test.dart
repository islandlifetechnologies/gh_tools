import 'package:gh_tools/gh_tools.dart';
import 'package:test/test.dart';

void main() {
  group('Evaluator', () {
    late Evaluator evaluator;

    setUp(() {
      evaluator = Evaluator();
    });

    test('returns false when files or paths are empty', () {
      expect(
        evaluator.evaluate(
          files: [],
          filters: const Filters(mode: FilterMode.or, paths: ['lib/**']),
        ),
        isFalse,
      );

      expect(
        evaluator.evaluate(
          files: ['lib/src/foo.dart'],
          filters: const Filters(mode: FilterMode.or, paths: []),
        ),
        isFalse,
      );
    });

    test('OR mode: returns true if any pattern matches', () {
      final filters = const Filters(
        mode: FilterMode.or,
        paths: ['lib/**', 'bin/**'],
      );

      expect(
        evaluator.evaluate(files: ['lib/client.dart'], filters: filters),
        isTrue,
      );

      expect(
        evaluator.evaluate(files: ['doc/README.md'], filters: filters),
        isFalse,
      );
    });

    test('AND mode: returns true only if all patterns match', () {
      final filters = const Filters(
        mode: FilterMode.and,
        paths: ['lib/**', 'test/**'],
      );

      expect(
        evaluator.evaluate(
          files: ['lib/client.dart', 'test/client_test.dart'],
          filters: filters,
        ),
        isTrue,
      );

      expect(
        evaluator.evaluate(files: ['lib/client.dart'], filters: filters),
        isFalse,
      );
    });
  });
}
