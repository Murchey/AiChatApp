import 'package:ai_chat/providers/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bubble font size defaults to 16', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();

    await settings.init();

    expect(settings.bubbleFontSize, 16);
  });

  test('bubble font size persists values at both boundaries', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();

    await settings.setBubbleFontSize(12);
    expect(settings.bubbleFontSize, 12);

    await settings.setBubbleFontSize(24);
    final restored = SettingsProvider();
    await restored.init();

    expect(restored.bubbleFontSize, 24);
    expect(
      (await SharedPreferences.getInstance()).getDouble('bubble_font_size'),
      24,
    );
  });

  test('bubble font size clamps persisted and newly set values', () async {
    SharedPreferences.setMockInitialValues({'bubble_font_size': 30.0});
    final settings = SettingsProvider();

    await settings.init();
    expect(settings.bubbleFontSize, 24);

    await settings.setBubbleFontSize(10);
    expect(settings.bubbleFontSize, 12);
  });
}
