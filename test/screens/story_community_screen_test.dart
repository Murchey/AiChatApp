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

  @override
  List<StoryCatalogEntry> get entries => List.generate(
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
