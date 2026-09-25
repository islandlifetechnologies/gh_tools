import 'dart:io';

import 'package:pubspec_parse/pubspec_parse.dart';

/// Scans a pubspec.yaml file and extracts metadata for GitHub Actions.
class PubspecScanner {
  /// Pubspec description key.
  static const kPubspecDescription = 'PUBSPEC_DESCRIPTION';

  /// Indicates whether the package depends on Flutter SDK key.
  static const kPubspecFlutterSdk = 'PUBSPEC_FLUTTER_SDK';

  /// Pubspec package name key.
  static const kPubspecName = 'PUBSPEC_NAME';

  /// Pubspec publish_to key.
  static const kPubspecPublishTo = 'PUBSPEC_PUBLISH_TO';

  /// Pubspec repository / homepage key.
  static const kPubspecRepository = 'PUBSPEC_REPOSITORY';

  /// Full pubspec version key.
  static const kPubspecVersion = 'PUBSPEC_VERSION';

  /// Pubspec major version key.
  static const kPubspecVersionMajor = 'PUBSPEC_VERSION_MAJOR';

  /// Pubspec minor version key.
  static const kPubspecVersionMinor = 'PUBSPEC_VERSION_MINOR';

  /// Pubspec patch version key.
  static const kPubspecVersionPatch = 'PUBSPEC_VERSION_PATCH';

  /// Pubspec pre-release version key.
  static const kPubspecVersionPreRelease = 'PUBSPEC_VERSION_PRE_RELEASE';

  /// Scans the given pubspec [file] and returns a [PubspecInfo].
  PubspecInfo scan(File file) {
    if (!file.existsSync()) {
      throw FileSystemException('File not found: ${file.path}', file.path);
    }

    final contents = file.readAsStringSync();
    final pubspec = Pubspec.parse(contents);

    final name = pubspec.name;
    if (name.isEmpty) {
      throw FormatException('Missing package name: ${file.path}');
    }

    final version = pubspec.version;
    if (version == null) {
      throw FormatException('Missing version: ${file.path}');
    }

    final repository = pubspec.repository?.toString() ?? pubspec.homepage ?? '';

    return PubspecInfo(
      description: pubspec.description ?? '',
      flutterSdk: pubspec.dependencies.containsKey('flutter'),
      name: name,
      major: version.major,
      minor: version.minor,
      patch: version.patch,
      preRelease: version.preRelease.join('.'),
      publishTo: pubspec.publishTo ?? '',
      repository: repository,
      version: version.toString(),
    );
  }
}

/// Extracted metadata from a pubspec.yaml file.
class PubspecInfo({
  required final String description,
  required final bool flutterSdk,
  required final String name,
  required final int major,
  required final int minor,
  required final int patch,
  required final String preRelease,
  required final String publishTo,
  required final String repository,
  required final String version,
}) {
  /// Converts metadata to a key-value map suitable for output emission.
  Map<String, String> toMap() => {
    PubspecScanner.kPubspecDescription: description,
    PubspecScanner.kPubspecFlutterSdk: flutterSdk.toString(),
    PubspecScanner.kPubspecName: name,
    PubspecScanner.kPubspecPublishTo: publishTo,
    PubspecScanner.kPubspecRepository: repository,
    PubspecScanner.kPubspecVersion: version,
    PubspecScanner.kPubspecVersionMajor: major.toString(),
    PubspecScanner.kPubspecVersionMinor: minor.toString(),
    PubspecScanner.kPubspecVersionPatch: patch.toString(),
    PubspecScanner.kPubspecVersionPreRelease: preRelease,
  };
}
