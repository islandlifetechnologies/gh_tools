import 'dart:io';

import 'package:file/file.dart';
import 'package:logging/logging.dart';

/// Emits key-value outputs to GitHub Actions runner file.
class GitHubOutputEmitter({required final FileSystem fs}) {
  final _logger = Logger('GitHubOutputEmitter');

  /// Emits [values] to the GitHub Actions output file or [outputFile].
  ///
  /// Supports single-line and multiline output formatting.
  Future<File> emit(Map<String, String> values, {File? outputFile}) async {
    final ghActionEnvFile = Platform.environment['GITHUB_OUTPUT'];
    if (ghActionEnvFile == null && outputFile == null) {
      throw StateError('No output file or GITHUB_OUTPUT defined.');
    }

    final file = outputFile ?? fs.file(ghActionEnvFile!);
    _logger.info('Output file: ${file.path}');

    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }

    final buffer = StringBuffer();
    for (final entry in values.entries) {
      final value = entry.value;
      if (value.contains('\n')) {
        final delimiter = 'EOF_${DateTime.now().millisecondsSinceEpoch}';
        buffer.writeln('${entry.key}<<$delimiter');
        buffer.writeln(value);
        buffer.writeln(delimiter);
      } else {
        buffer.writeln('${entry.key}=$value');
      }
    }

    file.writeAsStringSync(
      buffer.toString(),
      flush: true,
      mode: FileMode.append,
    );

    return file;
  }
}
