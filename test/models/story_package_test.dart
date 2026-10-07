import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat/models/memory_point.dart';
import 'package:ai_chat/models/story_package.dart';

void main() {
  test('故事包解析章节和记忆点', () {
    final story = StoryPackage.fromText('''
      {
        "schemaVersion": 1,
        "storyId": "world-1",
        "version": 2,
        "title": "新世界",
        "author": "作者",
        "summary": "简介",
        "tags": ["科幻"],
        "chapters": [
          {"id": "c1", "title": "背景", "order": 1,
           "memories": [{"id": "m1", "order": 1, "content": "城市被海水包围"}]}
        ]
      }
    ''');

    expect(story.storyId, 'world-1');
    expect(story.version, 2);
    expect(story.memories.single.content, '城市被海水包围');
  });

  test('旧记忆 JSON 不带故事字段仍可读取', () {
    final point = MemoryPoint.fromJson({
      'id': 'legacy',
      'content': '普通记忆',
      'created_at': '2026-01-01T00:00:00.000Z',
    });
    expect(point.content, '普通记忆');
    expect(point.sourceType, isNull);
    expect(point.toJson().containsKey('source_type'), isFalse);
  });

  test('故事来源字段可序列化和恢复', () {
    final point = MemoryPoint(
      id: 'story-point',
      content: '故事设定',
      sourceType: 'story',
      sourceId: 'world-1',
      sourceVersion: 3,
      sourceTitle: '新世界',
      chapterId: 'c1',
    );
    final restored = MemoryPoint.fromJson(point.toJson());
    expect(restored.sourceType, 'story');
    expect(restored.sourceId, 'world-1');
    expect(restored.sourceVersion, 3);
    expect(restored.chapterId, 'c1');
  });
}
