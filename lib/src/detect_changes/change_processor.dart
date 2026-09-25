import 'dart:convert';
import 'dart:io';

import 'package:file/local.dart';
import 'package:gh_tools/gh_tools.dart';
import 'package:github/github.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';

/// Detects file changes in a GitHub push or pull request event
/// and evaluates them against defined filters.
class ChangeProcessor {
  /// Creates a change processor with the given [filters] and [gh] client.
  ChangeProcessor({
    required this.filters,
    required this._gh,
    @visibleForTesting Map<String, String>? env,
  }) : _env = env ?? Platform.environment;

  static const kEnvGitHubEventName = 'GITHUB_EVENT_NAME';
  static const kEnvGitHubRefName = 'GITHUB_REF_NAME';
  static const kEnvGitHubRepository = 'GITHUB_REPOSITORY';
  static const kEnvGitHubSha = 'GITHUB_SHA';

  /// Named filters to evaluate against changed files.
  final Map<String, Filters> filters;

  final Map<String, String> _env;
  final GitHub _gh;
  final _logger = Logger('ChangeProcessor');

  /// Processes event changes and writes outputs if GITHUB_OUTPUT is set.
  ///
  /// Returns a map of filter name to match status (`true` / `false`).
  Future<Map<String, bool>> process() async {
    final repoStr = _env[kEnvGitHubRepository];
    if (repoStr == null || repoStr.isEmpty) {
      throw StateError('Missing $kEnvGitHubRepository');
    }
    final repo = RepositorySlug.full(repoStr);

    final ghType = _env[kEnvGitHubEventName];
    final ref = _env[kEnvGitHubRefName] ?? '';

    final client = GitHubClient(gh: _gh);
    final files = <String>[];

    if (ghType == 'pull_request') {
      final prNumber = int.tryParse(ref.split('/').first);
      if (prNumber == null) {
        _logger.severe('Invalid PR number: "$ref"');
        throw FormatException('Invalid PR number: $ref');
      }
      files.addAll(await client.listPrFiles(repo, prNumber));
    } else if (ghType == 'push') {
      final sha = _env[kEnvGitHubSha];
      if (sha == null || sha.isEmpty) {
        _logger.severe('Missing $kEnvGitHubSha');
        throw StateError('Missing $kEnvGitHubSha');
      }
      files.addAll(await client.listPushFiles(repo, sha));
    } else {
      _logger.severe('Unsupported event: "$ghType"');
      throw UnsupportedError('Unsupported event: $ghType');
    }
    files.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final evaluator = Evaluator();
    final result = <String, bool>{
      for (final entry in filters.entries)
        entry.key: evaluator.evaluate(files: files, filters: entry.value),
    };

    _logger.info('Results:');
    for (final entry in result.entries) {
      _logger.info('  ${entry.key}: ${entry.value}');
    }

    final envFile = _env['GITHUB_OUTPUT'];
    final fs = LocalFileSystem();
    if (envFile != null && envFile.isNotEmpty) {
      await GitHubOutputEmitter(fs: fs).emit({
        'CHANGES': json.encode(result),
        'CHANGES_ARRAY': json.encode(
          result.entries.where((e) => e.value).map((e) => e.key).toList(),
        ),
      }, outputFile: fs.file(envFile));
    } else {
      _logger.info('No GITHUB_OUTPUT set; skipping emit.');
    }

    return result;
  }
}
