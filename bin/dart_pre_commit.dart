import 'dart:io';

import 'package:args/args.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:gh_tools/gh_tools.dart';
import 'package:gh_tools/src/util/pubspec.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml_writer/yaml_writer.dart';
import 'package:yaon/yaon.dart';

const _kDartFolders = ['bin', 'lib', 'test', 'tool', 'example'];

const _kSteps = {
  'all': 'Run all pre-commit steps sequentially.',
  'analyze': 'Run "dart analyze".',
  'branch-version': 'Verify that the version in pubspec.yaml does not match the default branch.',
  'build-runner': 'If build_runner is a dependency or dev_dependency, run "dart run build_runner build".',
  'changelog-version':
      'Verify that the version in pubspec.yaml has an entry in CHANGELOG.md.',
  'format':
      'Run "dart format" on each existing folder and re-add changed files.',
  'format-fail':
      'Run "dart format --set-exit-if-changed" on each existing folder.',
  'install': 'Creates / updates the .pre-commit-config.yaml file as necessary.',
  'pub-get': 'Run "dart pub get".',
  'scan-packages': 'Scan the packages folder and sync package entries in .pre-commit-config.yaml.',
  'test': 'Run "flutter test" or "dart test" if a "test" folder exists.',
};

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'path',
      abbr: 'p',
      defaultsTo: '.',
      help: 'The path to the project to run the steps against.',
    )
    ..addOption(
      'step',
      abbr: 's',
      allowed: _kSteps.keys,
      allowedHelp: _kSteps,
      defaultsTo: 'all',
      help: 'The pre-commit step to execute.',
    );

  final parsed = ArgUtil(parser: parser).parse(args);
  final step = parsed['step'] as String;
  var targetPath = parsed['path'] as String;

  const fs = LocalFileSystem();
  final rest = List<String>.from(parsed.parsed.rest);

  if (!parsed.parsed.wasParsed('path') && rest.isNotEmpty) {
    final first = rest.first;
    if (fs.directory(first).existsSync() || !first.endsWith('.dart')) {
      targetPath = rest.removeAt(0);
    }
  }

  final targetDir = fs.directory(targetPath);
  if (!targetDir.existsSync()) {
    stderr.writeln(
      "Error: Target path '$targetPath' does not exist or is not a directory.",
    );
    exit(1);
  }

  final absTargetPath = targetDir.resolveSymbolicLinksSync();
  final relPrefixResult = await Process.run(
    'git',
    ['rev-parse', '--show-prefix'],
    runInShell: Platform.isWindows,
    workingDirectory: absTargetPath,
  );
  if (relPrefixResult.exitCode != 0) {
    stderr.writeln(
      'Error: Failed to determine git prefix: ${relPrefixResult.stderr}',
    );
    exit(1);
  }

  final relPrefix = (relPrefixResult.stdout as String).trim();
  final displayPath = relPrefix.isEmpty
      ? '.'
      : relPrefix.replaceAll(RegExp(r'/+$'), '');

  try {
    if (step == 'scan_packages') {
      _stepScanPackages(
        absTargetPath: absTargetPath,
        displayPath: displayPath,
        fs: fs,
      );
      exit(0);
    }
    if (step == 'install') {
      _installHooks(
        absTargetPath: absTargetPath,
        displayPath: displayPath,
        fs: fs,
      );
      exit(0);
    }

    // final hasDartChanges = await _hasDartChanges(
    //   absTargetPath: absTargetPath,
    //   changedFiles: rest,
    //   relPrefix: relPrefix,
    // );

    // if (!hasDartChanges) {
    //   stdout.writeln(
    //     '==> [$displayPath] ($step) No Dart file changes detected. Skipping.',
    //   );
    //   exit(0);
    // }

    final pubspecFile = fs.file('$absTargetPath/pubspec.yaml');
    if (!pubspecFile.existsSync()) {
      stderr.writeln("Error: pubspec.yaml not found in '$displayPath'.");
      exit(1);
    }

    final rawYaml = yaon.parse(pubspecFile.readAsStringSync());
    if (rawYaml is! Map) {
      stderr.writeln(
        "Error: Unable to parse '$displayPath/pubspec.yaml' as a map.",
      );
      exit(1);
    }
    final pubspecYaml = Map<dynamic, dynamic>.from(rawYaml);

    switch (step) {
      case 'all':
        await _stepPubGet(
          absTargetPath: absTargetPath,
          displayPath: displayPath,
        );
        await _stepBuildRunner(
          absTargetPath: absTargetPath,
          displayPath: displayPath,
          pubspecYaml: pubspecYaml,
        );
        await _stepFormat(
          absTargetPath: absTargetPath,
          displayPath: displayPath,
          fs: fs,
        );
        await _stepAnalyze(
          absTargetPath: absTargetPath,
          displayPath: displayPath,
        );
        await _stepTest(
          absTargetPath: absTargetPath,
          displayPath: displayPath,
          fs: fs,
          pubspecYaml: pubspecYaml,
        );
        _stepChangelogVersion(
          absTargetPath: absTargetPath,
          displayPath: displayPath,
          fs: fs,
          pubspecYaml: pubspecYaml,
        );
        await _stepBranchVersion(
          absTargetPath: absTargetPath,
          displayPath: displayPath,
          pubspecYaml: pubspecYaml,
          relPrefix: relPrefix,
        );
      case 'analyze':
        await _stepAnalyze(
          absTargetPath: absTargetPath,
          displayPath: displayPath,
        );
      case 'branch-version':
        await _stepBranchVersion(
          absTargetPath: absTargetPath,
          displayPath: displayPath,
          pubspecYaml: pubspecYaml,
          relPrefix: relPrefix,
        );
      case 'build-runner':
        await _stepBuildRunner(
          absTargetPath: absTargetPath,
          displayPath: displayPath,
          pubspecYaml: pubspecYaml,
        );
      case 'changelog-version':
        _stepChangelogVersion(
          absTargetPath: absTargetPath,
          displayPath: displayPath,
          fs: fs,
          pubspecYaml: pubspecYaml,
        );
      case 'format':
        await _stepFormat(
          absTargetPath: absTargetPath,
          displayPath: displayPath,
          fs: fs,
        );
      case 'format-fail':
        await _stepFormat(
          absTargetPath: absTargetPath,
          displayPath: displayPath,
          fs: fs,
          setExitIfChanged: true,
        );
      case 'pub-get':
        await _stepPubGet(
          absTargetPath: absTargetPath,
          displayPath: displayPath,
        );
      case 'test':
        await _stepTest(
          absTargetPath: absTargetPath,
          displayPath: displayPath,
          fs: fs,
          pubspecYaml: pubspecYaml,
        );
    }
    exit(0);
  } on _StepFailedException catch (e) {
    if (e.message != null) {
      stderr.writeln(e.message);
    }
    exit(e.exitCode);
  } catch (e, stack) {
    stderr.writeln('Error: $e');
    stderr.writeln(stack);
    exit(1);
  }
}

