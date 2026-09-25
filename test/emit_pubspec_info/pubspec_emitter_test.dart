import 'dart:convert';

import 'package:file/memory.dart';
import 'package:gh_tools/gh_tools.dart';
import 'package:test/test.dart';

void main() {
  final fs = MemoryFileSystem();

  group('PubspecEmitter', () {
    final emitter = PubspecEmitter(fs: fs);

    test('emits in github format to output file', () async {
      final pubspec = fs.file('test/pubspec.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
name: emitter_pkg
version: 2.0.0
''');

      final output = fs.file('test/gh_output.txt');
      final result = await emitter.emit(
        pubspec,
        format: 'github',
        outputFile: output,
      );

      expect(result.existsSync(), isTrue);
      final content = result.readAsStringSync();
      expect(content, contains('PUBSPEC_NAME=emitter_pkg'));
      expect(content, contains('PUBSPEC_VERSION=2.0.0'));
      expect(content, contains('PUBSPEC_VERSION_MAJOR=2'));
    });

    test('emits in json format to output file', () async {
      final pubspec = fs.file('test/pubspec.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
name: json_pkg
version: 3.1.4
''');

      final output = fs.file('test/output.json');
      final result = await emitter.emit(
        pubspec,
        format: 'json',
        outputFile: output,
      );

      expect(result.existsSync(), isTrue);
      final jsonMap =
          json.decode(result.readAsStringSync()) as Map<String, dynamic>;
      expect(jsonMap['PUBSPEC_NAME'], 'json_pkg');
      expect(jsonMap['PUBSPEC_VERSION'], '3.1.4');
      expect(jsonMap['PUBSPEC_VERSION_PATCH'], '4');
    });
  });
}
