import 'package:file/file.dart';
import 'package:yaon/yaon.dart';

/// Result of running the `monorepo` pre-commit check.
class const MonorepoCheckResult({
  required final List<String> modifiedFiles,
  required final bool skipped,
}) {}

/// Checks and synchronizes `.pre-commit-config.yaml` and GitHub Actions
/// workflows that use `detect_changes` in multi-package monorepos.
///
/// Only acts when `packages/` exists and contains more than one package.
MonorepoCheckResult runMonorepoCheck({
  required String absTargetPath,
  required FileSystem fs,
}) => _runMonorepoCheck(absTargetPath: absTargetPath, fs: fs);

/// Parses `ignore_packages` YAML encoded inside `#` comments in [content].
///
/// Supports both single-line (`# ignore_packages: [a, b]`) and multi-line
/// comment blocks:
/// ```yaml
/// # ignore_packages:
/// #   - a
/// #   - b
/// ```
Set<String> parseIgnoredPackages(String content) =>
    _parseIgnoredPackages(content);

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
      final pkg = _packageNameFromPath(token.substring('--path='.length));
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

Set<String> _parseIgnoredPackages(String content) {
  final ignored = <String>{};
  final lines = content.split(RegExp(r'\r?\n'));
  final commentLineRegex = RegExp(r'^\s*#(.*)$');

  for (var i = 0; i < lines.length; i++) {
    final match = commentLineRegex.firstMatch(lines[i]);
    if (match == null) {
      continue;
    }
    final body = match.group(1) ?? '';
    final trimmedLeft = body.trimLeft();
    if (!trimmedLeft.startsWith('ignore_packages:')) {
      continue;
    }

    final baseIndent = body.length - trimmedLeft.length;
    final yamlLines = <String>[trimmedLeft];
    final afterColon = trimmedLeft.substring('ignore_packages:'.length).trim();

    if (afterColon.isEmpty) {
      for (var j = i + 1; j < lines.length; j++) {
        final nextMatch = commentLineRegex.firstMatch(lines[j]);
        if (nextMatch == null) {
          break;
        }
        final nextBody = nextMatch.group(1) ?? '';
        final nextTrimmed = nextBody.trimLeft();
        if (nextTrimmed.isEmpty) {
          continue;
        }
        final nextIndent = nextBody.length - nextTrimmed.length;
        if (nextIndent < baseIndent ||
            (nextIndent == baseIndent && !nextTrimmed.startsWith('-'))) {
          break;
        }
        final stripped = nextBody.length >= baseIndent
            ? nextBody.substring(baseIndent)
            : nextTrimmed;
        yamlLines.add(stripped);
        i = j;
      }
    }

    try {
      final parsed = yaon.parse(yamlLines.join('\n'));
      if (parsed is Map && parsed['ignore_packages'] is List) {
        for (final item in parsed['ignore_packages'] as List) {
          final name = item?.toString().trim() ?? '';
          if (name.isNotEmpty) {
            ignored.add(name);
          }
        }
      }
    } catch (_) {
      // Ignore malformed comment YAML.
    }
  }

  return ignored;
}

MonorepoCheckResult _runMonorepoCheck({
  required String absTargetPath,
  required FileSystem fs,
}) {
  final packagesDir = fs.directory('$absTargetPath/packages');
  if (!packagesDir.existsSync()) {
    return const MonorepoCheckResult(modifiedFiles: [], skipped: true);
  }

  final fsPackages =
      packagesDir
          .listSync()
          .whereType<Directory>()
          .map((d) => fs.path.basename(d.path))
          .where((name) => !name.startsWith('.'))
          .toList()
        ..sort();

  if (fsPackages.length <= 1) {
    return const MonorepoCheckResult(modifiedFiles: [], skipped: true);
  }

  final modifiedFiles = <String>[];

  final preCommitModified = _syncPreCommitConfig(
    absTargetPath: absTargetPath,
    fs: fs,
    fsPackages: fsPackages,
  );
  if (preCommitModified != null) {
    modifiedFiles.add(preCommitModified);
  }

  modifiedFiles.addAll(
    _syncWorkflows(
      absTargetPath: absTargetPath,
      fs: fs,
      fsPackages: fsPackages,
    ),
  );

  return MonorepoCheckResult(modifiedFiles: modifiedFiles, skipped: false);
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

bool _hasFlagValue(List<String> tokens, String flag, String value) {
  for (var i = 0; i < tokens.length - 1; i++) {
    if (tokens[i] == flag && tokens[i + 1] == value) {
      return true;
    }
  }
  return false;
}

bool _isDetectChangesWorkflow(String content) {
  final usesGhTools =
      RegExp(r'uses:\s*[^\s]*gh_tools').hasMatch(content) ||
      RegExp(r'dart\s+pub\s+global\s+activate\s+gh_tools').hasMatch(content) ||
      content.contains('gh_tools:detect_changes');
  final invokesDetectChanges = RegExp(r'\bdetect_changes\b').hasMatch(content);
  return usesGhTools && invokesDetectChanges;
}

bool _isPackageFilterMap(Map<dynamic, dynamic> filtersMap) {
  for (final value in filtersMap.values) {
    if (value is Map && value['paths'] is List) {
      final paths = value['paths'] as List;
      if (paths.any((p) => p.toString().contains('packages/'))) {
        return true;
      }
    } else if (value is List) {
      if (value.any((p) => p.toString().contains('packages/'))) {
        return true;
      }
    } else if (value is String && value.contains('packages/')) {
      return true;
    }
  }
  return false;
}

String _leadingCommentsPrefix(String rawContent) {
  final lines = rawContent.split(RegExp(r'\r?\n'));
  final prefixLines = <String>[];
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      prefixLines.add(line);
    } else {
      break;
    }
  }
  if (prefixLines.isEmpty) {
    return '';
  }
  return '${prefixLines.join('\n')}\n';
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

