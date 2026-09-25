import 'dart:convert';

import 'package:github/github.dart';
import 'package:logging/logging.dart';
import 'package:template_expressions/template_expressions.dart';

/// GitHub API client wrapper for repository properties and commit/PR file
/// inspection.
class GitHubClient({required final GitHub _gh}) {
  final _logger = Logger('GitHubClient');

  /// Retrieves custom property values for the repository [slug].
  ///
  /// Returns a map of property names to their current values.
  ///
  /// Uses GitHub REST API endpoint:
  /// `GET /repos/{owner}/{repo}/properties/values`
  Future<Map<String, dynamic>> getProperties(RepositorySlug slug) async {
    final path = '/repos/${slug.fullName}/properties/values';
    _logger.info('Fetching custom properties: ${slug.fullName}');

    final response = await _gh.request('GET', path);

    if (response.statusCode != 200) {
      _logger.severe(
        'Fetch properties failed (${response.statusCode}): ${response.body}',
      );
      throw GitHubError(_gh, 'Fetch properties failed: ${response.statusCode}');
    }

    final items = json.decode(response.body) as List<dynamic>;
    final result = <String, dynamic>{
      for (final item in items)
        (item as Map<String, dynamic>)['property_name'] as String:
            item['value'],
    };

    _logger.info('Found ${result.length} properties.');
    return result;
  }

  /// Lists modified and added files for pull request [number] in repository
  /// [slug].
  Future<List<String>> listPrFiles(RepositorySlug slug, int number) async {
    _logger.info('Fetching PR #$number files: $slug');
    final prFiles = await _gh.pullRequests.listFiles(slug, number).toList();

    final files = [
      for (final file in prFiles)
        if (file.filename != null) file.filename!,
    ];

    _logger.info('Found ${files.length} files.');
    for (final file in files) {
      _logger.info(' -- $file');
    }
    return files;
  }

  /// Lists modified and added files for commit [sha] in repository [slug].
  Future<List<String>> listPushFiles(RepositorySlug slug, String sha) async {
    _logger.info('Fetching commit $sha files: $slug');
    final commit = await _gh.repositories.getCommit(slug, sha);
    final commitFiles = commit.files ?? const <CommitFile>[];

    final files = [
      for (final file in commitFiles)
        if (file.name != null) file.name!,
    ];

    _logger.info('Found ${files.length} files.');
    for (final file in files) {
      _logger.info(' -- $file');
    }
    return files;
  }

  /// Updates custom properties for the repository [slug].
  ///
  /// String values support `template_expressions` evaluation.
  ///
  /// Uses GitHub REST API endpoint:
  /// `PATCH /repos/{owner}/{repo}/properties/values`
  Future<void> updateProperties(
    RepositorySlug slug,
    Map<String, dynamic> properties,
  ) async {
    final path = '/repos/${slug.fullName}/properties/values';

    dynamic processValue(dynamic value) {
      if (value is String) {
        return Template(value).process();
      } else if (value is List) {
        return value.map(processValue).toList();
      }
      return value;
    }

    final body = jsonEncode({
      'properties': [
        for (final entry in properties.entries)
          {'property_name': entry.key, 'value': processValue(entry.value)},
      ],
    });

    _logger.info('Updating ${properties.length} properties: ${slug.fullName}');

    final response = await _gh.request(
      'PATCH',
      path,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (response.statusCode == 200 || response.statusCode == 204) {
      _logger.info('Properties updated.');
    } else {
      _logger.severe(
        'Update properties failed (${response.statusCode}): ${response.body}',
      );
      throw GitHubError(
        _gh,
        'Update properties failed: ${response.statusCode}',
      );
    }
  }
}
