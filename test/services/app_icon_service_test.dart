import 'package:ai_chat/services/app_icon_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(
      () => messenger.setMockMethodCallHandler(AppIconService.channel, null));

  test('icon selection persists only after native success', () async {
    final service = AppIconService(android: true);
    addTearDown(service.dispose);
    messenger.setMockMethodCallHandler(AppIconService.channel, (call) async {
      expect(call.method, 'setIcon');
      expect(call.arguments['mode'], 'dark');
      return true;
    });
    await service.select('dark');
    expect(service.mode, 'dark');
    expect((await SharedPreferences.getInstance()).getString('app_icon_mode'),
        'dark');
    messenger.setMockMethodCallHandler(
        AppIconService.channel, (_) async => false);
    await expectLater(service.select('light'), throwsStateError);
    expect(service.mode, 'dark');
    expect((await SharedPreferences.getInstance()).getString('app_icon_mode'),
        'dark');
  });

  test('refresh preserves native unsupported and failure results', () async {
    final service = AppIconService(android: true);
    addTearDown(service.dispose);
    for (final result in ['success', 'not_pinned', 'unsupported', 'failed']) {
      messenger.setMockMethodCallHandler(
          AppIconService.channel, (_) async => result);
      expect(await service.refresh(), result);
    }
    messenger.setMockMethodCallHandler(AppIconService.channel, (_) async {
      throw PlatformException(code: 'ICON_ERROR', message: 'launcher failure');
    });
    await expectLater(service.refresh(), throwsA(isA<PlatformException>()));
    final desktop = AppIconService(android: false);
    addTearDown(desktop.dispose);
    expect(await desktop.refresh(), 'unsupported');
    await expectLater(desktop.select('dark'), throwsUnsupportedError);
  });
}
