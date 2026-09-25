// ignore_for_file: avoid_print

import 'dart:io';

import 'package:args/args.dart';
import 'package:gh_tools/src/util/pubspec.dart';

/// Wraps [ArgParser] with common options (--help, --version).
class CliParser({required final ArgParser parser}) {
  /// Parses [args] and handles --help / --version automatically.
  ArgResults parse(List<String> args, {bool allowExit = true}) {
    parser
      ..addFlag('help', abbr: 'h', help: 'Show usage.', negatable: false)
      ..addFlag('version', abbr: 'v', help: 'Show version.', negatable: false);

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

    return result;
  }
}
