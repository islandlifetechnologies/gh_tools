import 'dart:io';

import 'package:github/github.dart';
import 'package:logging/logging.dart';

RepositorySlug getRepositorySlug({String? repository}) {
  final logger = Logger('RepositorySlug');
  RepositorySlug? slug;

  if (repository != null && repository.trim().isNotEmpty) {
    final repo = repository;

    slug = RepositorySlug.full(repo);
    logger.info('Discovered CLI SLUG: $repo');
  } else if (Platform.environment['GITHUB_REPOSITORY']?.isNotEmpty == true) {
    final repo = Platform.environment['GITHUB_REPOSITORY']!;

    slug = RepositorySlug.full(repo);
    logger.info('Discovered ENV SLUG: $repo');
  } else {
    final ghResult = Process.runSync('git', ['remote', 'show', 'origin']);
    final ghOutput = ghResult.stdout;

    logger.info('GitHub Output:\n$ghOutput');

    final regex = RegExp(
      r'Push[^:]*:[^:]*:\/\/github.com\/(?<org>[^\/]*)\/(?<repo>[^\n\.\/]*)',
    );
    final matches = regex.allMatches(ghOutput.toString());

    for (final match in matches) {
      final org = match.namedGroup('org');
      final repo = match.namedGroup('repo');

      if (org != null && repo != null) {
        slug = RepositorySlug(org, repo);

        logger.info('Discovered SLUG: $org/$repo');
        break;
      }
    }
  }

  if (slug == null) {
    throw Exception('Unable to determine GitHub SLUG');
  }

  return slug;
}
