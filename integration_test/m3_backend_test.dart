import 'dart:convert';
import 'dart:io';
import 'package:ai_chat/config/theme.dart';
import 'package:ai_chat/models/story_package.dart';
import 'package:ai_chat/providers/backend_provider.dart';
import 'package:ai_chat/providers/story_provider.dart';
import 'package:ai_chat/screens/story_community_screen.dart';
import 'package:ai_chat/services/backend_token_store.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Uses an isolated real M1/M2 server and a separate native secure-storage key.
/// Supply credentials through an ignored --dart-define-from-file, never source.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('AICHAT_M3_URL');
  const invite = String.fromEnvironment('AICHAT_M3_INVITE');
  testWidgets('M3 real server, native token storage, pagination and settings',
      (tester) async {
    expect(url, isNotEmpty, reason: 'Provide AICHAT_M3_URL');
    expect(invite, isNotEmpty,
        reason: 'Provide a fresh single-use test invite');
    SharedPreferences.setMockInitialValues({});
    const store = SecureBackendTokenStore(key: 'aichat_m3_integration_session');
    await store.clear();
    final backend = BackendProvider(tokenStore: store);
    final stories = StoryProvider(backend: backend);
    await stories.saveConfig(const StorySourceConfig(baseUrl: url));
    await backend.bindInvite(invite);
    expect(backend.isAuthenticated, true);
    final stored = await store.read();
    expect(stored, isNotNull);
    expect((jsonDecode(stored!) as Map)['refresh_token'], isNotEmpty);
    final initialAccess = backend.config.accessToken;
    await backend.refreshAccessToken();
    expect(backend.config.accessToken, isNot(initialAccess));
    final restored = BackendProvider(tokenStore: store);
    await restored.init();
    expect(restored.config.refreshToken, backend.config.refreshToken);
    await stories.loadCatalog();
    expect(stories.entries.length, 20);
    expect(stories.hasMore, true);
    await stories.loadMoreCatalog();
    expect(stories.entries.length, 25);
    expect(stories.hasMore, false);
    await stories.loadCatalog(query: 'Smoke 01', tag: 'm3');
    expect(stories.entries.length, 1);
    final story = await stories.loadPackage(stories.entries.single);
    expect(story.memories.single.content, 'M3 memory content');

    await binding.convertFlutterSurfaceToImage();
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: stories,
          child: CupertinoApp(
              theme: AppTheme.buildTheme(
                  brightness: brightness, accent: AppColors.presetColors.first),
              home: const StoryCommunityScreen())));
      await tester.pumpAndSettle();
      expect(find.text('故事线社区'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.gear), findsOneWidget);
      await tester.tap(find.byIcon(CupertinoIcons.gear));
      await tester.pumpAndSettle();
      expect(find.text('故事线设置'), findsOneWidget);
      expect(find.text('保存'), findsOneWidget);
      expect(find.text('服务器地址'), findsOneWidget);
      await tester.ensureVisible(find.text('绑定设备并刷新令牌'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pump();
      final screenshot = await binding.takeScreenshot('m3-${brightness.name}');
      final directory = await getApplicationDocumentsDirectory();
      await File('${directory.path}/m3-${brightness.name}.png')
          .writeAsBytes(screenshot);
      await tester.pumpWidget(const CupertinoApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
    }
    await backend.revokeDevice();
    expect(await store.read(), isNull);
    expect(backend.isAuthenticated, false);
    restored.dispose();
    stories.dispose();
    backend.dispose();
  }, timeout: const Timeout(Duration(minutes: 4)));
}