Future<void> _installHooks({
  required String absTargetPath,
  required String displayPath,
  required FileSystem fs,
}) async {
  stdout.writeln('Installing pre-commit hooks...');

  final version = Version.parse(kPubspec.version);

  final configFile = fs.file('$absTargetPath/.pre-commit-config.yaml');
  if (!configFile.existsSync()) {
    configFile.createSync(recursive: true);
  }

  final packagesDir = fs.directory('$absTargetPath/packages');
  if (packagesDir.existsSync()) {
    stdout.writeln(
      '==> [$displayPath] No packages directory found. Passing scan_packages.',
    );
    const defaultSteps = ['scan-packages'];

    final config = <String, dynamic>{
      'repos': [
        {
          'repo': 'https://github.com/islandlifetechnologies/gh_tools',
          'rev': 'v${version.major}',
          'hooks': [
            for (final step in defaultSteps) {'id': step, 'name': step},
          ],
        },
      ],
    };

    configFile.writeAsStringSync(
      YamlWriter(allowUnquotedStrings: true).convert(config),
    );
    _stepScanPackages(
      absTargetPath: absTargetPath,
      displayPath: displayPath,
      fs: fs,
    );
  } else {
    const defaultSteps = [
      'pub-get',
      'build-runner',
      'format',
      'analyze',
      'test',
      'changelog-version',
      'branch-version',
    ];

    final config = <String, dynamic>{
      'repos': [
        {
          'repo': 'https://github.com/islandlifetechnologies/gh_tools',
          'rev': 'v${version.major}',
          'hooks': [
            for (final step in defaultSteps) {'id': step, 'name': step},
          ],
        },
      ],
    };

    configFile.writeAsStringSync(
      YamlWriter(allowUnquotedStrings: true).convert(config),
    );
  }

  await _runCommand('pre-commit', ['install'], workingDirectory: '.');
}

