import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_chat/models/story_package.dart';
import 'package:ai_chat/providers/memory_point_provider.dart';

void main() {
  test('故事安装、更新和卸载只影响故事来源记忆', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = MemoryPointProvider();
    await provider.init();
    await provider.addPoints('character-1', ['用户自己的记忆']);

    final first = StoryPackage(
      storyId: 'story-1',
      version: 1,
      title: '第一版故事',
      author: '作者',
      summary: '',
      tags: const [],
      chapters: const [
        StoryChapter(
          id: 'chapter-1',
          title: '背景',
          order: 1,
          memories: [
            StoryMemory(id: 'memory-1', order: 1, content: '旧世界设定'),
          ],
        ),
      ],
    );
    await provider.installStory('character-1', first);
    expect(provider.pointsFor('character-1').map((p) => p.content),
        containsAll(<String>['用户自己的记忆', '旧世界设定']));

    final second = StoryPackage(
      storyId: 'story-1',
      version: 2,
      title: '第二版故事',
      author: '作者',
      summary: '',
      tags: const [],
      chapters: const [
        StoryChapter(
          id: 'chapter-2',
          title: '更新',
          order: 1,
          memories: [
            StoryMemory(id: 'memory-2', order: 1, content: '新世界设定'),
          ],
        ),
      ],
    );
    await provider.installStory('character-1', second);
    expect(provider.pointsFor('character-1').map((p) => p.content),
        containsAll(<String>['用户自己的记忆', '新世界设定']));
    expect(provider.pointsFor('character-1').map((p) => p.content),
        isNot(contains('旧世界设定')));

    await provider.removeStory('character-1', 'story-1');
    expect(provider.pointsFor('character-1').map((p) => p.content).toList(),
        ['用户自己的记忆']);
    expect(provider.installedStoriesFor('character-1'), isEmpty);
  });
}
