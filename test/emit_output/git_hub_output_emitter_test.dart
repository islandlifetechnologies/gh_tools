import 'dart:io';

import 'package:file/memory.dart';
import 'package:gh_tools/gh_tools.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  final fs = MemoryFileSystem();

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('gh_tools_emitter_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('GitHubOutputEmitter', () {
    test('emits single-line values to output file', () async {
      final emitter = GitHubOutputEmitter(fs: fs);
      final outputFile = fs.file('${tempDir.path}/output.txt');

      final values = {'FOO': 'bar', 'COUNT': '42'};

      final result = await emitter.emit(values, outputFile: outputFile);

      expect(result.existsSync(), isTrue);
      final lines = result.readAsLinesSync();
      expect(lines, contains('FOO=bar'));
      expect(lines, contains('COUNT=42'));
    });

    test('emits multiline values with delimiter format', () async {
      final emitter = GitHubOutputEmitter(fs: fs);
      final outputFile = fs.file('${tempDir.path}/output.txt');

      final values = {'MULTILINE': 'line1\nline2\nline3'};

      final result = await emitter.emit(values, outputFile: outputFile);
      final content = result.readAsStringSync();

      expect(content, contains('MULTILINE<<EOF_'));
      expect(content, contains('line1\nline2\nline3'));
    });

    test(
      'throws StateError when no output file or GITHUB_OUTPUT set',
      () async {
        final emitter = GitHubOutputEmitter(fs: fs);
        expect(() => emitter.emit({'A': 'B'}), throwsStateError);
      },
      skip: Platform.environment['GITHUB_OUTPUT'] != null,
    );
  });
}