String? _extractPackageFromHook(Map<dynamic, dynamic> hook) {
  final id = hook['id']?.toString() ?? '';
  final entry = hook['entry']?.toString() ?? '';
  final args = hook['args'];

  final tokens = <String>[];
  if (entry.isNotEmpty) {
    tokens.addAll(entry.split(RegExp(r'\s+')));
  }
  if (args is List) {
    tokens.addAll(args.map((e) => e.toString()));
  }

  final isAllStep =
      id == 'all' ||
      tokens.contains('--step=all') ||
      _hasFlagValue(tokens, '--step', 'all') ||
      _hasFlagValue(tokens, '-s', 'all');
  if (!isAllStep) {
    return null;
  }

  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    if (token.startsWith('--path=')) {
      final path = token.substring('--path='.length);
      final pkg = _packageNameFromPath(path);
      if (pkg != null) {
        return pkg;
      }
    } else if ((token == '--path' || token == '-p') && i + 1 < tokens.length) {
      final pkg = _packageNameFromPath(tokens[i + 1]);
      if (pkg != null) {
        return pkg;
      }
    } else if (!token.startsWith('-')) {
      final pkg = _packageNameFromPath(token);
      if (pkg != null) {
        return pkg;
      }
    }
  }
  return null;
}

String _formatYamlScalar(dynamic value) {
  if (value == null) {
    return 'null';
  }
  if (value is bool || value is num) {
    return value.toString();
  }
  final str = value.toString();
  if (str.isEmpty ||
      str.contains('\n') ||
      RegExp(r'^[\s:#\-\[\]\{\},&*!|>\x27"@`?]').hasMatch(str) ||
      str.contains(': ')) {
    final escaped = str.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return '"$escaped"';
  }
  return str;
}

void _writeYamlMap(
  StringBuffer buf,
  Map<dynamic, dynamic> map, {
  bool firstLineUnindented = false,
  required int indent,
}) {
  final entries = map.entries.toList();
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final key = entry.key.toString();
    final value = entry.value;
    final prefix = (i == 0 && firstLineUnindented) ? '' : (' ' * indent);

    if (value is Map) {
      buf.writeln('$prefix$key:');
      _writeYamlMap(buf, Map<dynamic, dynamic>.from(value), indent: indent + 2);
    } else if (value is List) {
      if (key == 'args' &&
          value.isNotEmpty &&
          value.every((e) => e is! Map && e is! List)) {
        final inlineItems = value.map(_formatYamlScalar).join(', ');
        buf.writeln('$prefix$key: [$inlineItems]');
      } else if (value.isEmpty) {
        buf.writeln('$prefix$key: []');
      } else {
        buf.writeln('$prefix$key:');
        _writeYamlList(buf, value, indent: indent + 2);
      }
    } else {
      buf.writeln('$prefix$key: ${_formatYamlScalar(value)}');
    }
  }
}

void _writeYamlList(
  StringBuffer buf,
  List<dynamic> list, {
  bool blankLineBetweenItems = false,
  required int indent,
}) {
  final prefix = ' ' * indent;
  for (var i = 0; i < list.length; i++) {
    if (i > 0 && blankLineBetweenItems) {
      buf.writeln();
    }
    final item = list[i];
    if (item is Map) {
      buf.write('$prefix- ');
      _writeYamlMap(
        buf,
        Map<dynamic, dynamic>.from(item),
        firstLineUnindented: true,
        indent: indent + 2,
      );
    } else {
      buf.writeln('$prefix- ${_formatYamlScalar(item)}');
    }
  }
}

