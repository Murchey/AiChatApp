import 'package:ai_chat/config/theme.dart';
import 'package:ai_chat/screens/app_themes_screen.dart';
import 'package:ai_chat/services/app_theme_store.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('theme management and sources use $brightness semantic colors',
        (tester) async {
      final store = AppThemeStore.instance;
      final installed = store.installed;
      final repositories = store.repositories;
      final activeId = store.activeId;
      store.installed = [];
      store.repositories = [];
      store.activeId = null;
      addTearDown(() {
        store.installed = installed;
        store.repositories = repositories;
        store.activeId = activeId;
      });
      final dark = brightness == Brightness.dark;
      final ink = dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
      final background =
          dark ? AppColors.scaffoldDark : AppColors.scaffoldLight;
      Color? textColor(String text) => tester
          .renderObject<RenderParagraph>(find.text(text))
          .text
          .style
          ?.color;
      await tester.pumpWidget(CupertinoApp(
        theme: AppTheme.buildTheme(
            brightness: brightness, accent: AppColors.presetColors.first),
        // Reproduce a surrounding route with fixed default text color.
        builder: (_, child) => DefaultTextStyle(
            style: const TextStyle(color: CupertinoColors.black),
            child: child!),
        home: const AppThemesScreen(),
      ));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<CupertinoPageScaffold>(find.byType(CupertinoPageScaffold))
              .backgroundColor,
          background);
      expect(textColor('尚未安装主题。可本地导入或配置在线来源。'), ink);
      expect(textColor('已安装'), ink);
      final navBottom = tester.getBottomLeft(find.text('应用主题')).dy;
      expect(tester.getTopLeft(find.text('已安装')).dy, greaterThan(navBottom));
      await tester.tap(find.text('在线主题'));
      await tester.pumpAndSettle();
      expect(textColor('点击右上角配置仓库或对象存储来源。'), ink);
      await tester.tap(find.byIcon(CupertinoIcons.gear));
      await tester.pumpAndSettle();
      expect(
          textColor(
              'GitHub/Gitee：ThemeStore Release 下的 ZIP。对象存储：配置路径/Theme/ 下的 ZIP，需具备列举和读取权限。'),
          ink);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
