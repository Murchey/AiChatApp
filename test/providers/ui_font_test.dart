import 'dart:io';
import 'package:ai_chat/providers/settings_provider.dart';
import 'package:ai_chat/services/imported_font_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// This test uses path_provider's platform interface to isolate font files.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FontPaths extends PathProviderPlatform {
  final String path;
  _FontPaths(this.path);
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('imported UI font persists, restores and resets after deletion',
      () async {
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('aichat-font-test');
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FontPaths(dir.path);
    addTearDown(() async {
      PathProviderPlatform.instance = previous;
      await dir.delete(recursive: true);
    });
    final bytes = await rootBundle
        .load('packages/cupertino_icons/assets/CupertinoIcons.ttf');
    const storage = ImportedFontStorage();
    await storage.saveFont('TestUI.ttf', bytes.buffer.asUint8List());
    final settings = SettingsProvider();
    await settings.init();
    await settings.setUiFont('TestUI');
    expect(settings.uiFontFamily, importedFontFamily('TestUI'));
    final restarted = SettingsProvider();
    await restarted.init();
    expect(restarted.uiFontName, 'TestUI');
    await storage.deleteFont('TestUI');
    await restarted.clearDeletedBubbleFont('TestUI');
    expect(restarted.uiFontFamily, isNull);
    expect((await SharedPreferences.getInstance()).containsKey('ui_font_name'),
        false);
  });
}
