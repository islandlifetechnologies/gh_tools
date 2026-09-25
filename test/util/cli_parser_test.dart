import 'package:args/args.dart';
import 'package:gh_tools/gh_tools.dart';
import 'package:test/test.dart';

void main() {
  group('CliParser', () {
    test('parses options normally', () {
      final parser = ArgParser()..addOption('name', abbr: 'n');

      final cliParser = CliParser(parser: parser);
      final results = cliParser.parse(['--name', 'foo']);

      expect(results['name'], 'foo');
      expect(results['help'], isFalse);
      expect(results['version'], isFalse);
    });

    test('intercepts --help with allowExit: false', () {
      final parser = ArgParser();
      final cliParser = CliParser(parser: parser);

      expect(
        () => cliParser.parse(['--help'], allowExit: false),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('intercepts -h with allowExit: false', () {
      final parser = ArgParser();
      final cliParser = CliParser(parser: parser);

      expect(
        () => cliParser.parse(['-h'], allowExit: false),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('intercepts -v / --version with allowExit: false', () {
      final parser = ArgParser();
      final cliParser = CliParser(parser: parser);

      expect(
        () => cliParser.parse(['-v'], allowExit: false),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
