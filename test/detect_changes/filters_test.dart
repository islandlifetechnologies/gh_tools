import 'package:gh_tools/gh_tools.dart';
import 'package:test/test.dart';

void main() {
  group('FilterMode', () {
    test('lookup resolves modes correctly', () {
      expect(FilterMode.lookup('and'), FilterMode.and);
      expect(FilterMode.lookup('AND'), FilterMode.and);
      expect(FilterMode.lookup('or'), FilterMode.or);
      expect(FilterMode.lookup('OR'), FilterMode.or);
      expect(FilterMode.lookup(null), FilterMode.and);
      expect(FilterMode.lookup('unknown'), FilterMode.and);
    });
  });

  group('Filters.fromJson', () {
    test('parses from map with mode and paths', () {
      final filters = Filters.fromJson({
        'mode': 'or',
        'paths': ['lib/**', 'bin/**'],
      });

      expect(filters.mode, FilterMode.or);
      expect(filters.paths, ['lib/**', 'bin/**']);
    });

    test('parses from map using defaultMode when mode is omitted', () {
      final filters = Filters.fromJson({
        'paths': ['lib/**'],
      }, defaultMode: FilterMode.and);

      expect(filters.mode, FilterMode.and);
      expect(filters.paths, ['lib/**']);
    });

    test('parses from list of paths', () {
      final filters = Filters.fromJson([
        'lib/**',
        'test/**',
      ], defaultMode: FilterMode.or);

      expect(filters.mode, FilterMode.or);
      expect(filters.paths, ['lib/**', 'test/**']);
    });

    test('parses from single string path', () {
      final filters = Filters.fromJson('lib/**', defaultMode: FilterMode.and);

      expect(filters.mode, FilterMode.and);
      expect(filters.paths, ['lib/**']);
    });

    test('handles empty or unexpected inputs', () {
      final filters = Filters.fromJson(null);
      expect(filters.paths, isEmpty);
      expect(filters.mode, FilterMode.or);
    });
  });
}