String? _packageNameFromPath(String path) {
  final normalized = path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
  final match = RegExp(r'(?:^|/)packages/([^/]+)$').firstMatch(normalized);
  return match?.group(1);
}

String? _syncPreCommitConfig({
  required String absTargetPath,
  required FileSystem fs,
  required List<String> fsPackages,
}) {
  final configFile = fs.file('$absTargetPath/.pre-commit-config.yaml');
  if (!configFile.existsSync()) {
    return null;
  }

  final rawContent = configFile.readAsStringSync();
  final ignored = _parseIgnoredPackages(rawContent);
  final expectedPackages = fsPackages
      .where((p) => !ignored.contains(p))
      .toList();

  final parsedYaml = yaon.parse(rawContent);
  if (parsedYaml is! Map) {
    throw const FormatException(
      "Error: '.pre-commit-config.yaml' is not a valid YAML map.",
    );
  }

  final rootMap = Map<String, dynamic>.from(parsedYaml);
  final reposRaw = rootMap['repos'];
  if (reposRaw is! List || reposRaw.isEmpty) {
    throw const FormatException(
      "Error: '.pre-commit-config.yaml' does not contain a valid 'repos' list.",
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
            h['id'] == 'monorepo' ||
            h['id'] == 'scan-packages' ||
            h['id'] == 'scan_packages' ||
            _extractPackageFromHook(h) != null,
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
  var allPackagePrioritiesOk = true;
  Map<String, dynamic>? existingMonorepoHook;

  for (final hook in hooks) {
    final pkg = _extractPackageFromHook(hook);
    if (pkg != null) {
      sawPackageHook = true;
      existingPackages.add(pkg);
      if (hook['priority'] != 2) {
        allPackagePrioritiesOk = false;
      }
    } else if (hook['id'] == 'monorepo') {
      if (sawPackageHook || nonPackageHooks.isNotEmpty) {
        orderCanonical = false;
      }
      existingMonorepoHook = hook;
    } else {
      if (sawPackageHook) {
        orderCanonical = false;
      }
      nonPackageHooks.add(hook);
    }
  }

  final hasMonorepoAtTop =
      existingMonorepoHook != null &&
      existingMonorepoHook['priority'] == 1 &&
      orderCanonical;

  if (hasMonorepoAtTop &&
      allPackagePrioritiesOk &&
      _listsEqual(existingPackages, expectedPackages)) {
    return null;
  }

  final monorepoHook = <String, dynamic>{
    ...?existingMonorepoHook,
    'id': 'monorepo',
    'name': existingMonorepoHook?['name'] ?? 'monorepo',
    'priority': 1,
  };

  final updatedHooks = <Map<String, dynamic>>[
    monorepoHook,
    ...nonPackageHooks,
    for (final pkg in expectedPackages)
      {
        'id': 'all',
        'name': pkg,
        'args': ['--path=packages/$pkg'],
        'priority': 2,
      },
  ];

  targetRepo['hooks'] = updatedHooks;
  rootMap['repos'] = repos;

  final buf = StringBuffer(_leadingCommentsPrefix(rawContent));
  _writeYamlMap(buf, rootMap, indent: 0);
  configFile.writeAsStringSync(buf.toString());
  return '.pre-commit-config.yaml';
}

List<String> _syncWorkflows({
  required String absTargetPath,
  required FileSystem fs,
  required List<String> fsPackages,
}) {
  final workflowsDir = fs.directory('$absTargetPath/.github/workflows');
  if (!workflowsDir.existsSync()) {
    return const [];
  }

  final workflowFiles =
      workflowsDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.yaml') || f.path.endsWith('.yml'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final modified = <String>[];
  for (final file in workflowFiles) {
    final rawContent = file.readAsStringSync();
    if (!_isDetectChangesWorkflow(rawContent)) {
      continue;
    }

    final ignored = _parseIgnoredPackages(rawContent);
    final expectedPackages = fsPackages
        .where((p) => !ignored.contains(p))
        .toList();

    final updated = _updateWorkflowFilters(
      expectedPackages: expectedPackages,
      rawContent: rawContent,
    );
    if (updated != null && updated != rawContent) {
      file.writeAsStringSync(updated);
      modified.add('.github/workflows/${fs.path.basename(file.path)}');
    }
  }

  return modified;
}

String? _updateWorkflowFilters({
  required List<String> expectedPackages,
  required String rawContent,
}) {
  final eol = rawContent.contains('\r\n') ? '\r\n' : '\n';
  final lines = rawContent.split(RegExp(r'\r?\n'));
  final blockHeaderRegex = RegExp(r'^(\s*)filters:\s*\|[+-]?\s*$');

  var changed = false;
  final outLines = <String>[];

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final headerMatch = blockHeaderRegex.firstMatch(line);
    if (headerMatch == null) {
      outLines.add(line);
      continue;
    }

    final headerIndent = headerMatch.group(1)!.length;
    final blockLines = <String>[];
    var j = i + 1;
    for (; j < lines.length; j++) {
      final blockLine = lines[j];
      if (blockLine.trim().isEmpty) {
        blockLines.add(blockLine);
        continue;
      }
      final indent = blockLine.length - blockLine.trimLeft().length;
      if (indent <= headerIndent) {
        break;
      }
      blockLines.add(blockLine);
    }

    // Trim trailing blank lines from the block so they stay outside.
    final trailingBlanks = <String>[];
    while (blockLines.isNotEmpty && blockLines.last.trim().isEmpty) {
      trailingBlanks.insert(0, blockLines.removeLast());
    }

    final nonEmptyIndents = blockLines
        .where((l) => l.trim().isNotEmpty)
        .map((l) => l.length - l.trimLeft().length);
    final contentIndent = nonEmptyIndents.isEmpty
        ? headerIndent + 2
        : nonEmptyIndents.reduce((a, b) => a < b ? a : b);

    final dedented = blockLines
        .map(
          (l) => l.length >= contentIndent
              ? l.substring(contentIndent)
              : l.trimLeft(),
        )
        .join('\n');

    dynamic parsedFilters;
    try {
      parsedFilters = yaon.parse(dedented);
    } catch (_) {
      parsedFilters = null;
    }

    if (parsedFilters is! Map || !_isPackageFilterMap(parsedFilters)) {
      outLines
        ..add(line)
        ..addAll(blockLines)
        ..addAll(trailingBlanks);
      i = j - 1;
      continue;
    }

    final filtersMap = Map<String, dynamic>.from(parsedFilters);
    final missing = expectedPackages
        .where((pkg) => !filtersMap.containsKey(pkg))
        .toList();

    if (missing.isEmpty) {
      outLines
        ..add(line)
        ..addAll(blockLines)
        ..addAll(trailingBlanks);
      i = j - 1;
      continue;
    }

    changed = true;
    for (final pkg in missing) {
      filtersMap[pkg] = {
        'paths': ['packages/$pkg/**'],
      };
    }

    final sortedKeys = filtersMap.keys.toList()..sort();
    final sortedMap = <String, dynamic>{
      for (final key in sortedKeys) key: filtersMap[key],
    };

    final buf = StringBuffer();
    _writeYamlMap(buf, sortedMap, indent: contentIndent);
    final renderedBlock = buf.toString().trimRight().split('\n');

    outLines
      ..add(line)
      ..addAll(renderedBlock)
      ..addAll(trailingBlanks);
    i = j - 1;
  }

  if (!changed) {
    return null;
  }
  return outLines.join(eol);
}

void _writeYamlList(
  StringBuffer buf,
  List<dynamic> list, {
  required int indent,
}) {
  final prefix = ' ' * indent;
  for (final item in list) {
    if (item is Map) {
      buf.write('$prefix- ');
      _writeYamlMap(buf, item, firstLineUnindented: true, indent: indent + 2);
    } else {
      buf.writeln('$prefix- ${_formatYamlScalar(item)}');
    }
  }
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
    final prefix = (firstLineUnindented && i == 0) ? '' : ' ' * indent;
    final key = entry.key.toString();
    final value = entry.value;

    if (value is Map) {
      buf.writeln('$prefix$key:');
      _writeYamlMap(buf, value, indent: indent + 2);
    } else if (value is List) {
      if (value.isEmpty) {
        buf.writeln('$prefix$key: []');
      } else if (value.every((e) => e is! Map && e is! List)) {
        final items = value.map(_formatYamlScalar).join(', ');
        buf.writeln('$prefix$key: [$items]');
      } else {
        buf.writeln('$prefix$key:');
        _writeYamlList(buf, value, indent: indent + 2);
      }
    } else {
      buf.writeln('$prefix$key: ${_formatYamlScalar(value)}');
    }
  }
}
