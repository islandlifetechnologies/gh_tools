import 'dart:io';

import 'package:github/github.dart';

/// Resolves repository slugs from environment variables or git remote URL.
class RepoScanner({final String hostname = 'github.com'}) {
  /// Returns the [RepositorySlug] from `GITHUB_REPOSITORY` or git remote
  /// origin.
  RepositorySlug getRepoSlugFromEnvironment({Map<String, String>? env}) {
    final environment = env ?? Platform.environment;
    var repoString = environment['GITHUB_REPOSITORY']?.trim();

    if (repoString == null || repoString.isEmpty) {
      repoString = getRepoSlugFromDirectory().fullName;
    }

    return RepositorySlug.full(repoString.trim());
  }

  /// Parses the [RepositorySlug] from git remote origin URL in the current
  /// directory.
  RepositorySlug getRepoSlugFromDirectory() {
    final result = Process.runSync('git', ['remote', 'get-url', 'origin']);

    if (result.exitCode != 0) {
      throw ProcessException(
        'git',
        ['remote', 'get-url', 'origin'],
        (result.stderr as String).trim(),
        result.exitCode,
      );
    }

    final remoteUrl = result.stdout.toString().trim();
    final escapedHost = RegExp.escape(hostname);
    final pattern = RegExp('$escapedHost[:/](.+?)/(.+?)(?:\\.git)?\$');
    final match = pattern.firstMatch(remoteUrl);

    if (match == null) {
      throw FormatException('Invalid repo URL: $remoteUrl');
    }

    return RepositorySlug(match.group(1)!, match.group(2)!);
  }
}
