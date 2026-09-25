import 'dart:convert';

import 'package:file/file.dart';
import 'package:gh_tools/gh_tools.dart';
import 'package:logging/logging.dart';

/// Emits metadata from a pubspec file in GitHub Actions or JSON format.
class PubspecEmitter({required final FileSystem fs}) {
  final _logger = Logger('PubspecEmitter');

  /// Scans [file] and emits metadata in the requested [format] ('github' or
  /// 'json').
  Future<File> emit(
    File file, {
    String format = 'github',
    File? outputFile,
  }) async {
    final scanner = PubspecScanner();
    final values = scanner.scan(file);

    if (format == 'json') {
      final oFile =
          outputFile ?? fs.file('${file.parent.path}/output/output.json');
      if (!oFile.parent.existsSync()) {
        oFile.parent.createSync(recursive: true);
      }
      oFile.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(values.toMap()),
        flush: true,
      );
      _logger.info('Wrote JSON: ${oFile.path}');
      return oFile;
    }

    return GitHubOutputEmitter(fs: fs)
        .emit(values.toMap(), outputFile: outputFile);
  }
}