Future<String?> _getDefaultBranch(String workingDirectory) async {
  final symRef = await Process.run(
    'git',
    ['symbolic-ref', '--quiet', '--short', 'refs/remotes/origin/HEAD'],
    runInShell: Platform.isWindows,
    workingDirectory: workingDirectory,
  );
  if (symRef.exitCode == 0) {
    final ref = (symRef.stdout as String).trim();
    if (ref.isNotEmpty && await _gitRefExists(workingDirectory, ref)) {
      return ref;
    }
  }

  for (final candidate in const [
    'origin/main',
    'origin/master',
    'origin/develop',
    'main',
    'master',
    'develop',
  ]) {
    if (await _gitRefExists(workingDirectory, candidate)) {
      return candidate;
    }
  }

  final configRef = await Process.run(
    'git',
    ['config', '--get', 'init.defaultBranch'],
    runInShell: Platform.isWindows,
    workingDirectory: workingDirectory,
  );
  if (configRef.exitCode == 0) {
    final configured = (configRef.stdout as String).trim();
    if (configured.isNotEmpty) {
      for (final candidate in ['origin/$configured', configured]) {
        if (await _gitRefExists(workingDirectory, candidate)) {
          return candidate;
        }
      }
    }
  }

  return null;
}

Future<bool> _gitRefExists(String workingDirectory, String ref) async {
  final result = await Process.run(
    'git',
    ['rev-parse', '--verify', '--quiet', ref],
    runInShell: Platform.isWindows,
    workingDirectory: workingDirectory,
  );
  return result.exitCode == 0;
}

bool _hasChangelogEntry(String changelogContent, String version) {
  final headingPrefix = RegExp(r'^(#+\s+)?(\[?v?)?');
  final trailingBoundary = RegExp(r'^(\]|[^0-9A-Za-z._+-])');

  for (final rawLine in changelogContent.split('\n')) {
    final line = rawLine.trimRight();
    final match = headingPrefix.firstMatch(line);
    if (match == null) {
      continue;
    }
    final stripped = line.substring(match.end);
    if (stripped.startsWith(version)) {
      final rest = stripped.substring(version.length);
      if (rest.isEmpty || trailingBoundary.hasMatch(rest)) {
        return true;
      }
    }
  }
  return false;
}

// Future<bool> _hasDartChanges({
//   required String absTargetPath,
//   required List<String> changedFiles,
//   required String relPrefix,
// }) async {
//   if (changedFiles.isNotEmpty) {
//     for (final file in changedFiles) {
//       final cleanFile = file
//           .replaceAll(r'\', '/')
//           .replaceFirst(RegExp(r'^\./'), '');
//       if (cleanFile.endsWith('.dart')) {
//         if (relPrefix.isEmpty || cleanFile.startsWith(relPrefix)) {
//           return true;
//         }
//       }
//     }
//     return false;
//   }

//   final diffResult = await Process.run(
//     'git',
//     ['diff', '--cached', '--name-only', '--', absTargetPath],
//     runInShell: Platform.isWindows,
//     workingDirectory: absTargetPath,
//   );
//   if (diffResult.exitCode != 0) {
//     return false;
//   }

//   final lines = (diffResult.stdout as String).split('\n');
//   return lines.any((line) => line.trim().endsWith('.dart'));
// }

bool _hasDependency(
  Map<dynamic, dynamic> pubspecYaml,
  String pkg, {
  bool includeDev = false,
}) {
  final deps = pubspecYaml['dependencies'];
  if (deps is Map && deps.containsKey(pkg)) {
    return true;
  }
  if (includeDev) {
    final devDeps = pubspecYaml['dev_dependencies'];
    if (devDeps is Map && devDeps.containsKey(pkg)) {
      return true;
    }
  }
  return false;
}

bool _hasFlagValue(List<String> tokens, String flag, String expectedValue) {
  for (var i = 0; i < tokens.length - 1; i++) {
    if (tokens[i] == flag && tokens[i + 1] == expectedValue) {
      return true;
    }
  }
  return false;
}

