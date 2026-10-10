import 'dart:convert';
import 'dart:typed_data';
import 'package:ai_chat/models/story_package.dart';
import 'package:ai_chat/providers/story_provider.dart';
import 'package:ai_chat/screens/story_quick_edit_screen.dart';
import 'package:ai_chat/services/story_editing_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Provider extends StoryProvider {
  @override
  StorySourceConfig get config => const StorySourceConfig(
      type: StorySourceType.cos, baseUrl: 'https://example.com');
  @override
  Future<void> init() async {}
  @override
  Future<void> loadCatalog(
      {String? query,
      String? tag,
      bool append = false,
      bool force = false}) async {}
}

class _Service extends StoryEditingService {
  int indexReads = 0;
  Map<String, dynamic>? published;
  String? file;
  String? deletedImage;
  String? deletedPost;
  @override
  Future<void> deletePost(
      StorySourceConfig config, StoryCatalogEntry entry) async {
    deletedPost = entry.storyId;
  }

  @override
  Future<Map<String, dynamic>> loadDetail(
          StorySourceConfig config, StoryCatalogEntry entry) async =>
      {
        'storyId': entry.storyId,
        'version': entry.version,
        'title': entry.title,
        'introduction': '已有帖正文',
        'memories': [],
        'images': []
      };
  @override
  Future<String> uploadImage(
          StorySourceConfig config, String file, Uint8List bytes) async =>
      'img/test.png';
  @override
  Future<void> deleteImage(StorySourceConfig config, String file, String image,
      {StoryCatalogEntry? entry}) async {
    deletedImage = image;
  }

  @override
  Future<void> checkWrite(StorySourceConfig config) async {}
  @override
  Future<Map<String, dynamic>> loadIndex(StorySourceConfig config) async {
    indexReads++;
    return {
      'stories': [
        {
          'storyId': 'first',
          'version': 1,
          'title': '晨光',
          'author': '作者一',
          'tags': ['慢热'],
          'file': 'assets/first/1.json'
        },
        {
          'storyId': 'second',
          'version': 1,
          'title': '月光',
          'author': '作者二',
          'tags': ['异地'],
          'file': 'assets/second/1.json'
        },
      ]
    };
  }

  @override
  Future<void> publish(
      StorySourceConfig config, Map<String, dynamic> detail, String file,
      {required bool isNew}) async {
    published = detail;
    this.file = file;
  }
}

