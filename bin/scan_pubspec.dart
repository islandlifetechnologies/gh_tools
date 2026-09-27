import 'dart:io';

import 'package:args/args.dart';
import 'package:file/local.dart';
import 'package:gh_tools/gh_tools.dart';

void main(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'format',
      abbr: 'f',
      defaultsTo: 'github',
      help: 'Output format.',
      allowed: ['github', 'json'],
      allowedHelp: {
        'github': 'GitHub Actions output format',
        'json': 'JSON format',
      },
    )
    ..addOption('output', abbr: 'o', help: 'Output file path.')
    ..addOption(
      'pubspec',
      abbr: 'p',
      defaultsTo: './pubspec.yaml',
      help: 'Path to pubspec.yaml.',
    );

  final parsed = ArgUtil(parser: parser).parse(args);
  final format = parsed['format'] as String;
  final output = parsed['output'] as String?;
  final pubspecPath = parsed['pubspec'] as String;

  try {
    final fs = LocalFileSystem();
    final file = fs.file(pubspecPath);
    await PubspecEmitter(fs: fs).emit(
      file,
      format: format,
      outputFile: output != null ? fs.file(output) : null,
    );
    exit(0);
  } catch (e, stack) {
    stderr.writeln('Error: $e');
    stderr.writeln(stack);
    exit(1);
  }
}
