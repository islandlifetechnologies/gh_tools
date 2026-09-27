// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:file/local.dart';
import 'package:gh_tools/gh_tools.dart';
import 'package:github/github.dart';
import 'package:logging/logging.dart';
import 'package:yaon/yaon.dart';

final _logger = Logger('main');
Future<void> main(List<String> args) async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
    if (record.error != null) {
      print('${record.error}');
    }
    if (record.stackTrace != null) {
      print('${record.stackTrace}');
    }
  });

  final parser = ArgParser();
  parser
    ..addOption(
      'branch',
      defaultsTo: null,
      help: "Branch name to scan the project for.  Default to the repository's default branch.",
    )
    ..addOption(
      'changelog',
      defaultsTo: 'true',
      help: 'Scan for the version to exist in the changelog and fail if not.',
    )
    ..addOption(
      'dry-run',
      defaultsTo: 'false',
      help: 'Perform all calculations but make no changes.',
    )
    ..addOption(
      'major',
      defaultsTo: 'true',
      help: 'Add a tag for the major version; ie: v1',
    )
    ..addOption(
      'minor',
      defaultsTo: 'true',
      help: 'Add a tag for the minor version; ie: v1.2',
    )
    ..addOption(
      'overwrite',
      defaultsTo: 'true',
      help: 'Overwrite the existing tag if it exsts; fails if false.',
    )
    ..addOption(
      'path',
      defaultsTo: '.',
      help: 'The path to the project; default is current directory.',
    )
    ..addOption('prefix', defaultsTo: 'v', help: 'Prefix for the version tag.');

  final parsed = ArgUtil(parser: parser)
      .parse(args, repository: true, token: true);
  final path = parsed['path'];

  final fs = LocalFileSystem();

  final useChangelog = parsed['changelog']?.toString().toLowerCase() == 'true';
  final useMajor = parsed['major']?.toString().toLowerCase() == 'true';
  final useMinor = parsed['minor']?.toString().toLowerCase() == 'true';
  final dryRun = parsed['dry-run']?.toString().toLowerCase() == 'true';
  final overwrite = parsed['overwrite']?.toString().toLowerCase() == 'true';
  final prefix = parsed['prefix'];
  var branchName = parsed['branch'] as String? ?? '';
  final pubspec = fs.file('$path/pubspec.yaml');

  if (!pubspec.existsSync()) {
    throw Exception('Unable to load [$path/pubspec.yaml] file.');
  }

  String? changelog;

  if (useChangelog) {
    final file = fs.file('$path/CHANGELOG.md');
    if (!file.existsSync()) {
      throw Exception('Unable to load [$path/CHANGELOG.md] file.');
    }

    changelog = file.readAsStringSync();
  }

  final yaml = yaon.parse(pubspec.readAsStringSync());

  final version = yaml['version']?.toString();

  if (version == null) {
    throw Exception(
      'Unable to find a version attribute in the [$path/pubspec.yaml].',
    );
  }

  final slug = parsed.repository!;
  final token = parsed.token!;

  final options = {
    'branch': branchName,
    'changelog': useChangelog,
    'dryRun': dryRun,
    'major': useMajor,
    'minor': useMinor,
    'overwrite': overwrite,
    'path': path,
    'prefix': prefix,
    'slug': slug,
    'version': version,
  };
  _logger.info('Options:');
  for (final entry in options.entries) {
    _logger.info('  • [${entry.key}]: ${entry.value}');
  }
  _logger.info('');

  final gh = GitHub(auth: Authentication.withToken(token));

  final tags = await gh.repositories.listTags(slug).toList();
  final repo = await gh.repositories.getRepository(slug);
  branchName = branchName.isNotEmpty ? branchName : repo.defaultBranch;
  final branch = await gh.repositories.getBranch(slug, branchName);
  final sha = branch.commit!.sha!;

  final tagCreated = await _createTag(
    changelog: changelog,
    dryRun: dryRun,
    gh: gh,
    overwrite: overwrite,
    prefix: prefix,
    sha: sha,
    slug: slug,
    tags: tags,
    version: version,
  );

  final major = version.split('.').first;
  if (tagCreated && useMajor) {
    await _createTag(
      changelog: changelog,
      dryRun: dryRun,
      gh: gh,
      prefix: prefix,
      sha: sha,
      slug: slug,
      tags: tags,
      version: major,
    );
  }

  if (tagCreated && useMinor) {
    final minor = version.split('.')[1];
    await _createTag(
      changelog: changelog,
      dryRun: dryRun,
      gh: gh,
      prefix: prefix,
      sha: sha,
      slug: slug,
      tags: tags,
      version: '$major.$minor',
    );
  }

  exit(exitCode);
}

Future<bool> _createTag({
  String? changelog,
  required bool dryRun,
  required GitHub gh,
  bool overwrite = true,
  required String prefix,
  required String sha,
  required RepositorySlug slug,
  required List<Tag> tags,
  required String version,
}) async {
  var result = false;
  Tag? tag;
  final tagName = '$prefix$version';

  for (final t in tags) {
    if (t.name == tagName) {
      tag = t;
      _logger.info('Tag exists: ${t.name}');
      break;
    }
  }

  if (!overwrite && tag != null) {
    _logger.info('Aborting because tag exists and overwrite is false.');
  } else {
    final cl = changelog;
    String? changes;
    if (cl != null) {
      _logger.info('Looking for changes for tag: $tagName');

      final scanner = ChangelogScanner(cl);
      changes =
          '''
Release

${scanner.getChanges(version)}
''';

      _logger.info('''
[CHANGELOG]: $version

$changes''');
    } else {
      changes = 'Release $version';
    }

    if (dryRun) {
      result = true;
      _logger.info('Dry Run Complete: [$tagName]');
    } else {
      if (tag != null) {
        final response = await gh.request(
          'delete',
          '/repos/${slug.owner}/${slug.name}/git/refs/tags/${tag.name}',
        );
        if (response.statusCode >= 300) {
          throw Exception('Unable to get response for deleting tag.');
        }
        _logger.info('Deleted Tag: [$tagName]');
      }

      var response = await gh.request(
        'post',
        '/repos/${slug.owner}/${slug.name}/git/tags',
        body: utf8.encode(
          json.encode({
            'message': changes,
            'object': sha,
            'tag': tagName,
            'type': 'commit',
          }),
        ),
      );
      if (response.statusCode >= 300) {
        _logger.severe('''Error on response:
Code: ${response.statusCode}
Body:
${response.body}
''');
        throw Exception('Unable to get response for creating tag.');
      }

      _logger.info('Created Ref for Tag: [$tagName]');

      final responseBody = json.decode(response.body);
      final tagSha = responseBody['sha'];
      response = await gh.request(
        'post',
        '/repos/${slug.owner}/${slug.name}/git/refs',
        body: utf8.encode(
          json.encode({'ref': 'refs/tags/$tagName', 'sha': tagSha}),
        ),
      );
      if (response.statusCode >= 300) {
        _logger.severe('''Error on response:
Code: ${response.statusCode}
Body:
${response.body}
''');
        throw Exception('Unable to get response for creating tag.');
      }

      _logger.info('Created Tag: [$tagName]');
      result = true;
    }
  }

  return result;
}
