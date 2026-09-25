import 'package:gh_tools/gh_tools.dart';
import 'package:test/test.dart';

void main() {
  group('RepoScanner', () {
    test('resolves slug from GITHUB_REPOSITORY environment variable', () {
      final scanner = RepoScanner();
      final slug = scanner.getRepoSlugFromEnvironment(
        env: {'GITHUB_REPOSITORY': 'owner/repo_name'},
      );

      expect(slug.owner, 'owner');
      expect(slug.name, 'repo_name');
      expect(slug.fullName, 'owner/repo_name');
    });

    test('resolves slug with surrounding whitespace', () {
      final scanner = RepoScanner();
      final slug = scanner.getRepoSlugFromEnvironment(
        env: {'GITHUB_REPOSITORY': '  my-org/my-project  '},
      );

      expect(slug.owner, 'my-org');
      expect(slug.name, 'my-project');
    });
  });
}
