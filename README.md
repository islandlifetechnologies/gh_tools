# gh_tools

Tools and CLI binaries for common GitHub Actions workflows and repository automation tasks in Dart and Flutter projects.

**Table of Contents**
<!-- markup:toc /-->
<!-- markup:output -->
- [Installation](#installation)
- [CLI Tools](#cli-tools)
  - [detect_changes](#detect_changes)
    - [GitHub Actions Example](#github-actions-example)
  - [scan_pubspec](#scan_pubspec)
    - [GitHub Actions Example](#github-actions-example-1)
  - [update_repo_properties](#update_repo_properties)
    - [Example Properties File .github/properties.yaml](#example-properties-file-githubpropertiesyaml)
- [Dart API Usage](#dart-api-usage)
  - [Scanning a Pubspec](#scanning-a-pubspec)
  - [Evaluating Change Filters](#evaluating-change-filters)
  - [Emitting Outputs](#emitting-outputs)
  - [Managing Custom Properties](#managing-custom-properties)
<!-- /markup:output -->

---

## Installation

Activate `gh_tools`:

```bash
dart pub global activate gh_tools
```

---

## CLI Tools

### `detect_changes`

Evaluates changed files for a PR or push against defined glob filters.

```bash
Usage: detect_changes [arguments]
    --filters (mandatory)    Filter definitions (YAML/JSON).
    --mode                   Default filter mode.
                             [and, or (default)]
    --token                  GitHub personal access token.
-h, --help                   Show usage.
-v, --version                Show version.
```

#### GitHub Actions Example

```yaml
- name: Detect Changes
  id: changes
  run: |
    dart run gh_tools:detect_changes \
      --token "${{ secrets.GITHUB_TOKEN }}" \
      --filters '
        core:
          - "packages/core/**"
        web:
          - "packages/web/**"
        docs:
          - "**/*.md"
      '

- name: Build Web
  if: fromJSON(steps.changes.outputs.CHANGES).web == true
  run: dart run build_runner build
```

Outputs written to `$GITHUB_OUTPUT`:

- `CHANGES`: JSON object of filter matches, e.g. `{"core": true, "web": false, "docs": true}`
- `CHANGES_ARRAY`: JSON list of matched filter keys, e.g. `["core", "docs"]`

---

### `scan_pubspec`

Extracts pubspec metadata and exports it for downstream workflow steps.

```bash
Usage: scan_pubspec [arguments]
-f, --format                    Output format.
          [github] (default)    GitHub Actions output format
          [json]                JSON format
-o, --output                    Output file path.
-p, --pubspec                   Path to pubspec.yaml.
                                (defaults to "./pubspec.yaml")
-h, --help                      Show usage.
-v, --version                   Show version.
```

#### GitHub Actions Example

```yaml
- name: Scan Pubspec
  id: pubspec
  run: dart run gh_tools:scan_pubspec --pubspec ./pubspec.yaml

- name: Create Release
  if: steps.pubspec.outputs.PUBSPEC_VERSION_PRE_RELEASE == ''
  run: echo "Releasing version ${{ steps.pubspec.outputs.PUBSPEC_VERSION }}"
```

Outputs emitted:
| Key | Description | Example |
|---|---|---|
| `PUBSPEC_NAME` | Package name | `gh_tools` |
| `PUBSPEC_DESCRIPTION` | Package description | `Tools for GitHub activities.` |
| `PUBSPEC_VERSION` | Full version string | `1.2.3-beta.1` |
| `PUBSPEC_VERSION_MAJOR` | Major version number | `1` |
| `PUBSPEC_VERSION_MINOR` | Minor version number | `2` |
| `PUBSPEC_VERSION_PATCH` | Patch version number | `3` |
| `PUBSPEC_VERSION_PRE_RELEASE` | Pre-release identifier | `beta.1` |
| `PUBSPEC_FLUTTER_SDK` | Contains Flutter dependency | `true` / `false` |
| `PUBSPEC_PUBLISH_TO` | Target package repository | `none` |
| `PUBSPEC_REPOSITORY` | Repository or homepage URL | `https://github.com/...` |

---

### `update_repo_properties`

Updates GitHub custom repository properties from a YAML or JSON file.

```bash
Usage: update_repo_properties [arguments]
-p, --properties    Properties file path (YAML/JSON).
                    (defaults to ".github/properties.yaml")
    --token         GitHub personal access token.
-h, --help          Show usage.
-v, --version       Show version.
```

#### Example Properties File (`.github/properties.yaml`)

```yaml
language: Dart
framework: CLI
last_updated: ${now()}
tier: production
tags:
  - automation
  - tooling
```

---

## Dart API Usage

### Scanning a Pubspec

```dart
import 'dart:io';
import 'package:gh_tools/gh_tools.dart';

void main() {
  final scanner = PubspecScanner();
  final info = scanner.scan(File('pubspec.yaml'));

  print('${info.name} v${info.version} (Flutter: ${info.flutterSdk})');
}
```

### Evaluating Change Filters

```dart
import 'package:gh_tools/gh_tools.dart';

void main() {
  final evaluator = Evaluator();
  final filters = Filters(
    mode: FilterMode.or,
    paths: ['lib/**', 'bin/**'],
  );

  final changedFiles = ['lib/src/client.dart', 'README.md'];
  final matched = evaluator.evaluate(files: changedFiles, filters: filters);

  print('Matched: $matched'); // true
}
```

### Emitting Outputs

```dart
import 'package:gh_tools/gh_tools.dart';

Future<void> main() async {
  final emitter = GitHubOutputEmitter();
  await emitter.emit({
    'STATUS': 'success',
    'SUMMARY': 'All checks completed successfully.',
  });
}
```

### Managing Custom Properties

```dart
import 'package:gh_tools/gh_tools.dart';
import 'package:github/github.dart';

Future<void> main() async {
  final gh = GitHub(auth: Authentication.bearerToken('ghp_your_token'));
  final client = GitHubClient(gh: gh);

  final slug = RepositorySlug('islandlifetechnologies', 'gh_tools');
  final props = await client.getProperties(slug);
  print('Current properties: $props');

  await client.updateProperties(slug, {
    'status': 'active',
    'updated_at': r'${now()}',
  });
}
```