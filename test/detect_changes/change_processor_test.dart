import 'package:gh_tools/gh_tools.dart';
import 'package:github/github.dart';
import 'package:test/test.dart';

void main() {
  group('ChangeProcessor', () {
    final gh = GitHub();

    test('throws StateError when GITHUB_REPOSITORY is missing', () {
      final processor = ChangeProcessor(
        filters: {},
        gh: gh,
        env: {
          ChangeProcessor.kEnvGitHubEventName: 'push',
          ChangeProcessor.kEnvGitHubSha: 'abc1234',
        },
      );

      expect(() => processor.process(), throwsStateError);
    });

    test('throws FormatException when PR number is invalid', () {
      final processor = ChangeProcessor(
        filters: {},
        gh: gh,
        env: {
          ChangeProcessor.kEnvGitHubRepository: 'owner/repo',
          ChangeProcessor.kEnvGitHubEventName: 'pull_request',
          ChangeProcessor.kEnvGitHubRefName: 'not-a-number/merge',
        },
      );

      expect(() => processor.process(), throwsFormatException);
    });

    test('throws StateError when push SHA is missing', () {
      final processor = ChangeProcessor(
        filters: {},
        gh: gh,
        env: {
          ChangeProcessor.kEnvGitHubRepository: 'owner/repo',
          ChangeProcessor.kEnvGitHubEventName: 'push',
          ChangeProcessor.kEnvGitHubRefName: 'main',
        },
      );

      expect(() => processor.process(), throwsStateError);
    });

    test('throws UnsupportedError for unsupported event', () {
      final processor = ChangeProcessor(
        filters: {},
        gh: gh,
        env: {
          ChangeProcessor.kEnvGitHubRepository: 'owner/repo',
          ChangeProcessor.kEnvGitHubEventName: 'workflow_dispatch',
          ChangeProcessor.kEnvGitHubRefName: 'main',
        },
      );

      expect(() => processor.process(), throwsUnsupportedError);
    });
  });
}
