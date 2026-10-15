import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_chat/services/app_theme_store.dart';
import 'package:ai_chat/models/app_theme_pack.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Map<String, dynamic> sample() => Map<String, dynamic>.from(
      jsonDecode(File('docs/theme-example/content.json').readAsStringSync())
          as Map);
  test('parses complete theme; validates slots, paths and nine slice center',
      () {
    final pack = AppThemePack.parse(sample(), 'example');
    expect(pack.navigation.length, 4);
    expect(pack.images.length, 11);
    expect(pack.font, 'fonts/self.ttf');
    expect(pack.navigationSize('chat', 24), 24);
    for (final invalid in [0, 37, '32', double.nan]) {
      final data = sample();
      data['navigation']['chat']['size'] = invalid;
      expect(() => AppThemePack.parse(data, ''), throwsFormatException);
    }
    for (final path in [
      '../escape.png',
      '/absolute.png',
      'a\\b.png',
      'C:/file.png',
      'a//b.png'
    ]) {
      expect(() => themeResourcePath(path), throwsFormatException);
    }
    var data = sample();
    data['navigation'] = {
      'chat': {'normal': 'a.png', 'width': 96, 'height': 96}
    };
    expect(() => AppThemePack.parse(data, ''), throwsFormatException);
    data = sample();
    (data['selfBubble'] as Map)['stretchInsets'] = {
      'left': 120,
      'right': 120,
      'top': 0,
      'bottom': 0
    };
    expect(() => AppThemePack.parse(data, ''), throwsFormatException);
    expect(() => AppThemePack.parse({'id': 'empty', 'name': 'Empty'}, ''),
        throwsFormatException);
  });
  test(
      'installs, rejects duplicates, exports, reimports and preserves adjustments',
      () async {
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('aichat_theme_test_');
    final store = AppThemeStore(directory: Directory('${dir.path}/themes'));
    try {
      final pack = await store.install('docs/soft-cloud-theme.zip');
      expect(store.active, isNull);
      expect(File(pack.path('content.json')).existsSync(), true);
      await expectLater(store.install('docs/soft-cloud-theme.zip'),
          throwsA(isA<ThemeAlreadyInstalled>()));
      await store.enable(pack.id);
      expect(store.bubbleEnabled, true);
      expect(store.fontFamily, isNotNull);
      await store.adjust('textDark', 0xFF123456);
      await store.enable(null);
      expect(store.textColor(true), isNull);
      await store.enable(pack.id);
      expect(store.textColor(true)!.toARGB32(), 0xFF123456);
      await store.init();
      expect(store.activeId, pack.id);
      expect(store.textColor(true)!.toARGB32(), 0xFF123456);
      final zip = File('${dir.path}/roundtrip.zip');
      await zip.writeAsBytes(await store.export(pack));
      await store.install(zip.path, replace: true);
      expect(store.activeId, pack.id);
      await store.delete(pack.id);
      expect(store.active, isNull);
      expect(store.installed, isEmpty);
      await store.install(zip.path);
      expect(store.installed.single.id, pack.id);
    } finally {
      store.dispose();
      await dir.delete(recursive: true);
    }
  });
  test(
      'Hsin theme installs with shared navigation states and validated leading image',
      () async {
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('aichat_hsin_test_');
    final store = AppThemeStore(directory: dir);
    try {
      final pack = await store.install('developDocs/themes/Hsin_theme.zip');
      expect(pack.id, 'Hsin_theme');
      expect(pack.headers.keys, ['home', 'contacts']);
      expect(pack.bubbleLeading!.width, 320);
      expect(pack.bubbleLeadingSize, 56);
      expect(pack.navigationSize('chat', 21), 36);
      expect(pack.textColor.toARGB32(), 0xFFFFFFFF);
      for (final pair in pack.navigation.values) {
        expect(pair.$1.file, pair.$2.file);
      }
      final data = Map<String, dynamic>.from(
          jsonDecode(await File(pack.path('content.json')).readAsString())
              as Map);
      data['selfBubble']['leading']['size'] = -1;
      expect(() => AppThemePack.parse(data, ''), throwsFormatException);
      data['selfBubble']['leading']['size'] = 40;
      data['selfBubble']['leading']['file'] = '../outside.png';
      expect(() => AppThemePack.parse(data, ''), throwsFormatException);
    } finally {
      store.dispose();
      await dir.delete(recursive: true);
    }
  },
      skip: !File('developDocs/themes/Hsin_theme.zip').existsSync()
          ? 'Personal Hsin artwork is local-only; run build_hsin_theme.py to verify it'
          : false);
  test(
      'rejects wrong dimensions, missing images, damaged fonts and traversal without replacing old data',
      () async {
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('aichat_theme_bad_');
    final store = AppThemeStore(directory: Directory('${dir.path}/themes'));
    try {
      await store.install('docs/soft-cloud-theme.zip');
      final good =
          File('${dir.path}/themes/soft-cloud/content.json').readAsStringSync();
      for (final kind in ['dimensions', 'missing', 'font', 'traversal']) {
        final archive = ZipDecoder()
            .decodeBytes(await File('docs/soft-cloud-theme.zip').readAsBytes());
        final result = Archive();
        final data = sample();
        if (kind == 'dimensions') {
          (data['headers'] as Map)['home']['width'] = 251;
        }
        if (kind == 'missing') {
          (data['headers'] as Map)['home']['file'] = 'images/missing.png';
        }
        if (kind == 'font') {
          data['selfFont'] = {'file': 'fonts/damaged.ttf', 'name': 'Bad'};
        }
        for (final entry in archive) {
          if (entry.name != 'content.json') {
            result.addFile(
                ArchiveFile.bytes(entry.name, entry.content as List<int>));
          }
        }
        result.addFile(ArchiveFile.string('content.json', jsonEncode(data)));
        if (kind == 'font') {
          result.addFile(ArchiveFile.bytes('fonts/damaged.ttf', [0, 1, 0, 0]));
        }
        if (kind == 'traversal') {
          result.addFile(ArchiveFile.string('../outside.txt', 'bad'));
        }
        final zip = File('${dir.path}/bad.zip');
        await zip.writeAsBytes(ZipEncoder().encode(result));
        await expectLater(
            store.install(zip.path, replace: true), throwsA(anything));
        expect(
            File('${dir.path}/themes/soft-cloud/content.json')
                .readAsStringSync(),
            good);
        expect(File('${dir.path}/outside.txt').existsSync(), false);
      }
    } finally {
      store.dispose();
      await dir.delete(recursive: true);
    }
  });
}
