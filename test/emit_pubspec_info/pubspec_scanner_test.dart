import 'dart:io';

import 'package:file/memory.dart';
import 'package:gh_tools/gh_tools.dart';
import 'package:test/test.dart';

void main() {
  final fs = MemoryFileSystem();
  group('PubspecScanner', () {
    final scanner = PubspecScanner();

    test('scans standard Dart pubspec', () {
      final file = fs.file('test/pubspec.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
name: my_package
description: A sample dart package.
version: 1.2.3-beta.1
homepage: https://github.com/example/my_package
publish_to: none

dependencies:
  meta: ^1.12.0
''');

      final info = scanner.scan(file);

      expect(info.name, 'my_package');
      expect(info.description, 'A sample dart package.');
      expect(info.version, '1.2.3-beta.1');
      expect(info.major, 1);
      expect(info.minor, 2);
      expect(info.patch, 3);
      expect(info.preRelease, 'beta.1');
      expect(info.publishTo, 'none');
      expect(info.repository, 'https://github.com/example/my_package');
      expect(info.flutterSdk, isFalse);

      final map = info.toMap();
      expect(map[PubspecScanner.kPubspecName], 'my_package');
      expect(map[PubspecScanner.kPubspecVersion], '1.2.3-beta.1');
      expect(map[PubspecScanner.kPubspecVersionMajor], '1');
      expect(map[PubspecScanner.kPubspecVersionMinor], '2');
      expect(map[PubspecScanner.kPubspecVersionPatch], '3');
      expect(map[PubspecScanner.kPubspecVersionPreRelease], 'beta.1');
      expect(map[PubspecScanner.kPubspecFlutterSdk], 'false');
    });

    test('detects Flutter SDK dependency', () {
      final file = fs.file('test/pubspec.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
name: flutter_app
version: 0.1.0
dependencies:
  flutter:
    sdk: flutter
''');

      final info = scanner.scan(file);
      expect(info.flutterSdk, isTrue);
      expect(info.toMap()[PubspecScanner.kPubspecFlutterSdk], 'true');
    });

    test('throws FileSystemException if file does not exist', () {
      final nonExistent = fs.file('test/non_existent.yaml');
      expect(
        () => scanner.scan(nonExistent),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('throws FormatException if version is missing', () {
      final file = fs.file('test/pubspec.yaml');
      file.writeAsStringSync('''
name: bad_package
''');
      expect(() => scanner.scan(file), throwsFormatException);
    });
  });
}
