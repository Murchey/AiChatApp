import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_chat/services/backend_http_client.dart';
import 'package:ai_chat/config/theme.dart';
import 'package:ai_chat/models/story_package.dart';
import 'package:ai_chat/providers/story_provider.dart';
import 'package:ai_chat/providers/backend_provider.dart';
import '../support/backend_test_support.dart';
import 'package:ai_chat/screens/story_community_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FeedProvider extends StoryProvider {
  @override
  Future<void> init() async {}

  bool _busy = false;
  @override
  bool get loading => _busy;
  void setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }

  @override
  List<StoryCatalogEntry> get entries => _items;
  final List<StoryCatalogEntry> _items = List.generate(
    20,
    (i) => StoryCatalogEntry.fromJson({
      'storyId': 'post-$i',
      'title': 'Post $i',
      'summary': 'Story preview',
      'tags': ['Romance'],
      'file': 'assets/post-$i.json',
    }),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget themed(Widget child) {
    return CupertinoApp(
      theme: AppTheme.buildTheme(
        brightness: Brightness.light,
        accent: AppColors.presetColors.first,
      ),
      home: child,
    );
  }

  testWidgets('feed controls clear navigation and scroll together with posts',
      (tester) async {
    final provider = _FeedProvider();
    addTearDown(provider.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<StoryProvider>.value(
      value: provider,
      child: CupertinoApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 24),
            viewPadding: const EdgeInsets.only(top: 24),
          ),
          child: child!,
        ),
        home: const StoryCommunityScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    final search = find.byType(CupertinoSearchTextField);
    final tags = find.widgetWithText(CupertinoButton, '全部');
    final searchTop = tester.getTopLeft(search).dy;
    final tagsTop = tester.getTopLeft(tags).dy;
    final feed =
        find.byKey(const PageStorageKey<String>('story-community-feed-list'));
    expect(tester.getTopLeft(feed).dy, 0);
    expect(searchTop, greaterThanOrEqualTo(120));
    expect(tagsTop, greaterThan(tester.getBottomLeft(search).dy));
    await tester.drag(
      find.byKey(const PageStorageKey<String>('story-community-feed-list')),
      const Offset(0, -60),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(search).dy, lessThan(searchTop));
    expect(tester.getTopLeft(tags).dy, lessThan(tagsTop));
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading notifications reuse visible post widgets',
      (tester) async {
    final provider = _FeedProvider();
    addTearDown(provider.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<StoryProvider>.value(
        value: provider, child: themed(const StoryCommunityScreen())));
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('story-feed:post-0'));
    final before = tester.widget(card);
    final rendered = find.byWidgetPredicate((widget) =>
        widget.key is ValueKey<String> &&
        (widget.key as ValueKey<String>).value.startsWith('story-feed:'));
    expect(rendered.evaluate().length, lessThan(provider.entries.length));
    provider.setBusy(true);
    await tester.pump();
    expect(identical(tester.widget(card), before), isTrue);
    provider.setBusy(false);
    await tester.pumpAndSettle();
    expect(identical(tester.widget(card), before), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'empty local search can load more and index switching replaces the feed',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    var calls = 0;
    final provider = StoryProvider(
        staticClient: BackendHttpClient(client: MockClient((request) async {
      calls++;
      final second = request.url.path.endsWith('index-2.json');
      return http.Response(
          jsonEncode({
            if (!second)
              'indexes': [
                {'file': 'index.json', 'title': 'Latest'},
                {'file': 'index-2.json', 'title': 'Archive'},
              ],
            'stories': [
              {
                'storyId': second ? 'second' : 'first',
                'title': second ? 'Second post' : 'First post',
                'file': second ? 'assets/second.json' : 'assets/first.json',
                'tags': ['romance'],
              }
            ],
          }),
          200);
    })));
    addTearDown(provider.dispose);
    await provider.saveConfig(const StorySourceConfig(
        type: StorySourceType.cos, baseUrl: 'https://example.com'));
    await tester.pumpWidget(ChangeNotifierProvider<StoryProvider>.value(
        value: provider, child: themed(const StoryCommunityScreen())));
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester.enterText(find.byType(CupertinoSearchTextField), 'Second');
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('First post'), findsNothing);
    await tester.ensureVisible(find.text('加载更多故事'));
    await tester.tap(find.text('加载更多故事'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Second post'), findsOneWidget);
    await tester
        .ensureVisible(find.byKey(const ValueKey('story-index-selector')));
    await tester.tap(find.byKey(const ValueKey('story-index-selector')));
    await tester.pumpAndSettle();
    final panel = find.byKey(const ValueKey('story-index-panel'));
    expect(tester.getSize(panel).height,
        tester.view.physicalSize.height / tester.view.devicePixelRatio * 0.5);
    expect(
        find.byKey(const ValueKey('story-index-panel-list')), findsOneWidget);
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(provider.loadedIndexes, ['index-2.json']);
    expect(find.text('First post'), findsNothing);
    expect(find.text('Second post'), findsOneWidget);
    expect(
        tester
            .widget<CupertinoSearchTextField>(
                find.byType(CupertinoSearchTextField))
            .controller!
            .text,
        isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('feed keeps source settings behind the navigation gear',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = BackendProvider(tokenStore: MemoryTokenStore());
    final provider = StoryProvider(backend: backend);
    await provider.init();
    addTearDown(() {
      provider.dispose();
      backend.dispose();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [ChangeNotifierProvider.value(value: provider)],
        child: themed(const StoryCommunityScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('故事线社区'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.gear), findsOneWidget);
    expect(find.text('打开故事线设置'), findsOneWidget);
    expect(find.text('服务器地址'), findsNothing);

    await tester.tap(find.byIcon(CupertinoIcons.gear).last);
    await tester.pumpAndSettle();
    expect(find.text('故事线设置'), findsOneWidget);
    expect(find.text('服务器地址'), findsOneWidget);
    expect(find.text('故事来源'), findsOneWidget);
  });
}
