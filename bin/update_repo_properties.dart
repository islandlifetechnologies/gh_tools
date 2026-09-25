import 'dart:io';

import 'package:args/args.dart';
import 'package:gh_tools/gh_tools.dart';
import 'package:github/github.dart';
import 'package:yaon/yaon.dart';

void main(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'properties',
      abbr: 'p',
      defaultsTo: '.github/properties.yaml',
      help: 'Properties file path (YAML/JSON).',
    )
    ..addOption('token', help: 'GitHub personal access token.');

  final parsed = CliParser(parser: parser).parse(args);
  final fileName = parsed['properties'] as String;
  final file = File(fileName);

  if (!file.existsSync()) {
    stderr.writeln('File not found: "$fileName"');
    exit(1);
  }

  try {
    final token =
        (parsed['token'] as String? ??
                Platform.environment['GITHUB_TOKEN'] ??
                const String.fromEnvironment('GITHUB_TOKEN'))
            .trim();

    if (token.isEmpty) {
      stderr.writeln('Missing GITHUB_TOKEN.');
      exit(1);
    }

    final parsedYaml = yaon.parse(file.readAsStringSync());
    if (parsedYaml is! Map) {
      stderr.writeln('Properties file must contain a map.');
      exit(1);
    }
    final yaml = Map<String, dynamic>.from(parsedYaml);

    final gh = GitHub(auth: Authentication.bearerToken(token));
    final client = GitHubClient(gh: gh);

    await client.updateProperties(
      RepoScanner().getRepoSlugFromEnvironment(),
      yaml,
    );
    exit(0);
  } catch (e, stack) {
    stderr.writeln('Error: $e');
    stderr.writeln(stack);
    exit(1);
  }
}
