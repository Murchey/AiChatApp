import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:ai_chat/models/app_theme_pack.dart';
import 'package:ai_chat/services/app_theme_store.dart';
import 'package:ai_chat/services/theme_image.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ImageInfo> decoded(ImageProvider provider) {
  final result = Completer<ImageInfo>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late ImageStreamListener listener;
  listener = ImageStreamListener((image, _) {
    result.complete(image);
    stream.removeListener(listener);
  }, onError: (Object error, StackTrace? stack) {
    result.completeError(error, stack);
    stream.removeListener(listener);
  });
  stream.addListener(listener);
  return result.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'large artwork decodes within budget, reuses keys and preserves logical size',
      () async {
    final dir = await Directory.systemTemp.createTemp('theme-decode-');
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const Color(0xFFDC86A1), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final source = await picture.toImage(4096, 2048);
    final bytes = await source.toByteData(format: ui.ImageByteFormat.png);
    source.dispose();
    picture.dispose();
    await File('${dir.path}/bubble.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    final manifest = <String, dynamic>{
      'id': 'large',
      'name': 'Large',
      'selfBubble': {
        'file': 'bubble.png',
        'width': 4096,
        'height': 2048,
        'stretchInsets': {'left': 128, 'right': 128, 'top': 128, 'bottom': 128},
        'textColor': '#FFFFFF'
      },
    };
    final pack = AppThemePack.parse(manifest, dir.path);
    try {
      final provider = themeImageProvider(pack, pack.bubble!,
          maxDimension: 1024, sourceScale: 8);
      final image = await decoded(provider);
      expect(image.image.width, 1024);
      expect(image.image.height, 512);
      expect(image.scale, 2);
      expect(image.image.width / image.scale, 4096 / 8);
      final key = await provider.obtainKey(ImageConfiguration.empty);
      final repeated = themeImageProvider(pack, pack.bubble!,
          maxDimension: 1024, sourceScale: 8);
      expect(await repeated.obtainKey(ImageConfiguration.empty), key);
      expect(PaintingBinding.instance.imageCache.containsKey(key), true);
      final reinstalled = AppThemePack.parse(manifest, dir.path);
      final replaced = themeImageProvider(reinstalled, reinstalled.bubble!,
          maxDimension: 1024, sourceScale: 8);
      expect(await replaced.obtainKey(ImageConfiguration.empty), isNot(key));
      const small = ThemeImageAsset('bubble.png', 240, 120);
      final smallProvider =
          themeImageProvider(pack, small, maxDimension: 1024) as ResizeImage;
      expect(smallProvider.width, 240); // Never upscale small theme assets.
      image.dispose();
    } finally {
      PaintingBinding.instance.imageCache.clear();
      await dir.delete(recursive: true);
    }
  });

  test(
      'install, replace and delete preserve unrelated image cache and refresh theme keys',
      () async {
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('theme-cache-');
    final store = AppThemeStore(directory: dir);
    final avatar = FileImage(File('docs/theme-example/images/chat.png'));
    final avatarInfo = await decoded(avatar);
    final avatarKey = await avatar.obtainKey(ImageConfiguration.empty);
    try {
      final first = await store.install('docs/soft-cloud-theme.zip');
      final oldProvider =
          themeImageProvider(first, first.bubble!, maxDimension: 1024);
      final oldKey = await oldProvider.obtainKey(ImageConfiguration.empty);
      final oldImage = await decoded(oldProvider);
      final replacement =
          await store.install('docs/soft-cloud-theme.zip', replace: true);
      final newProvider = themeImageProvider(replacement, replacement.bubble!,
          maxDimension: 1024);
      expect(
          await newProvider.obtainKey(ImageConfiguration.empty), isNot(oldKey));
      expect(PaintingBinding.instance.imageCache.containsKey(avatarKey), true);
      await store.delete(replacement.id);
      expect(PaintingBinding.instance.imageCache.containsKey(avatarKey), true);
      oldImage.dispose();
      // Same-file reuse is still validated against every declared dimension.
      final data = jsonDecode(
              await File('docs/theme-example/content.json').readAsString())
          as Map<String, dynamic>;
      data['navigation']['chat']['selected'] =
          data['navigation']['chat']['normal'];
      data['navigation']['contacts']['normal'] =
          data['navigation']['chat']['normal'];
      data['navigation']['contacts']['width'] = 1;
      await expectLater(
          store.validate(AppThemePack.parse(data, 'docs/theme-example')),
          throwsFormatException);
    } finally {
      avatarInfo.dispose();
      store.dispose();
      PaintingBinding.instance.imageCache.clear();
      await dir.delete(recursive: true);
    }
  });
}
