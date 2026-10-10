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
    expect(service.file, 'assets/${service.published!['storyId']}/1.json');
    expect(service.published!['memories'], isEmpty);
    expect(tester.takeException(), isNull);
  });
}
