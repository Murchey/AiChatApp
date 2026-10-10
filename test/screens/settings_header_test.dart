import 'package:ai_chat/widgets/settings/settings_ui.dart';
import 'package:ai_chat/config/theme.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
        '42px outlined frosted back button and transparent header: $brightness',
        (tester) async {
      await tester.pumpWidget(CupertinoApp(
        theme: AppTheme.buildTheme(
            brightness: brightness, accent: CupertinoColors.systemBlue),
        home: Builder(
            builder: (context) => CupertinoPageScaffold(
                  navigationBar: settingsNavigationBar(context, '二级页面'),
                  child: ListView(
                      children: List.generate(30, (i) => Text('内容 $i'))),
                )),
      ));
      await tester.pumpAndSettle();
      final button = find
          .ancestor(
              of: find.byIcon(CupertinoIcons.chevron_left),
              matching: find.byType(Container))
          .first;
      expect(tester.getSize(button), const Size(42, 42));
      final decoration =
          tester.widget<Container>(button).decoration! as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(decoration.border, isNotNull);
      expect(find.byType(BackdropFilter), findsNWidgets(2));
      final mask = tester.widget<ShaderMask>(find.byType(ShaderMask));
      expect(mask.blendMode, BlendMode.dstIn);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('chat settings retain previous compact navigation',
      (tester) async {
    await tester.pumpWidget(CupertinoApp(
        home: Builder(
            builder: (context) => CupertinoPageScaffold(
                  navigationBar:
                      settingsNavigationBar(context, '聊天设置', legacy: true),
                  child: const SizedBox(),
                ))));
    expect(find.byType(CupertinoNavigationBar), findsOneWidget);
    expect(find.byType(ShaderMask), findsNothing);
  });
}
