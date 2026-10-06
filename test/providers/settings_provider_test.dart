import 'package:ai_chat/providers/settings_provider.dart';
import 'package:ai_chat/config/theme.dart';
import 'package:flutter/cupertino.dart';
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

  test('theme presets restore the green default without duplicate colors',
      () async {
    final values =
        AppColors.presetColors.map((color) => color.toARGB32()).toSet();

    expect(AppColors.presetColors.first, const Color(0xFF07C160));
    expect(AppColors.presetColors, hasLength(5));
    expect(values, hasLength(AppColors.presetColors.length));

    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.init();

    expect(settings.accentColor, const Color(0xFF07C160));
  });

  test('saved accent color remains unchanged when settings are restored',
      () async {
    const savedColor = Color(0xFF007AFF);
    SharedPreferences.setMockInitialValues({
      'accent_color': savedColor.toARGB32(),
    });

    final settings = SettingsProvider();
    await settings.init();

    expect(settings.accentColor, savedColor);
  });
}
