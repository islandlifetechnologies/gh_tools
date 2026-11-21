import 'package:file/memory.dart';
import 'package:gh_tools/gh_tools.dart';
import 'package:test/test.dart';

void main() {
  group('parseIgnoredPackages', () {
    test('parses single-line inline list comment', () {
      const content = '''
# ignore_packages: [foo, bar]
repos: []
''';
      expect(parseIgnoredPackages(content), equals({'foo', 'bar'}));
    });

    test('parses multi-line indented comment list', () {
      const content = '''
env:
  # ignore_packages:
  #   - alpha
  #   - beta
  filters: |
''';
      expect(parseIgnoredPackages(content), equals({'alpha', 'beta'}));
    });
  });

  group('runMonorepoCheck', () {
    late MemoryFileSystem fs;
    const root = '/repo';

    setUp(() {
      fs = MemoryFileSystem();
      fs.directory(root).createSync(recursive: true);
    });

    test('skips when packages directory does not exist', () {
      final result = runMonorepoCheck(absTargetPath: root, fs: fs);
      expect(result.skipped, isTrue);
      expect(result.modifiedFiles, isEmpty);
    });

    test('skips when packages directory has only one package', () {
      fs.directory('$root/packages/only_one').createSync(recursive: true);
      final result = runMonorepoCheck(absTargetPath: root, fs: fs);
      expect(result.skipped, isTrue);
      expect(result.modifiedFiles, isEmpty);
    });

    test('adds missing packages and puts monorepo at top with priority 1', () {
      fs.directory('$root/packages/pkg_a').createSync(recursive: true);
      fs.directory('$root/packages/pkg_b').createSync(recursive: true);
      fs.file('$root/.pre-commit-config.yaml').writeAsStringSync('''
repos:
  - repo: https://github.com/islandlifetechnologies/gh_tools
    rev: v1.1.3
    hooks:
      - id: all
        name: pkg_a
        args: [--path=packages/pkg_a]
''');

      final result = runMonorepoCheck(absTargetPath: root, fs: fs);
      expect(result.skipped, isFalse);
      expect(result.modifiedFiles, equals(['.pre-commit-config.yaml']));

      final updated = fs
          .file('$root/.pre-commit-config.yaml')
          .readAsStringSync();
      expect(
        updated,
        contains(
          '    hooks:\n'
          '      - id: monorepo\n'
          '        name: monorepo\n'
          '        priority: 1\n'
          '      - id: all\n'
          '        name: pkg_a\n'
          '        args: ["--path=packages/pkg_a"]\n'
          '        priority: 2\n'
          '      - id: all\n'
          '        name: pkg_b\n'
          '        args: ["--path=packages/pkg_b"]\n'
          '        priority: 2',
        ),
      );

      // Running again when already in sync should make no modifications.
      final secondResult = runMonorepoCheck(absTargetPath: root, fs: fs);
      expect(secondResult.skipped, isFalse);
      expect(secondResult.modifiedFiles, isEmpty);
    });

    test('updates detect_changes workflow using gh_tools reusable action', () {
      fs.directory('$root/packages/pkg_a').createSync(recursive: true);
      fs.directory('$root/packages/pkg_b').createSync(recursive: true);
      fs.file('$root/.pre-commit-config.yaml').writeAsStringSync('''
repos:
  - repo: https://github.com/islandlifetechnologies/gh_tools
    rev: v1.1.3
    hooks:
      - id: monorepo
        name: monorepo
        priority: 1
      - id: all
        name: pkg_a
        args: ["--path=packages/pkg_a"]
        priority: 2
      - id: all
        name: pkg_b
        args: ["--path=packages/pkg_b"]
        priority: 2
''');
      fs.directory('$root/.github/workflows').createSync(recursive: true);
      fs.file('$root/.github/workflows/publish.yaml').writeAsStringSync(r'''
name: Tag & Publish

env:
  filters: |
    pkg_a:
      paths:
        - packages/pkg_a/**

jobs:
  detect_changes:
    runs-on: ubuntu-latest
    steps:
      - uses: islandlifetechnologies/gh_tools@v1
      - run: |
          detect_changes --filters "${{ env.filters }}"
''');

      final result = runMonorepoCheck(absTargetPath: root, fs: fs);
      expect(result.skipped, isFalse);
      expect(result.modifiedFiles, equals(['.github/workflows/publish.yaml']));

      final updated = fs
          .file('$root/.github/workflows/publish.yaml')
          .readAsStringSync();
      expect(updated, contains('pkg_b:\n      paths: [packages/pkg_b/**]'));
      expect(
        updated,
        contains(r'detect_changes --filters "${{ env.filters }}"'),
      );
    });

    test('updates detect_changes workflow activating gh_tools', () {
      fs.directory('$root/packages/pkg_a').createSync(recursive: true);
      fs.directory('$root/packages/pkg_b').createSync(recursive: true);
      fs.file('$root/.pre-commit-config.yaml').writeAsStringSync('''
repos:
  - repo: https://github.com/islandlifetechnologies/gh_tools
    rev: v1.1.3
    hooks:
      - id: monorepo
        name: monorepo
        priority: 1
      - id: all
        name: pkg_a
        args: ["--path=packages/pkg_a"]
        priority: 2
      - id: all
        name: pkg_b
        args: ["--path=packages/pkg_b"]
        priority: 2
''');
      fs.directory('$root/.github/workflows').createSync(recursive: true);
      fs.file('$root/.github/workflows/ci.yml').writeAsStringSync(r'''
name: CI

env:
  filters: |
    pkg_a:
      paths:
        - packages/pkg_a/**

jobs:
  detect_changes:
    runs-on: ubuntu-latest
    steps:
      - run: |
          dart pub global activate gh_tools
          detect_changes --filters "${{ env.filters }}"
''');

      final result = runMonorepoCheck(absTargetPath: root, fs: fs);
      expect(result.skipped, isFalse);
      expect(result.modifiedFiles, equals(['.github/workflows/ci.yml']));

      final updated = fs
          .file('$root/.github/workflows/ci.yml')
          .readAsStringSync();
      expect(updated, contains('pkg_b:\n      paths: [packages/pkg_b/**]'));
    });

    test(
      'respects ignore_packages comment independently in config and workflow',
      () {
        fs.directory('$root/packages/pkg_a').createSync(recursive: true);
        fs.directory('$root/packages/pkg_b').createSync(recursive: true);
        fs.directory('$root/packages/pkg_c').createSync(recursive: true);

        fs.file('$root/.pre-commit-config.yaml').writeAsStringSync('''
# ignore_packages: [pkg_b]
repos:
  - repo: https://github.com/islandlifetechnologies/gh_tools
    rev: v1.1.3
    hooks:
      - id: monorepo
        name: monorepo
        priority: 1
      - id: all
        name: pkg_a
        args: [--path=packages/pkg_a]
        priority: 2
      - id: all
        name: pkg_c
        args: [--path=packages/pkg_c]
        priority: 2
''');

        fs.directory('$root/.github/workflows').createSync(recursive: true);
        fs.file('$root/.github/workflows/publish.yaml').writeAsStringSync(r'''
name: Publish

env:
  # ignore_packages:
  #   - pkg_c
  filters: |
    pkg_a:
      paths: [packages/pkg_a/**]
    pkg_b:
      paths: [packages/pkg_b/**]

jobs:
  detect_changes:
    runs-on: ubuntu-latest
    steps:
      - uses: islandlifetechnologies/gh_tools@v1
      - run: detect_changes --filters "${{ env.filters }}"
''');

        final result = runMonorepoCheck(absTargetPath: root, fs: fs);
        expect(result.skipped, isFalse);
        expect(result.modifiedFiles, isEmpty);
      },
    );
  });
}