bool _listsEqual(List<String> a, List<String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

String? _packageNameFromPath(String rawPath) {
  final normalized = rawPath
      .replaceAll(r'\', '/')
      .replaceFirst(RegExp(r'^\./'), '')
      .replaceAll(RegExp(r'/+$'), '');
  if (normalized.startsWith('packages/')) {
    final rest = normalized.substring('packages/'.length);
    if (rest.isNotEmpty && !rest.contains('/')) {
      return rest;
    }
  }
  return null;
}

Future<void> _runCommand(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows,
    workingDirectory: workingDirectory,
  );
  final code = await process.exitCode;
  if (code != 0) {
    throw _StepFailedException(exitCode: code);
  }
}

/// Run "dart analyze"
Future<void> _stepAnalyze({
  required String absTargetPath,
  required String displayPath,
}) async {
  stdout.writeln('==> [$displayPath] Running dart analyze...');
  await _runCommand('dart', ['analyze'], workingDirectory: absTargetPath);
}

/// Verify that the version in the pubspec.yaml does not match the version in
/// the same pubspec.yaml in the repo's default branch. If the pubspec does not
/// exist in the repo's default branch, pass the validation.
Future<void> _stepBranchVersion({
  required String absTargetPath,
  required String displayPath,
  required Map<dynamic, dynamic> pubspecYaml,
  required String relPrefix,
}) async {
  final version = pubspecYaml['version']?.toString().trim() ?? '';
  if (version.isEmpty) {
    throw _StepFailedException(
      message: "Error: Could not find 'version' in $displayPath/pubspec.yaml.",
    );
  }

  final pubspecGitPath = '${relPrefix}pubspec.yaml';
  final defaultBranch = await _getDefaultBranch(absTargetPath);
  if (defaultBranch == null) {
    stdout.writeln(
      '==> [$displayPath] No default branch found in repository. Passing validation.',
    );
    return;
  }

  final catFileResult = await Process.run(
    'git',
    ['cat-file', '-e', '$defaultBranch:$pubspecGitPath'],
    runInShell: Platform.isWindows,
    workingDirectory: absTargetPath,
  );

  if (catFileResult.exitCode != 0) {
    stdout.writeln(
      '==> [$displayPath] $pubspecGitPath does not exist in default branch ($defaultBranch). Passing validation.',
    );
    return;
  }

  final showResult = await Process.run(
    'git',
    ['show', '$defaultBranch:$pubspecGitPath'],
    runInShell: Platform.isWindows,
    workingDirectory: absTargetPath,
  );
  if (showResult.exitCode != 0) {
    throw _StepFailedException(
      message:
          'Error: Unable to read $defaultBranch:$pubspecGitPath: ${showResult.stderr}',
    );
  }

  final defaultYaml = yaon.parse(showResult.stdout as String);
  final defaultBranchVersion = defaultYaml is Map
      ? (defaultYaml['version']?.toString().trim() ?? '')
      : '';

  if (version == defaultBranchVersion) {
    throw _StepFailedException(
      message:
          "Error: Version '$version' in $pubspecGitPath matches the version in default branch ($defaultBranch).",
    );
  }

  stdout.writeln(
    "==> [$displayPath] Verified version '$version' does not match $defaultBranch ('$defaultBranchVersion').",
  );
}

/// If build_runner is a dependency or a dev_dependency then run
/// "dart run build_runner build"
Future<void> _stepBuildRunner({
  required String absTargetPath,
  required String displayPath,
  required Map<dynamic, dynamic> pubspecYaml,
}) async {
  if (_hasDependency(pubspecYaml, 'build_runner', includeDev: true)) {
    stdout.writeln('==> [$displayPath] Running dart run build_runner build...');
    await _runCommand('dart', [
      'run',
      'build_runner',
      'build',
    ], workingDirectory: absTargetPath);
  } else {
    stdout.writeln(
      '==> [$displayPath] build_runner is not a dependency. Skipping.',
    );
  }
}

/// Verify that the version in the pubspec.yaml has an entry in the CHANGELOG.md
void _stepChangelogVersion({
  required String absTargetPath,
  required String displayPath,
  required FileSystem fs,
  required Map<dynamic, dynamic> pubspecYaml,
}) {
  final version = pubspecYaml['version']?.toString().trim() ?? '';
  if (version.isEmpty) {
    throw _StepFailedException(
      message: "Error: Could not find 'version' in $displayPath/pubspec.yaml.",
    );
  }

  final changelogFile = fs.file('$absTargetPath/CHANGELOG.md');
  if (!changelogFile.existsSync()) {
    throw _StepFailedException(
      message: "Error: CHANGELOG.md not found in '$displayPath'.",
    );
  }

  final changelogContent = changelogFile.readAsStringSync();
  if (!_hasChangelogEntry(changelogContent, version)) {
    throw _StepFailedException(
      message:
          "Error: Version '$version' in $displayPath/pubspec.yaml does not have an entry in $displayPath/CHANGELOG.md.",
    );
  }

  stdout.writeln(
    "==> [$displayPath] Verified version '$version' has an entry in CHANGELOG.md.",
  );
}

/// For each folder that exists, run dart format $folder. If files changed,
/// re-add them.
Future<void> _stepFormat({
  required String absTargetPath,
  required String displayPath,
  required FileSystem fs,
  bool setExitIfChanged = false,
}) async {
  final changedRegex = RegExp(r'\([1-9]\d* changed\)');

  for (final folder in _kDartFolders) {
    final dir = fs.directory('$absTargetPath/$folder');
    if (!dir.existsSync()) {
      continue;
    }

    stdout.writeln('==> [$displayPath] Running dart format $folder...');
    final formatResult = await Process.run(
      'dart',
      [
        'format',
        folder,
        if (setExitIfChanged) ...['--set-exit-if-changed'],
      ],
      runInShell: Platform.isWindows,
      workingDirectory: absTargetPath,
    );

    final out = (formatResult.stdout as String).trimRight();
    if (out.isNotEmpty) {
      stdout.writeln(out);
    }
    final err = (formatResult.stderr as String).trimRight();
    if (err.isNotEmpty) {
      stderr.writeln(err);
    }
    if (formatResult.exitCode != 0) {
      throw _StepFailedException(exitCode: formatResult.exitCode);
    }

    final diffResult = await Process.run(
      'git',
      ['diff', '--quiet', '--', folder],
      runInShell: Platform.isWindows,
      workingDirectory: absTargetPath,
    );

    if (diffResult.exitCode != 0 || changedRegex.hasMatch(out)) {
      stdout.writeln(
        '==> [$displayPath] Re-adding changed files in $folder...',
      );
      await _runCommand('git', [
        'add',
        '--',
        folder,
      ], workingDirectory: absTargetPath);
    }
  }
}

/// Run "dart pub get"
Future<void> _stepPubGet({
  required String absTargetPath,
  required String displayPath,
}) async {
  stdout.writeln('==> [$displayPath] Running dart pub get...');
  await _runCommand('dart', ['pub', 'get'], workingDirectory: absTargetPath);
}

/// Scans the `packages` folder (if present) and ensures `.pre-commit-config.yaml`
/// has a matching `all` step for every package in alphabetical order.
void _stepScanPackages({
  required String absTargetPath,
  required String displayPath,
  required FileSystem fs,
}) {
  final packagesDir = fs.directory('$absTargetPath/packages');
  if (!packagesDir.existsSync()) {
    stdout.writeln(
      '==> [$displayPath] No packages directory found. Passing scan_packages.',
    );
    return;
  }

  final fsPackages =
      packagesDir
          .listSync()
          .whereType<Directory>()
          .map((d) => fs.path.basename(d.path))
          .where((name) => !name.startsWith('.'))
          .toList()
        ..sort();

  var configFile = fs.file('$absTargetPath/.pre-commit-config.yaml');
  var configFileName = '.pre-commit-config.yaml';
  if (!configFile.existsSync()) {
    final fallbackFile = fs.file('$absTargetPath/.pre-commit-hooks.yaml');
    if (fallbackFile.existsSync()) {
      configFile = fallbackFile;
      configFileName = '.pre-commit-hooks.yaml';
    } else {
      throw _StepFailedException(
        message: "Error: .pre-commit-config.yaml not found in '$displayPath'.",
      );
    }
  }

  final rawContent = configFile.readAsStringSync();
  final parsedYaml = yaon.parse(rawContent);

  if (parsedYaml is Map) {
    final rootMap = Map<String, dynamic>.from(parsedYaml);
    final reposRaw = rootMap['repos'];
    if (reposRaw is! List || reposRaw.isEmpty) {
      throw _StepFailedException(
        message:
            "Error: '$configFileName' does not contain a valid 'repos' list.",
      );
    }

    final repos = reposRaw
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();

    var targetRepoIndex = repos.indexWhere((repoMap) {
      final repoUrl = repoMap['repo']?.toString() ?? '';
      if (repoUrl.contains('gh_tools')) {
        return true;
      }
      final hooks = repoMap['hooks'];
      if (hooks is List) {
        return hooks.whereType<Map>().any(
          (h) =>
              h['id'] == 'scan_packages' || _extractPackageFromHook(h) != null,
        );
      }
      return false;
    });
    if (targetRepoIndex == -1) {
      targetRepoIndex = 0;
    }

    final targetRepo = repos[targetRepoIndex];
    final hooksRaw = targetRepo['hooks'];
    final hooks = hooksRaw is List
        ? hooksRaw
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList()
        : <Map<String, dynamic>>[];

    final nonPackageHooks = <Map<String, dynamic>>[];
    final existingPackages = <String>[];
    var sawPackageHook = false;
    var orderCanonical = true;

    for (final hook in hooks) {
      final pkg = _extractPackageFromHook(hook);
      if (pkg != null) {
        sawPackageHook = true;
        existingPackages.add(pkg);
      } else {
        if (sawPackageHook) {
          orderCanonical = false;
        }
        nonPackageHooks.add(hook);
      }
    }

    if (orderCanonical && _listsEqual(existingPackages, fsPackages)) {
      stdout.writeln(
        '==> [$displayPath] All packages in $configFileName are in sync and in alphabetical order.',
      );
      return;
    }

    final updatedHooks = <Map<String, dynamic>>[
      ...nonPackageHooks,
      for (final pkg in fsPackages)
        {
          'id': 'all',
          'name': pkg,
          'args': ['--path=packages/$pkg'],
        },
    ];

    targetRepo['hooks'] = updatedHooks;
    rootMap['repos'] = repos;

    final buf = StringBuffer();
    _writeYamlMap(buf, rootMap, indent: 0);
    configFile.writeAsStringSync(buf.toString());

    throw _StepFailedException(
      message:
          'Alert: $configFileName was modified to sync with the packages folder. Please stage the updated $configFileName and re-run pre-commit.',
    );
  } else if (parsedYaml is List) {
    final hooks = parsedYaml
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();

    final nonPackageHooks = <Map<String, dynamic>>[];
    final existingPackages = <String>[];
    var sawPackageHook = false;
    var orderCanonical = true;

    for (final hook in hooks) {
      final pkg = _extractPackageFromHook(hook);
      if (pkg != null) {
        sawPackageHook = true;
        existingPackages.add(pkg);
      } else {
        if (sawPackageHook) {
          orderCanonical = false;
        }
        nonPackageHooks.add(hook);
      }
    }

    if (orderCanonical && _listsEqual(existingPackages, fsPackages)) {
      stdout.writeln(
        '==> [$displayPath] All packages in $configFileName are in sync and in alphabetical order.',
      );
      return;
    }

    final updatedHooks = <Map<String, dynamic>>[
      ...nonPackageHooks,
      for (final pkg in fsPackages)
        {
          'id': pkg,
          'name': 'Dart Pre-Commit ($pkg)',
          'description': 'Run all pre-commit steps for packages/$pkg.',
          'entry': 'dart_pre_commit --step=all --path=packages/$pkg',
          'language': 'dart',
          'files': r'\.dart$',
          'require_serial': true,
        },
    ];

    final buf = StringBuffer();
    _writeYamlList(buf, updatedHooks, blankLineBetweenItems: true, indent: 0);
    configFile.writeAsStringSync(buf.toString());

    throw _StepFailedException(
      message:
          'Alert: $configFileName was modified to sync with the packages folder. Please stage the updated $configFileName and re-run pre-commit.',
    );
  } else {
    throw _StepFailedException(
      message: "Error: Unable to parse '$configFileName'.",
    );
  }
}

/// If a "test" folder exists, and "flutter" is a dependency, run
/// "flutter test". If a "test" folder exists and "flutter" is not a
/// dependency, run "dart test".
Future<void> _stepTest({
  required String absTargetPath,
  required String displayPath,
  required FileSystem fs,
  required Map<dynamic, dynamic> pubspecYaml,
}) async {
  final testDir = fs.directory('$absTargetPath/test');
  if (!testDir.existsSync()) {
    stdout.writeln(
      '==> [$displayPath] No test directory found. Skipping tests.',
    );
    return;
  }

  if (_hasDependency(pubspecYaml, 'flutter')) {
    stdout.writeln('==> [$displayPath] Running flutter test...');
    await _runCommand('flutter', ['test'], workingDirectory: absTargetPath);
  } else {
    stdout.writeln('==> [$displayPath] Running dart test...');
    await _runCommand('dart', ['test'], workingDirectory: absTargetPath);
  }
}

class const _StepFailedException({
  final int exitCode = 1,
  final String? message,
}) implements Exception {}
