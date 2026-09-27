import 'dart:io';

import 'package:args/args.dart';
import 'package:gh_tools/gh_tools.dart';
import 'package:github/github.dart';
import 'package:logging/logging.dart';
import 'package:yaon/yaon.dart';

void main(List<String> args) async {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    stdout.writeln('${record.level.name}: ${record.message}');
  });

  final parser = ArgParser()
    ..addOption(
      'filters',
      mandatory: true,
      help: 'Filter definitions (YAML/JSON).',
    )
    ..addOption(
      'mode',
      defaultsTo: 'or',
      allowed: ['and', 'or'],
      help: 'Default filter mode. And requires all filters to match, or will match on any filter.',
    );

  final parsed = ArgUtil(parser: parser).parse(args, token: true);
  final filtersRaw = parsed['filters'] as String?;

  if (filtersRaw == null || filtersRaw.trim().isEmpty) {
    stderr.writeln('Missing "filters" argument.');
    exit(1);
  }

  try {
    final token = parsed.token!;

    final defaultMode = FilterMode.lookup(parsed['mode'] as String?);
    final yaml = yaon.parse(filtersRaw);

    if (yaml is! Map) {
      stderr.writeln('Filters must be a YAML/JSON map.');
      exit(1);
    }

    final parsedFilters = <String, Filters>{
      for (final entry in yaml.entries)
        entry.key.toString(): Filters.fromJson(
          entry.value,
          defaultMode: defaultMode,
        ),
    };

    final gh = GitHub(auth: Authentication.bearerToken(token));
    final processor = ChangeProcessor(filters: parsedFilters, gh: gh);

    await processor.process();
    exit(0);
  } catch (e, stack) {
    stderr.writeln('Error: $e');
    stderr.writeln(stack);
    exit(1);
  }
}