void main() {
  testWidgets('existing post uses header back to return to list',
      (tester) async {
    final provider = _Provider();
    addTearDown(provider.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<StoryProvider>.value(
        value: provider,
        child: CupertinoApp(home: StoryQuickEditScreen(service: _Service()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('晨光'));
    await tester.pumpAndSettle();
    expect(find.text('编辑帖子'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    expect(find.text('已有帖正文'), findsOneWidget);
    await tester.tap(find.byIcon(CupertinoIcons.chevron_left));
    await tester.pumpAndSettle();
    expect(find.text('帖子快捷编辑'), findsOneWidget);
    expect(find.text('保存'), findsNothing);
    expect(find.text('晨光'), findsOneWidget);
  });
  Future<_Service> open(WidgetTester tester) async {
    final service = _Service();
    final provider = _Provider();
    addTearDown(provider.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<StoryProvider>.value(
        value: provider,
        child: CupertinoApp(home: StoryQuickEditScreen(service: service))));
    await tester.pumpAndSettle();
    return service;
  }

  testWidgets('searches full catalog locally and clearing restores all posts',
      (tester) async {
    final service = await open(tester);
    expect(find.text('保存'), findsNothing);
    final search = find.byKey(const Key('story-editor-search'));
    await tester.enterText(search, '异地');
    await tester.pump();
    expect(find.text('晨光'), findsNothing);
    expect(find.text('月光'), findsOneWidget);
    await tester.enterText(search, 'first');
    await tester.pump();
    expect(find.text('晨光'), findsOneWidget);
    expect(find.text('月光'), findsNothing);
    await tester.enterText(search, '作者二');
    await tester.pump();
    expect(find.text('月光'), findsOneWidget);
    await tester.enterText(search, '');
    await tester.pump();
    expect(find.text('晨光'), findsOneWidget);
    expect(find.text('月光'), findsOneWidget);
    expect(service.indexReads, 1);
  });

  testWidgets('long press confirms deletion and pull down refreshes the list',
      (tester) async {
    final service = await open(tester);
    expect(find.text('刷新帖子列表'), findsNothing);
    expect(find.byType(CupertinoSliverRefreshControl, skipOffstage: false),
        findsOneWidget);
    await tester.longPress(find.text('晨光'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(service.deletedPost, isNull);
    await tester.tap(find.byKey(const ValueKey('delete-post:first')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(service.deletedPost, 'first');
    expect(find.text('晨光'), findsNothing);
    expect(find.text('月光'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(service.indexReads, 2);
    expect(find.text('晨光'), findsOneWidget);
  });

  testWidgets(
      'composer back returns to list and blank memory lines are ignored',
      (tester) async {
    final service = await open(tester);
    await tester.tap(find.text('创建新帖子'));
    await tester.pumpAndSettle();
    expect(find.text('返回帖子列表'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('标题（必填）')), '标题');
    await tester.enterText(find.byKey(const ValueKey('帖子正文（必填）')), '正文');
    final memoriesToggle = find.text('故事记忆点（可选）');
    await tester.ensureVisible(memoriesToggle);
    await tester.tap(memoriesToggle);
    await tester.pumpAndSettle();
    final memories = find.byKey(const ValueKey('记忆点（每行一条）'));
    await tester.ensureVisible(memories);
    await tester.enterText(memories, '第一条\n\n\n第二条\n  \n');
    await tester.tap(find.text('发布'));
    await tester.pumpAndSettle();
    expect(service.published!['memories'], ['第一条', '第二条']);
    await tester.tap(find.byIcon(CupertinoIcons.chevron_left));
    await tester.pumpAndSettle();
    expect(find.text('帖子快捷编辑'), findsOneWidget);
    expect(find.text('保存'), findsNothing);
    expect(find.text('创建新帖子'), findsOneWidget);
  });

  testWidgets('uploads image, previews it and deletes object and draft path',
      (tester) async {
    final service = _Service();
    final provider = _Provider();
    addTearDown(provider.dispose);
    final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==');
    await tester.pumpWidget(ChangeNotifierProvider<StoryProvider>.value(
        value: provider,
        child: CupertinoApp(
            home: StoryQuickEditScreen(
                service: service, pickImage: () async => bytes))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建新帖子'));
    await tester.pumpAndSettle();
    final add = find.text('添加图片');
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    final remove = find.byKey(const ValueKey('delete-image:img/test.png'));
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    expect(service.deletedImage, 'img/test.png');
    expect(find.byType(Image), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('标题（必填）')), '标题');
    await tester.enterText(find.byKey(const ValueKey('帖子正文（必填）')), '正文');
    await tester.tap(find.text('发布'));
    await tester.pumpAndSettle();
    expect(service.published!['images'], isEmpty);
  });

  testWidgets('creates a new post with generated ID, validates and publishes',
      (tester) async {
    final service = await open(tester);
    await tester.tap(find.text('创建新帖子'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发布'));
    await tester.pump();
    expect(service.published, isNull);
    expect(find.text('请填写标题和帖子正文'), findsOneWidget);
    final title = find.byKey(const ValueKey('标题（必填）'));
    await tester.ensureVisible(title);
    await tester.enterText(title, '新故事');
    final intro = find.byKey(const ValueKey('帖子正文（必填）'));
    await tester.ensureVisible(intro);
    await tester.enterText(intro, '正文内容');
    await tester.tap(find.text('发布'));
    await tester.pumpAndSettle();
    expect(service.published!['title'], '新故事');
    expect(service.published!['introduction'], '正文内容');
    expect(service.published!['storyId'], startsWith('story-'));
    expect(service.file, 'assets/${service.published!['storyId']}.json');
    expect(service.published!['memories'], isEmpty);
    expect(tester.takeException(), isNull);
  });
}
