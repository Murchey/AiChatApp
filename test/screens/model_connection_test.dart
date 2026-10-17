import 'dart:convert';
import 'dart:io';
import 'package:ai_chat/providers/api_provider.dart';
import 'package:ai_chat/providers/settings_provider.dart';
import 'package:ai_chat/screens/model_edit_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final status in [200, 400]) {
    testWidgets('model connection test shows server result $status',
        (tester) async {
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        final previous = HttpOverrides.current;
        HttpOverrides.global = null;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var requests = 0;
        server.listen((request) async {
          requests++;
          final payload =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          expect(payload['model'], 'grok-4');
          expect(payload.containsKey('enable_thinking'), false);
          request.response
            ..statusCode = status
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(status == 200
                ? {
                    'choices': [
                      {
                        'message': {'content': 'OK'}
                      }
                    ]
                  }
                : {
                    'error': {'message': 'Unsupported request parameter'}
                  }));
          await request.response.close();
        });
        final settings = SettingsProvider();
        tester.view.physicalSize = const Size(900, 1800);
        tester.view.devicePixelRatio = 1;
        try {
          await tester.pumpWidget(ChangeNotifierProvider.value(
              value: settings,
              child: CupertinoApp(
                  home: ModelEditScreen(
                      model: ApiModel(
                          id: 'grok',
                          displayName: 'Grok',
                          modelName: 'grok-4',
                          baseUrl: 'http://127.0.0.1:${server.port}/v1',
                          apiKey: 'test-key')))));
          await tester.pumpAndSettle();
          await tester.tap(find.text('测试模型连接'));
          await tester.pump();
          for (var i = 0; i < 50 && find.text('复制详情').evaluate().isEmpty; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            await tester.pump();
          }
          await tester.pumpAndSettle();
          expect(requests, 1);
          expect(find.text(status == 200 ? '连接成功' : '连接失败'), findsOneWidget);
          expect(find.text('复制详情'), findsOneWidget);
          if (status == 400) {
            expect(find.textContaining('HTTP 400'), findsOneWidget);
            expect(find.textContaining('Unsupported request parameter'),
                findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          settings.dispose();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          await server.close(force: true);
          HttpOverrides.global = previous;
        }
      });
    });
  }
}
