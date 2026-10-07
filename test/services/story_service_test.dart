import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat/models/story_package.dart';
import 'package:ai_chat/services/story_service.dart';

void main() {
  test('GitHub and Gitee static indexes resolve to raw URLs', () {
    final github = StoryService.staticIndexUri(const StorySourceConfig(
      type: StorySourceType.github,
      repository: 'owner/repository',
      branch: 'main',
      path: 'stories/index.json',
    ));
    final gitee = StoryService.staticIndexUri(const StorySourceConfig(
      type: StorySourceType.gitee,
      repository: 'https://gitee.com/owner/repository',
      branch: 'master',
      path: 'index.json',
    ));
    expect(github.toString(),
        'https://raw.githubusercontent.com/owner/repository/main/stories/index.json');
    expect(gitee.toString(),
        'https://gitee.com/owner/repository/raw/master/index.json');
  });

  test('COS / OSS index can be resolved from a public base URL', () {
    final uri = StoryService.staticIndexUri(const StorySourceConfig(
      type: StorySourceType.cos,
      baseUrl: 'https://bucket.example.com/story',
      path: 'index.json',
    ));
    expect(uri.toString(), 'https://bucket.example.com/story/index.json');
  });

  test('relative story file resolves beside the static index', () {
    final index = Uri.parse('https://example.com/stories/index.json');
    expect(
      StoryService.resolveStaticFile(index, 'world/1.json').toString(),
      'https://example.com/stories/world/1.json',
    );
  });
}
