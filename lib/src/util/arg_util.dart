// ignore_for_file: avoid_print

import 'dart:io';

import 'package:args/args.dart';
import 'package:gh_tools/gh_tools.dart';
import 'package:gh_tools/src/util/pubspec.dart';
import 'package:github/github.dart';

/// Wraps [ArgParser] with common options (--help, --version).
class ArgUtil({required final ArgParser parser}) {
  /// Parses [args] and handles --help / --version automatically.
  ArgUtilResults parse(
    List<String> args, {
    bool allowExit = true,
    bool repository = false,
    bool token = false,
  }) {
    parser
      ..addFlag('help', abbr: 'h', help: 'Show usage.', negatable: false)
      ..addFlag('version', abbr: 'v', help: 'Show version.', negatable: false);

    if (repository) {
      parser.addOption(
        'repository',
        abbr: 'r',
        help: 'Repository to utilize.  Defaults to the current repository.',
      );
    }

    if (token) {
      parser.addOption('token', abbr: 't', help: 'GitHub access token.');
    }

    final result = parser.parse(args);

    final help = result['help'] as bool;
    final version = result['version'] as bool;

    if (help || version) {
      print('${Platform.executable} ${kPubspec.version}');
      if (help) {
        print('');
        print(parser.usage);
      }
      if (allowExit) {
        exit(0);
      }
      throw UnsupportedError('Exited with code 0');
    }

    String? ghToken;
    if (token) {
      ghToken =
          (result['token'] ??
                  Platform.environment['GITHUB_TOKEN'] ??
                  const String.fromEnvironment('GITHUB_TOKEN'))
              .trim();

      if (ghToken != null && ghToken.isEmpty) {
        stderr.writeln('Missing GITHUB_TOKEN.');
        exit(1);
      }
    }

    RepositorySlug? ghRepo;
    if (repository) {
      ghRepo = getRepositorySlug(repository: result['repository'] as String?);
    }

    return ArgUtilResults(parsed: result, repository: ghRepo, token: ghToken);
  }
}

class ArgUtilResults({
  required final ArgResults parsed,
  required final RepositorySlug? repository,
  required final String? token,
}) {
  dynamic operator [](String name) {
    return parsed[name];
  }
}
