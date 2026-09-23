import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// 已导入的 TTF 字体元数据。字体文件仅保存在应用文档目录中。
class ImportedFont {
  const ImportedFont({
    required this.name,
    required this.path,
    required this.sizeBytes,
  });

  final String name;
  final String path;
  final int sizeBytes;

  String get family => importedFontFamily(name);
}

bool isSupportedImportedFontFile(String filename) =>
    filename.toLowerCase().endsWith('.ttf');

String importedFontStorageName(String filename) {
  final base = filename.replaceFirst(RegExp(r'\.ttf$', caseSensitive: false), '');
  final safe = base.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  return safe.isEmpty ? '未命名字体' : safe;
}

String importedFontFamily(String name) =>
    'AiChatFont_${sha1.convert(utf8.encode(name)).toString()}';

/// 导入字体的本地持久化，独立于聊天和缓存目录。
class ImportedFontStorage {
  const ImportedFontStorage();

  Future<List<ImportedFont>> listFonts() async {
    final dir = await _fontsDir();
    if (!await dir.exists()) return const [];
    final fonts = <ImportedFont>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !isSupportedImportedFontFile(entity.path)) continue;
      final filename = entity.uri.pathSegments.last;
      fonts.add(ImportedFont(
        name: importedFontStorageName(filename),
        path: entity.path,
        sizeBytes: await entity.length(),
      ));
    }
    fonts.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return fonts;
  }

  Future<Uint8List?> loadFont(String name) async {
    final file = await _fontFile(name);
    if (!await file.exists()) return null;
    return Uint8List.fromList(await file.readAsBytes());
  }

  Future<void> saveFont(String sourceName, Uint8List bytes) async {
    if (!isSupportedImportedFontFile(sourceName)) {
      throw const FormatException('仅支持 .ttf 字体文件');
    }
    final dir = await _fontsDir();
    if (!await dir.exists()) await dir.create(recursive: true);
    await _fontFile(importedFontStorageName(sourceName)).then(
      (file) => file.writeAsBytes(bytes, flush: true),
    );
  }

  Future<void> deleteFont(String name) async {
    final file = await _fontFile(name);
    if (await file.exists()) await file.delete();
  }

  Future<int> totalBytes() async {
    final fonts = await listFonts();
    return fonts.fold<int>(0, (sum, font) => sum + font.sizeBytes);
  }

  Future<int> clear() async {
    final dir = await _fontsDir();
    if (!await dir.exists()) return 0;
    var freed = 0;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      try {
        freed += await entity.length();
        await entity.delete();
      } catch (_) {}
    }
    return freed;
  }

  Future<Directory> _fontsDir() async => Directory(
        '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}imported_fonts',
      );

  Future<File> _fontFile(String name) async => File(
        '${(await _fontsDir()).path}${Platform.pathSeparator}${importedFontStorageName(name)}.ttf',
      );
}
