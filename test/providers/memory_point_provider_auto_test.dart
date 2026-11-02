import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_chat/models/auto_memory_op.dart';
import 'package:ai_chat/models/story_package.dart';
import 'package:ai_chat/providers/memory_point_provider.dart';

void main() {
  test('applyAutoOperations 增改删仅作用于 AI 托管条目', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = MemoryPointProvider();
    await provider.init();
    await provider.addPoints('character-1', ['用户自己的记忆']);
    await provider.installStory(
      'character-1',
      StoryPackage(
        storyId: 'story-1',
        version: 1,
        title: '故事标题',
        author: '作者',
        summary: '',
        tags: const [],
        chapters: const [
          StoryChapter(
            id: 'chapter-1',
            title: '背景',
            order: 1,
            memories: [StoryMemory(id: 'memory-1', order: 1, content: '故事设定')],
          ),
        ],
      ),
    );

    // add：新条目进入托管分区（最新在前）
    await provider.applyAutoOperations('character-1', [
      const AutoMemoryOp(op: AutoMemoryOp.opAdd, content: '剧情记录一'),
      const AutoMemoryOp(op: AutoMemoryOp.opAdd, content: '剧情记录二'),
    ]);
    final auto = provider.autoPointsFor('character-1');
    expect(auto.map((p) => p.content).toList(), ['剧情记录二', '剧情记录一']);
    expect(auto.every((p) => p.isAutoManaged), isTrue);

    // add 去重：内容相同的不再新增
    await provider.applyAutoOperations('character-1', [
      const AutoMemoryOp(op: AutoMemoryOp.opAdd, content: '剧情记录一'),
    ]);
    expect(provider.autoPointsFor('character-1').length, 2);

    // update 托管条目
    await provider.applyAutoOperations('character-1', [
      AutoMemoryOp(
        op: AutoMemoryOp.opUpdate,
        id: auto.first.id,
        content: '剧情记录二（改写）',
      ),
    ]);
    expect(provider.autoPointsFor('character-1').first.content, '剧情记录二（改写）');

    // 越权：update/delete 指向用户与故事线条目 → 一律忽略
    final userPoint = provider
        .pointsFor('character-1')
        .firstWhere((p) => !p.isAutoManaged && !p.isStory);
    final storyPoint =
        provider.pointsFor('character-1').firstWhere((p) => p.isStory);
    await provider.applyAutoOperations('character-1', [
      AutoMemoryOp(op: AutoMemoryOp.opUpdate, id: userPoint.id, content: '恶意改写'),
      AutoMemoryOp(op: AutoMemoryOp.opDelete, id: userPoint.id),
      AutoMemoryOp(op: AutoMemoryOp.opUpdate, id: storyPoint.id, content: '恶意改写'),
      AutoMemoryOp(op: AutoMemoryOp.opDelete, id: storyPoint.id),
    ]);
    expect(
      provider.pointsFor('character-1').map((p) => p.content),
      containsAll(<String>['用户自己的记忆', '故事设定']),
    );

    // delete 托管条目
    final deleteId = provider.autoPointsFor('character-1').last.id;
    await provider.applyAutoOperations('character-1', [
      AutoMemoryOp(op: AutoMemoryOp.opDelete, id: deleteId),
    ]);
    expect(provider.autoPointsFor('character-1').length, 1);

    // 持久化：reload 后托管条目仍在
    await provider.reload();
    final reloaded = provider.autoPointsFor('character-1');
    expect(reloaded.length, 1);
    expect(reloaded.first.isAutoManaged, isTrue);
    expect(reloaded.first.content, '剧情记录二（改写）');
  });

  test('removePoints 批量删除跨分区生效', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = MemoryPointProvider();
    await provider.init();
    await provider.addPoints('character-1', ['用户记忆甲', '用户记忆乙']);
    await provider.applyAutoOperations('character-1', [
      const AutoMemoryOp(op: AutoMemoryOp.opAdd, content: '托管记忆'),
    ]);
    final all = provider.pointsFor('character-1');
    expect(all.length, 3);

    final targets = all
        .where((p) => p.content != '用户记忆乙')
        .map((p) => p.id)
        .toList();
    await provider.removePoints('character-1', targets);
    expect(
      provider.pointsFor('character-1').map((p) => p.content).toList(),
      ['用户记忆乙'],
    );
  });
}
