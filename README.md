# gh_tools

Tools and CLI binaries for common GitHub Actions workflows and repository automation tasks in Dart and Flutter projects.

**Table of Contents**
<!-- markup:toc /-->
<!-- markup:output -->
- [Installation](#installation)
- [Tools / Binaries](#tools-binaries)
  - [detect_changes](#detect_changes)
    - [GitHub Actions Example](#github-actions-example)
  - [pubspec_tag](#pubspec_tag)
    - [GitHub Actions Example](#github-actions-example-1)
  - [scan_pubspec](#scan_pubspec)
    - [GitHub Actions Example](#github-actions-example-2)
  - [update_repo_properties](#update_repo_properties)
    - [Example Properties File .github/properties.yaml](#example-properties-file-githubpropertiesyaml)
<!-- /markup:output -->

---

## Installation

Activate `gh_tools`:

```bash
dart pub global activate gh_tools
```

... or from a GitHub Action you can instead use:

```yaml
- uses: islandlifetechnologies/gh_tools@v1
```

That will automatically get the latest binaries for either Linux, MacOS, or Windows and bind them to the runner path.

---

## Tools / Binaries

### `detect_changes`

Evaluates changed files for a PR or push against defined glob filters.
<!-- markup:process

command: detect_changes
args:
  - --help
output:
  fence-type: bash
/-->
<!-- markup:output -->
```bash
detect_changes 1.0.0

    --filters (mandatory)    Filter definitions (YAML/JSON).
    --mode                   Default filter mode. And requires all filters to match, or will match on any filter.
                             [and, or (default)]
-h, --help                   Show usage.
-v, --version                Show version.
-t, --token                  GitHub access token.
```
<!-- /markup:output -->

#### GitHub Actions Example

```yaml
name: Validate PR (Matrix)

on:
  pull_request:
    types: [opened, reopened, synchronize]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

env:
  filters: |
    package_one:
      paths:
        - packages/package_one/**
    package_two:
      paths:
        - packages/package_two/**
    package_three:
      paths:
        - packages/package_three/**
  doc_filters: |
    readme:
      paths:
        - README.md

jobs:
  detect_changes:
    name: "Detect Changes"
    runs-on: ubuntu-latest
    outputs:
      CHANGES: ${{ steps.detect_changes.outputs.CHANGES }}
      CHANGES_ARRAY: ${{ steps.detect_changes.outputs.CHANGES_ARRAY }}
      DOC_CHANGES: ${{ steps.detect_doc_changes.outputs.CHANGES }}
    steps:
      - uses: islandlifetechnologies/gh_tools@v1

      - name: Checkout Code Base
        uses: actions/checkout@v7

      - name: Look for Changes
        id: detect_changes
        shell: bash
        run: |
          detect_changes \
            --filters "${{ env.filters }}" \
            --token "${{ secrets.GITHUB_TOKEN }}"

      - name: Look for Doc Changes
        id: detect_doc_changes
        shell: bash
        run: |
          detect_changes \
            --filters "${{ env.doc_filters }}" \
            --token "${{ secrets.GITHUB_TOKEN }}"

  ## Utilizes the CHANGES map to specifically target a single change set.
  update_docs:
    needs:
      - detect_changes
    if: fromJSON(needs.detect_changes.outputs.DOC_CHANGES).readme == true
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Code Base
        uses: actions/checkout@v7

      - name: Setup Dart
        uses: dart-lang/setup-dart@v1

      - uses: islandlifetechnologies/markup@v1

      - name: Run markup
        run: |
          markup -i README.md

      - name: Post Markdown to GitHub
        uses: test-room-7/action-update-file@v2
        with:
          branch: ${{ github.head_ref || github.ref_name }}
          file-path: |
            **/*.md
            **/*.png
            **/*.svg
          commit-msg: "[actions skip]: Auto-generated Markdown TOCs"
          github-token: ${{ secrets.GITHUB_TOKEN }}

  ## Utilizes the CHANGES_ARRAY to build a matrix of packages that have changed.
  ## Each package is validated in parallel.
  monorepo_split:
    needs:
      - detect_changes
    if: ${{ needs.detect_changes.outputs.CHANGES_ARRAY != '[]' && needs.detect_changes.outputs.CHANGES_ARRAY != '' }}
    strategy:
      fail-fast: false
      matrix:
        package: ${{ fromJSON(needs.detect_changes.outputs.CHANGES_ARRAY) }}
    name: "Validate ${{ matrix.package }}"
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Code Base
        uses: actions/checkout@v7

      - name: Setup Dart
        uses: dart-lang/setup-dart@v1

      - name: Validate ${{ matrix.package }}
        run: |
          dart pub get
          dart format --set-exit-if-changed lib test
          dart analyze
          dart test
        working-directory: packages/${{ matrix.package }}
```

Outputs written to `$GITHUB_OUTPUT`:

- `CHANGES`: JSON object of filter matches, e.g. `{"core": true, "web": false, "docs": true}`
- `CHANGES_ARRAY`: JSON list of matched filter keys, e.g. `["core", "docs"]`

The `CHANGES` option is typically easier to use when looking for a single change set, while `CHANGES_ARRAY` is typically easier to use when building a matrix of jobs. The above example shows how both can be utilized together.

---

### `pubspec_tag`

Extracts the information from the pubspec and utilizes that to create a tag for the repository.
<!-- markup:process

command: pubspec_tag
args:
  - --help
output:
  fence-type: bash
/-->
<!-- markup:output -->
```bash
pubspec_tag 1.0.0

    --branch        Branch name to scan the project for.  Default to the repository's default branch.
    --changelog     Scan for the version to exist in the changelog and fail if not.
                    (defaults to "true")
    --dry-run       Perform all calculations but make no changes.
                    (defaults to "false")
    --major         Add a tag for the major version; ie: v1
                    (defaults to "true")
    --minor         Add a tag for the minor version; ie: v1.2
                    (defaults to "true")
    --overwrite     Overwrite the existing tag if it exsts; fails if false.
                    (defaults to "true")
    --path          The path to the project; default is current directory.
                    (defaults to ".")
    --prefix        Prefix for the version tag.
                    (defaults to "v")
-h, --help          Show usage.
-v, --version       Show version.
-r, --repository    Repository to utilize.  Defaults to the current repository.
-t, --token         GitHub access token.
```
<!-- /markup:output -->

#### GitHub Actions Example

```yaml
- uses: islandlifetechnologies/gh_tools@v1

- name: Checkout Code Base
  uses: actions/checkout@v7

- name: Create Tag
  run: pubspec_tag --token "${{ secrets.GITHUB_TOKEN }}"
```

---

### `scan_pubspec`

Extracts pubspec metadata and exports it for downstream workflow steps.
<!-- markup:process

command: scan_pubspec
args:
  - --help
output:
  fence-type: bash
/-->
<!-- markup:output -->
```bash
scan_pubspec 1.0.0

-f, --format                    Output format.

          [github] (default)    GitHub Actions output format
          [json]                JSON format

-o, --output                    Output file path.
-p, --pubspec                   Path to pubspec.yaml.
                                (defaults to "./pubspec.yaml")
-h, --help                      Show usage.
-v, --version                   Show version.
```
<!-- /markup:output -->

#### GitHub Actions Example

```yaml
- uses: islandlifetechnologies/gh_tools@v1

- name: Checkout Code Base
  uses: actions/checkout@v7

- name: Scan Pubspec
  id: pubspec
  run: scan_pubspec --pubspec ./pubspec.yaml

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
<!-- markup:process

command: update_repo_properties
args:
  - --help
output:
  fence-type: bash
/-->
<!-- markup:output -->
```bash
update_repo_properties 1.0.0

-p, --properties    Properties file path (YAML/JSON).
                    (defaults to ".github/properties.yaml")
-h, --help          Show usage.
-v, --version       Show version.
-r, --repository    Repository to utilize.  Defaults to the current repository.
-t, --token         GitHub access token.
```
<!-- /markup:output -->

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