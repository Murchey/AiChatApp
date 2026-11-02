import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_chat/config/theme.dart';
import 'package:ai_chat/models/auto_memory_op.dart';
import 'package:ai_chat/models/story_package.dart';
import 'package:ai_chat/providers/memory_point_provider.dart';
import 'package:ai_chat/screens/memory_point_manage_screen.dart';

Future<MemoryPointProvider> buildProvider() async {
  final provider = MemoryPointProvider();
  await provider.init();
  await provider.addPoints('char-1', ['用户手动记忆']);
  await provider.installStory(
    'char-1',
    StoryPackage(
      storyId: 'story-1',
      version: 1,
      title: '远征篇',
      author: '作者',
      summary: '',
      tags: const [],
      chapters: const [
        StoryChapter(
          id: 'chapter-1',
          title: '背景',
          order: 1,
          memories: [StoryMemory(id: 'memory-1', order: 1, content: '故事设定记忆')],
        ),
      ],
    ),
  );
  await provider.applyAutoOperations('char-1', [
    const AutoMemoryOp(op: AutoMemoryOp.opAdd, content: 'AI剧情记录甲'),
    const AutoMemoryOp(op: AutoMemoryOp.opAdd, content: 'AI剧情记录乙'),
  ]);
  return provider;
}

Widget wrap(MemoryPointProvider provider) {
  return MultiProvider(
    providers: [ChangeNotifierProvider.value(value: provider)],
    child: CupertinoApp(
      theme: AppTheme.buildTheme(
        brightness: Brightness.light,
        accent: AppColors.presetColors.first,
      ),
      home: const MemoryPointManageScreen(characterId: 'char-1'),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('两个分区分别展示托管与用户/故事线记忆', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final provider = await buildProvider();
    await tester.pumpWidget(wrap(provider));
    await tester.pump();

    expect(find.text('AI 托管 · 剧情记录'), findsOneWidget);
    expect(find.text('我的记忆'), findsOneWidget);
    expect(find.text('AI剧情记录甲'), findsOneWidget);
    expect(find.text('AI剧情记录乙'), findsOneWidget);
    expect(find.text('用户手动记忆'), findsOneWidget);
    expect(find.text('故事设定记忆'), findsOneWidget);
    // 故事线条目带来源徽标
    expect(find.textContaining('故事线 · 远征篇'), findsOneWidget);
  });

  testWidgets('搜索跨分区过滤记忆点', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final provider = await buildProvider();
    await tester.pumpWidget(wrap(provider));
    await tester.pump();

    await tester.enterText(find.byType(CupertinoSearchTextField), '手动');
    await tester.pump();
    expect(find.text('用户手动记忆'), findsOneWidget);
    expect(find.text('AI剧情记录甲'), findsNothing);
    expect(find.text('故事设定记忆'), findsNothing);

    await tester.enterText(find.byType(CupertinoSearchTextField), '不存在的关键词');
    await tester.pump();
    expect(find.text('没有匹配的记忆点'), findsNWidgets(2));

    await tester.enterText(find.byType(CupertinoSearchTextField), '');
    await tester.pump();
    expect(find.text('AI剧情记录甲'), findsOneWidget);
  });

  testWidgets('多选模式批量删除记忆点', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final provider = await buildProvider();
    await tester.pumpWidget(wrap(provider));
    await tester.pump();

    // 进入多选模式，勾选两条（一条托管、一条用户）
    await tester.tap(find.text('选择'));
    await tester.pump();
    await tester.tap(find.text('AI剧情记录甲'));
    await tester.pump();
    await tester.tap(find.text('用户手动记忆'));
    await tester.pump();
    expect(find.text('删除(2)'), findsOneWidget);

    // 全选后取消一条，再删除剩余 3 条
    await tester.tap(find.text('全选'));
    await tester.pump();
    await tester.tap(find.text('AI剧情记录乙'));
    await tester.pump();
    expect(find.text('删除(3)'), findsOneWidget);

    await tester.tap(find.text('删除(3)'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('批量删除记忆点'), findsOneWidget);

    await tester.tap(find.text('删除').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 仅剩未勾选的一条
    final remaining = provider.pointsFor('char-1');
    expect(remaining.length, 1);
    expect(remaining.first.content, 'AI剧情记录乙');
    expect(find.text('AI剧情记录乙'), findsOneWidget);
    expect(find.text('AI剧情记录甲'), findsNothing);
    expect(find.text('用户手动记忆'), findsNothing);
  });
}
