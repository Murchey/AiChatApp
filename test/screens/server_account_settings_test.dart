import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_chat/models/story_package.dart';
import 'package:ai_chat/providers/backend_provider.dart';
import 'package:ai_chat/providers/settings_provider.dart';
import 'package:ai_chat/providers/story_provider.dart';
import 'package:ai_chat/screens/story_community_settings_screen.dart';
import 'package:ai_chat/services/backend_http_client.dart';
import '../support/backend_test_support.dart';
import '../providers/backend_account_test.dart'
    show accountTokens, accountVersion;

void main() {
  testWidgets(
      'settings registers once, reveals and clears password, and retains local data',
      (tester) async {
    SharedPreferences.setMockInitialValues({'local_chat': 'keep'});
    tester.view.physicalSize = const Size(390, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final response = Completer<void>();
    var requests = 0;
    final backend = BackendProvider(
        tokenStore: MemoryTokenStore(),
        client: BackendHttpClient(client: MockClient((req) async {
          if (req.url.path.endsWith('health')) {
            return jsonResponse({'status': 'UP'});
          }
          if (req.url.path.endsWith('version')) {
            return jsonResponse(accountVersion());
          }
          if (req.url.path.endsWith('register')) {
            requests++;
            await response.future;
            return jsonResponse(accountTokens());
          }
          if (req.url.path.endsWith('login')) {
            requests++;
            return jsonResponse(accountTokens());
          }
          if (req.url.path.endsWith('revoke')) {
            return jsonResponse({'revoked': true});
          }
          throw StateError('Unexpected route');
        })));
    final story = StoryProvider(backend: backend),
        settings = SettingsProvider();
    addTearDown(story.dispose);
    addTearDown(backend.dispose);
    addTearDown(settings.dispose);
    await story.saveConfig(const StorySourceConfig(
        type: StorySourceType.server, baseUrl: 'http://server.test'));
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<BackendProvider>.value(value: backend),
      ChangeNotifierProvider<StoryProvider>.value(value: story),
      ChangeNotifierProvider<SettingsProvider>.value(value: settings),
    ], child: const CupertinoApp(home: StoryCommunitySettingsScreen())));
    await tester.pumpAndSettle();
    final name = find.byWidgetPredicate(
        (w) => w is CupertinoTextField && w.placeholder == '3–32位字母、数字或下划线');
    final password = find.byWidgetPredicate(
        (w) => w is CupertinoTextField && w.placeholder == '至少8个字符，不保存密码');
    await tester.enterText(name, 'beta_user');
    await tester.enterText(password, 'password123');
    expect(tester.widget<CupertinoTextField>(password).obscureText, true);
    await tester.tap(find.byIcon(CupertinoIcons.eye));
    await tester.pump();
    expect(tester.widget<CupertinoTextField>(password).obscureText, false);
    await tester.tap(find.text('注册并登录'));
    await tester.pump();
    await tester.tap(find.text('注册并登录'));
    await tester.pump();
    expect(requests, 1);
    response.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<CupertinoTextField>(password).controller!.text, '');
    expect(find.text('当前账号：beta_user'), findsOneWidget);
    expect(find.text('邀请码（首次绑定）'), findsNothing);
    await tester.tap(find.text('退出服务器登录'));
    await tester.pumpAndSettle();
    expect(backend.isAuthenticated, false);
    expect((await SharedPreferences.getInstance()).getString('local_chat'),
        'keep');
    await tester.enterText(password, 'password123');
    await tester.tap(find.text('登录服务器账号'));
    await tester.pumpAndSettle();
    expect(requests, 2);
    expect(backend.isAccountLoggedIn, true);
    expect(tester.widget<CupertinoTextField>(password).controller!.text, '');
    expect(tester.takeException(), isNull);
  });
}
