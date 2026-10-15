import 'dart:convert';
import 'dart:io';
import 'package:ai_chat/config/theme.dart';
import 'package:ai_chat/models/app_theme_pack.dart';
import 'package:ai_chat/providers/settings_provider.dart';
import 'package:ai_chat/screens/settings_screen.dart';
import 'package:ai_chat/screens/theme_appearance_screen.dart';
import 'package:ai_chat/services/app_theme_store.dart';
import 'package:ai_chat/widgets/settings/color_picker_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
        'unified colors show effective controls and preserve base colors: $brightness',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();
      final store = AppThemeStore.instance;
      final pack = AppThemePack.parse(
          Map<String, dynamic>.from(jsonDecode(
                  File('docs/theme-example/content.json').readAsStringSync())
              as Map),
          Directory('docs/theme-example').absolute.path);
      store.installed = [pack];
      store.activeId = pack.id;
      await store.adjust('bubble', true);
      await store.adjust('textLight', null);
      addTearDown(() {
        store.activeId = null;
        store.installed = [];
        settings.dispose();
      });
      Widget app(Widget child) => ChangeNotifierProvider.value(
          value: settings,
          child: CupertinoApp(
              theme: AppTheme.buildTheme(
                  brightness: brightness, accent: AppColors.presetColors.first),
              home: child));
      await tester.pumpWidget(app(const SettingsScreen()));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('气泡与文字颜色'), 300);
      expect(find.text('自定义气泡颜色'), findsNothing);
      expect(find.text('主题我方气泡和文字'), findsNothing);
      await tester.tap(find.text('气泡与文字颜色'));
      await tester.pumpAndSettle();
      expect(find.text('由主题图片决定，不支持单独改色'), findsOneWidget);
      expect(
          find.byKey(const ValueKey('bubble-color-selfLight')), findsNothing);
      expect(
          find.byKey(const ValueKey('bubble-text-selfLight')), findsOneWidget);
      expect(find.byKey(const ValueKey('bubble-color-otherLight')),
          findsOneWidget);
      final baseText = settings.bubbleTextColor(BubbleTextSlot.selfLight);
      final baseBackground = settings.bubbleColor(BubbleColorSlot.selfLight);
      await tester.tap(find.byKey(const ValueKey('bubble-text-selfLight')));
      await tester.pumpAndSettle();
      tester
          .widget<CustomColorPicker>(find.byType(CustomColorPicker))
          .onChanged(const Color(0xFF112233));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(store.textColor(false), const Color(0xFF112233));
      expect(settings.bubbleTextColor(BubbleTextSlot.selfLight), baseText);
      expect(settings.bubbleColor(BubbleColorSlot.selfLight), baseBackground);
      await tester.tap(find.byKey(const ValueKey('bubble-text-selfLight')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复默认'));
      await tester.pumpAndSettle();
      expect(store.textColor(false), pack.textColor);
      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pumpAndSettle();
      expect(find.text('由主题图片决定，不支持单独改色'), findsNothing);
      expect(
          find.byKey(const ValueKey('bubble-color-selfLight')), findsOneWidget);
      expect(settings.bubbleColor(BubbleColorSlot.selfLight), baseBackground);
      await tester.tap(find.byKey(const ValueKey('bubble-text-selfLight')));
      await tester.pumpAndSettle();
      tester
          .widget<CustomColorPicker>(find.byType(CustomColorPicker))
          .onChanged(const Color(0xFF445566));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(settings.bubbleTextColor(BubbleTextSlot.selfLight),
          const Color(0xFF445566));
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('fixed styles expose only the theme text controls',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.setBubbleStyle(BubbleStyle.ww);
    final store = AppThemeStore.instance;
    final pack = AppThemePack.parse(
        Map<String, dynamic>.from(jsonDecode(
            File('docs/theme-example/content.json').readAsStringSync()) as Map),
        Directory('docs/theme-example').absolute.path);
    store.installed = [pack];
    store.activeId = pack.id;
    await store.adjust('bubble', true);
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: settings,
        child: const CupertinoApp(home: ThemeAppearanceScreen())));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bubble-text-selfLight')), findsOneWidget);
    expect(find.byKey(const ValueKey('bubble-color-selfLight')), findsNothing);
    expect(find.byKey(const ValueKey('bubble-text-otherLight')), findsNothing);
    await tester.ensureVisible(find.text('气泡和文字使用样式配色；切回默认样式后可调整'));
    expect(find.text('气泡和文字使用样式配色；切回默认样式后可调整'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.activeId = null;
    store.installed = [];
    settings.dispose();
  });
}
