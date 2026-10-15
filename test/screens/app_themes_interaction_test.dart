import 'dart:async';
import 'dart:convert';

import 'package:ai_chat/models/workshop_repository.dart';
import 'package:ai_chat/screens/app_themes_screen.dart';
import 'package:ai_chat/services/app_theme_store.dart';
import 'package:ai_chat/services/workshop_service.dart';
import 'package:ai_chat/widgets/workshop/workshop_download_dialogs.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets(
      'themes aggregate sources, search locally, select ZIPs, force refresh and retry',
      (tester) async {
    final store = AppThemeStore.instance;
    final repos = store.repositories;
    final installed = store.installed;
    store.installed = [];
    store.repositories = const [
      WorkshopRepository(
          id: 'cos',
          name: '对象存储',
          url: 'https://themes.cos.ap-guangzhou.myqcloud.com/',
          proxyUrl: '',
          type: WorkshopRepoType.cos),
      WorkshopRepository(
          id: 'git',
          name: 'GitHub',
          url: 'https://github.com/demo/themes',
          proxyUrl: ''),
    ];
    addTearDown(() {
      store.repositories = repos;
      store.installed = installed;
      WorkshopService.invalidateCosListCache();
    });
    WorkshopService.invalidateCosListCache();
    var requests = 0;
    var fail = false;
    Completer<http.Response>? pending;
    final client = MockClient((request) async {
      requests++;
      if (request.url.host == 'api.github.com') {
        return http.Response(
            jsonEncode([
              {
                'tag_name': 'ThemeStore',
                'assets': [
                  {
                    'name': '柔云.zip',
                    'browser_download_url': 'https://example.com/cloud.zip',
                  }
                ]
              }
            ]),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      if (pending != null) return pending!.future;
      if (fail) return http.Response('failed', 500);
      return http.Response(
          '<ListBucketResult><IsTruncated>false</IsTruncated>'
          '<Contents><Key>Theme/心月狐.zip</Key><Size>123</Size></Contents>'
          '</ListBucketResult>',
          200,
          headers: {'content-type': 'application/xml; charset=utf-8'});
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(const CupertinoApp(home: AppThemesScreen()));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('theme-refresh')), findsOneWidget);
      expect(requests, 0);
      await tester.tap(find.text('在线主题'));
      await tester.pumpAndSettle();
      expect(requests, 2);
      expect(find.text('心月狐'), findsOneWidget);
      expect(find.text('柔云'), findsOneWidget);
      await tester.tap(find.text('心月狐'));
      await tester.pump();
      expect(find.text('下载导入 (1)'), findsOneWidget);
      await tester.enterText(find.byType(CupertinoSearchTextField), 'rouyun');
      await tester.pumpAndSettle();
      expect(find.text('心月狐'), findsNothing);
      expect(find.text('柔云'), findsOneWidget);
      expect(requests, 2);
      await tester.tap(find.text('柔云'));
      await tester.pump();
      expect(find.text('下载导入 (2)'), findsOneWidget);
      await tester.enterText(find.byType(CupertinoSearchTextField), '');
      await tester.pumpAndSettle();
      expect(find.text('心月狐'), findsOneWidget);
      expect(requests, 2);

      // Refresh must bypass COS's populated list cache, and disable re-entry.
      pending = Completer<http.Response>();
      await tester.tap(find.byKey(const ValueKey('theme-refresh')));
      await tester.pump();
      expect(requests, 3);
      expect(
          tester
              .widget<CupertinoButton>(
                  find.byKey(const ValueKey('theme-refresh')))
              .onPressed,
          isNull);
      expect(find.text('正在处理…'), findsOneWidget);
      pending!.complete(http.Response('failure', 500));
      pending = null;
      await tester.pumpAndSettle();
      expect(find.textContaining('部分来源加载失败'), findsOneWidget);
      expect(find.text('心月狐'), findsOneWidget);
      expect(find.text('柔云'), findsOneWidget);
      expect(find.text('下载导入 (2)'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('重试加载'));
      await tester.pumpAndSettle();
      expect(requests, 6);
      expect(find.text('重试加载'), findsNothing);
      await tester.tap(find.text('已安装'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('在线主题'));
      await tester.pumpAndSettle();
      expect(requests, 6);

      // Use the same batch download dialog as Workshop, with source identities.
      await tester.tap(find.text('下载导入 (2)'));
      await tester.pump();
      final dialog =
          tester.widget<BatchDownloadDialog>(find.byType(BatchDownloadDialog));
      expect(dialog.items.map((item) => item.repoId), ['cos', 'git']);
      expect(dialog.forceDownload, true);
      expect(dialog.maxBytes, 50 * 1024 * 1024);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }, () => client);
  });
}
