import 'dart:io';

import 'package:args/args.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:gh_tools/gh_tools.dart';
import 'package:gh_tools/src/util/pubspec.dart';
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
  'integration-test': 'Run "flutter test integration_test" or "dart test integration_test" if an "integration_test" folder exists.',
  'monorepo': 'Ensure .pre-commit-config.yaml and detect_changes workflows include all packages.',
  'pub-get': 'Run "dart pub get".',
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
    if (fs.directory(first).existsSync()) {
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
    if (step == 'monorepo') {
      _stepMonorepo(
        absTargetPath: absTargetPath,
        displayPath: displayPath,
        fs: fs,
      );
      exit(0);
    }
    if (step == 'install') {
      await _installHooks(
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
        await _stepIntegrationTest(
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
      case 'integration-test':
        await _stepIntegrationTest(
          absTargetPath: absTargetPath,
          displayPath: displayPath,
          fs: fs,
          pubspecYaml: pubspecYaml,
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
        await _stepIntegrationTest(
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
  stdout.writeln('Installing prek hooks...');

  final configFile = fs.file('$absTargetPath/.pre-commit-config.yaml');
  if (!configFile.existsSync()) {
    configFile.createSync(recursive: true);
  }

  final packagesDir = fs.directory('$absTargetPath/packages');
  if (packagesDir.existsSync()) {
    final config = <String, dynamic>{
      'repos': [
        {
          'repo': 'https://github.com/islandlifetechnologies/gh_tools',
          'rev': 'v${kPubspec.version}',
          'hooks': [
            {'id': 'monorepo', 'name': 'monorepo', 'priority': 1},
          ],
        },
      ],
    };

    configFile.writeAsStringSync(
      YamlWriter(allowUnquotedStrings: true).convert(config),
    );
    runMonorepoCheck(absTargetPath: absTargetPath, fs: fs);
  } else {
    const defaultSteps = [
      (id: 'pub-get', priority: 1),
      (id: 'build-runner', priority: 1),
      (id: 'format', priority: 2),
      (id: 'analyze', priority: 2),
      (id: 'test', priority: 2),
      (id: 'integration-test', priority: 2),
      (id: 'changelog-version', priority: 2),
      (id: 'branch-version', priority: 2),
    ];

    final config = <String, dynamic>{
      'repos': [
        {
          'repo': 'https://github.com/islandlifetechnologies/gh_tools',
          'rev': 'v${kPubspec.version}',
          'hooks': [
            for (final step in defaultSteps)
              {'id': step.id, 'priority': step.priority},
          ],
        },
      ],
    };

    configFile.writeAsStringSync(
      YamlWriter(allowUnquotedStrings: true).convert(config),
    );
  }

  await _runCommand('prek', ['install', '-f'], workingDirectory: absTargetPath);
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

    if (changedRegex.hasMatch(out)) {
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

void _stepMonorepo({
  required String absTargetPath,
  required String displayPath,
  required FileSystem fs,
}) {
  final result = runMonorepoCheck(absTargetPath: absTargetPath, fs: fs);
  if (result.skipped) {
    stdout.writeln(
      '==> [$displayPath] Not a multi-package monorepo. Skipping monorepo check.',
    );
    return;
  }

  if (result.modifiedFiles.isNotEmpty) {
    final files = result.modifiedFiles.join(', ');
    throw _StepFailedException(
      message:
          'Alert: Updated $files to sync with the packages folder. Please stage the updated file(s) and re-run prek.',
    );
  }

  stdout.writeln('==> [$displayPath] Monorepo configuration is in sync.');
}

/// Runs `flutter test` or `dart test` (with optional [extraArgs]) if
/// [folderName] exists in [absTargetPath].
Future<void> _runTestFolder({
  required String absTargetPath,
  required String displayPath,
  List<String> extraArgs = const [],
  required String folderName,
  required FileSystem fs,
  required Map<dynamic, dynamic> pubspecYaml,
}) async {
  final dir = fs.directory('$absTargetPath/$folderName');
  if (!dir.existsSync()) {
    stdout.writeln(
      '==> [$displayPath] No $folderName directory found. Skipping.',
    );
    return;
  }

  final isFlutter = _hasDependency(pubspecYaml, 'flutter');
  final executable = isFlutter ? 'flutter' : 'dart';
  final args = ['test', ...extraArgs];
  stdout.writeln('==> [$displayPath] Running $executable ${args.join(' ')}...');
  await _runCommand(executable, args, workingDirectory: absTargetPath);
}

/// If an "integration_test" folder exists, and "flutter" is a dependency, run
/// "flutter test integration_test". If "flutter" is not a dependency, run
/// "dart test integration_test".
Future<void> _stepIntegrationTest({
  required String absTargetPath,
  required String displayPath,
  required FileSystem fs,
  required Map<dynamic, dynamic> pubspecYaml,
}) => _runTestFolder(
  absTargetPath: absTargetPath,
  displayPath: displayPath,
  extraArgs: const ['integration_test'],
  folderName: 'integration_test',
  fs: fs,
  pubspecYaml: pubspecYaml,
);

/// If a "test" folder exists, and "flutter" is a dependency, run
/// "flutter test". If a "test" folder exists and "flutter" is not a
/// dependency, run "dart test".
Future<void> _stepTest({
  required String absTargetPath,
  required String displayPath,
  required FileSystem fs,
  required Map<dynamic, dynamic> pubspecYaml,
}) => _runTestFolder(
  absTargetPath: absTargetPath,
  displayPath: displayPath,
  folderName: 'test',
  fs: fs,
  pubspecYaml: pubspecYaml,
);

class const _StepFailedException({
  final int exitCode = 1,
  final String? message,
}) implements Exception {}
