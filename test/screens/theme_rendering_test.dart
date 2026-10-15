import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_chat/config/theme.dart';
import 'package:ai_chat/models/app_theme_pack.dart';
import 'package:ai_chat/models/message.dart';
import 'package:ai_chat/providers/settings_provider.dart';
import 'package:ai_chat/services/app_theme_store.dart';
import 'package:ai_chat/widgets/chat_bubble.dart';
import 'package:ai_chat/widgets/theme_assets.dart';

void main() {
  for (final folder in [
    'docs/theme-example',
    if (Directory('developDocs/themes/Hsin_theme').existsSync())
      'developDocs/themes/Hsin_theme',
    if (Directory('ThemeDevelopSpace/ThemesOutput/Aemeath_theme/Aemeath_theme')
        .existsSync())
      'ThemeDevelopSpace/ThemesOutput/Aemeath_theme/Aemeath_theme'
  ]) {
    testWidgets(
        '$folder supports short and long messages, preserves other bubble and user overrides',
        (tester) async {
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        final store = AppThemeStore.instance;
        final pack = AppThemePack.parse(
            Map<String, dynamic>.from(
                jsonDecode(File('$folder/content.json').readAsStringSync())
                    as Map),
            Directory(folder).absolute.path);
        store.installed = [pack];
        store.activeId = pack.id;
        final settings = SettingsProvider();
        await settings.setBubbleStyle(BubbleStyle.ww);
        final boundary = GlobalKey();
        for (final dark in [false, true]) {
          await tester.pumpWidget(ChangeNotifierProvider.value(
              value: settings,
              child: CupertinoApp(
                theme: AppTheme.buildTheme(
                    brightness: dark ? Brightness.dark : Brightness.light,
                    accent: AppColors.presetColors.first),
                home: RepaintBoundary(
                    key: boundary,
                    child: ThemeHeaderSurface(
                        slot: 'home',
                        child: CupertinoPageScaffold(
                          backgroundColor: CupertinoColors.transparent,
                          navigationBar: const CupertinoNavigationBar(
                              automaticBackgroundVisibility: false,
                              enableBackgroundFilterBlur: false,
                              backgroundColor: CupertinoColors.transparent,
                              middle: Text('AiChat')),
                          child: ColoredBox(
                              color: const Color(0xFF123456),
                              child: SafeArea(
                                  child: ListView(children: [
                                ChatBubble(
                                    message: Message(
                                        id: 'short',
                                        conversationId: 'a',
                                        content: '短',
                                        sender: MessageSender.user)),
                                ChatBubble(
                                    message: Message(
                                        id: 'long',
                                        conversationId: 'a',
                                        content:
                                            List.filled(12, '长段落与换行\n').join(),
                                        sender: MessageSender.user)),
                                ChatBubble(
                                    message: Message(
                                        id: 'other',
                                        conversationId: 'a',
                                        content: '角色气泡保留原样式',
                                        sender: MessageSender.character)),
                              ]))),
                        ))),
              )));
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.takeException(), isNull);
          expect(find.byType(ClipPath), findsWidgets);
          expect(settings.bubbleStyle, BubbleStyle.ww);
          final headerWidget = tester.widget<Image>(
              find.byKey(const ValueKey('theme-header-background')));
          expect(headerWidget.fit, BoxFit.cover);
          expect(headerWidget.alignment, const Alignment(0, -0.4));
          // The header must paint above the opaque, populated list surface.
          final render = boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final headerImage = await render.toImage();
          final pixels = (await headerImage.toByteData(
                  format: ui.ImageByteFormat.rawRgba))!
              .buffer
              .asUint8List();
          final offset = (8 * headerImage.width + 8) * 4;
          expect(pixels.sublist(offset, offset + 3), isNot([0x12, 0x34, 0x56]));
          final codec = await ui.instantiateImageCodec(
              await File(pack.path(pack.headers['home']!.file)).readAsBytes());
          final source = (await codec.getNextFrame()).image;
          final bounds = tester
              .getSize(find.byKey(const ValueKey('theme-header-background')));
          expect(bounds.height, 60);
          final scale =
              bounds.width / source.width > bounds.height / source.height
                  ? bounds.width / source.width
                  : bounds.height / source.height;
          final crop = Rect.fromLTWH(
              (source.width - bounds.width / scale) / 2,
              (source.height - bounds.height / scale) * 0.3,
              bounds.width / scale,
              bounds.height / scale);
          // Compare against a filtered reference crop. A nearest-neighbor
          // source pixel is unreliable for detailed, downscaled artwork.
          final referenceRecorder = ui.PictureRecorder();
          final referenceCanvas = Canvas(referenceRecorder);
          referenceCanvas.drawImageRect(source, crop, Offset.zero & bounds,
              Paint()..filterQuality = FilterQuality.medium);
          referenceCanvas.drawRect(
              Offset.zero & bounds,
              Paint()
                ..color =
                    dark ? const Color(0x55000000) : const Color(0x55FFFFFF));
          final referencePicture = referenceRecorder.endRecording();
          final reference = await referencePicture.toImage(
              bounds.width.ceil(), bounds.height.ceil());
          final referencePixels =
              (await reference.toByteData(format: ui.ImageByteFormat.rawRgba))!
                  .buffer
                  .asUint8List();
          for (var channel = 0; channel < 3; channel++) {
            final expected =
                referencePixels[(8 * reference.width + 8) * 4 + channel];
            expect(pixels[offset + channel], closeTo(expected, 8),
                reason:
                    'Header must show artwork with equal scaling and upper portrait crop');
          }
          reference.dispose();
          referencePicture.dispose();
          source.dispose();
          codec.dispose();
          headerImage.dispose();
          if (pack.bubbleLeading != null) {
            expect(find.byKey(const ValueKey('theme-bubble-leading')),
                findsWidgets);
            expect(pack.textColor, const Color(0xFFFFFFFF));
            final decoration = tester.getRect(
                find.byKey(const ValueKey('theme-bubble-leading')).first);
            final body = tester
                .getRect(find.byKey(const ValueKey('theme-bubble-body')).first);
            expect(decoration.left, lessThan(body.left));
            expect(decoration.right, greaterThan(body.left));
            expect(decoration.top, lessThan(body.top));
            final text = tester.getRect(find
                .byWidgetPredicate((widget) =>
                    widget is RichText && widget.text.toPlainText() == '短')
                .first);
            expect(text.left, greaterThanOrEqualTo(decoration.right));
          }
          final context = tester.element(find.byType(ChatBubble).first);
          expect(context.bubbleTextColor(true), pack.textColor);
          await store.adjust(dark ? 'textDark' : 'textLight', 0xFF556677);
          await tester.pump();
          expect(context.bubbleTextColor(true).toARGB32(), 0xFF556677);
          if (dark && const bool.fromEnvironment('THEME_RENDER_PREVIEWS')) {
            {
              final render = boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
              final image = await render.toImage();
              final bytes =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              await Directory('build').create(recursive: true);
              await File('build/${pack.id}-render-preview.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            }
          }
        }
        await store.enable(null);
        await tester.pump();
        expect(tester.getSize(find.byType(CupertinoNavigationBar)).height, 44);
        expect(settings.bubbleStyle, BubbleStyle.ww);
        expect(store.textColor(true), isNull);
        await tester.pumpWidget(const SizedBox());
        store.installed = [];
        settings.dispose();
      });
    });
  }
}
