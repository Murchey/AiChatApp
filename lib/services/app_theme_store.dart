import 'package:crypto/crypto.dart';
import 'imported_font_storage.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:archive/archive.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_theme_pack.dart';
import '../models/workshop_repository.dart';
import 'secure_config_storage.dart';

class AppThemeStore extends ChangeNotifier {
  AppThemeStore({Directory? directory}) : _rootDirectory = directory;
  final Directory? _rootDirectory;
  static final _loadedFonts = <String>{};
  static final instance = AppThemeStore();
  List<AppThemePack> installed = [];
  List<WorkshopRepository> repositories = [];
  String? activeId;
  Map<String, dynamic> _overrides = {};
  AppThemePack? get active {
    for (final p in installed) {
      if (p.id == activeId) return p;
    }
    return null;
  }

  Map<String, dynamic> get adjustments =>
      Map<String, dynamic>.from(_overrides[activeId] as Map? ?? {});
  bool get bubbleEnabled =>
      active?.bubble != null && adjustments['bubble'] != false;
  Color? textColor(bool dark) {
    if (!bubbleEnabled) return null;
    final value = adjustments[dark ? 'textDark' : 'textLight'];
    return value is int ? Color(value) : active!.textColor;
  }

  String? get fontChoice => active?.font == null
      ? null
      : adjustments['font'] as String? ?? '__theme__';
  String? get fontFamily =>
      fontChoice == '__theme__' ? active!.fontFamily : null;
  Future<Directory> get root async =>
      _rootDirectory ??
      Directory(
          '${(await getApplicationDocumentsDirectory()).path}/app_themes');
  Future<void> init() async {
    installed = [];
    final prefs = await SharedPreferences.getInstance();
    activeId = prefs.getString('app_theme_active');
    _overrides = Map<String, dynamic>.from(
        jsonDecode(prefs.getString('app_theme_adjustments') ?? '{}') as Map);
    final raw =
        await SecureConfigStorage.readJson(prefs, 'app_theme_repositories');
    repositories = [
      for (final r in jsonDecode(raw ?? '[]') as List)
        WorkshopRepository.fromJson(Map<String, dynamic>.from(r as Map))
    ];
    final dir = await root;
    if (await dir.exists()) {
      final pending = await dir.list().toList();
      for (final entity in pending) {
        if (entity is! Directory) continue;
        final name = entity.path.replaceAll('\\', '/').split('/').last;
        if (name.startsWith('.old-')) {
          final target = Directory('${dir.path}/${name.substring(5)}');
          if (!await target.exists()) {
            await entity.rename(target.path);
          } else {
            await entity.delete(recursive: true);
          }
        } else if (name.startsWith('.install-')) {
          await entity.delete(recursive: true);
        }
      }
      await for (final entity in dir.list()) {
        if (entity is! Directory ||
            entity.uri.pathSegments.any((s) => s.startsWith('.'))) {
          continue;
        }
        try {
          final pack = AppThemePack.parse(
              Map<String, dynamic>.from(jsonDecode(
                      await File('${entity.path}/content.json').readAsString())
                  as Map),
              entity.path);
          await validate(pack);
          installed.add(pack);
        } catch (e) {
          debugPrint('主题加载失败: $e');
        }
      }
    }
    if (active?.font != null) await _loadFont(active!);
    final choice = fontChoice;
    if (choice != null && choice.isNotEmpty && choice != '__theme__') {
      final bytes = await const ImportedFontStorage().loadFont(choice);
      if (bytes != null) {
        await (FontLoader(importedFontFamily(choice))
              ..addFont(Future.value(ByteData.sublistView(bytes))))
            .load();
      } else {
        await adjust('font', null);
      }
    }
    notifyListeners();
  }

  Future<void> saveRepositories(List<WorkshopRepository> values) async {
    final prefs = await SharedPreferences.getInstance();
    await SecureConfigStorage.writeJson(prefs, 'app_theme_repositories',
        jsonEncode(values.map((r) => r.toJson()).toList()));
    repositories = values;
    notifyListeners();
  }

  Future<void> adjust(String key, dynamic value) async {
    if (active == null) return;
    final map = adjustments;
    if (value == null) {
      map.remove(key);
    } else {
      map[key] = value;
    }
    _overrides[activeId!] = map;
    await (await SharedPreferences.getInstance())
        .setString('app_theme_adjustments', jsonEncode(_overrides));
    notifyListeners();
  }

  Future<void> enable(String? id) async {
    if (id != null) {
      final pack = installed.firstWhere((p) => p.id == id);
      await validate(pack);
      if (pack.font != null) await _loadFont(pack);
    }
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove('app_theme_active');
    } else {
      await prefs.setString('app_theme_active', id);
    }
    activeId = id;
    final choice = fontChoice;
    if (choice != null && choice.isNotEmpty && choice != '__theme__') {
      final bytes = await const ImportedFontStorage().loadFont(choice);
      if (bytes != null) {
        await (FontLoader(importedFontFamily(choice))
              ..addFont(Future.value(ByteData.sublistView(bytes))))
            .load();
      } else {
        await adjust('font', null);
      }
    }
    notifyListeners();
  }

  Future<void> _loadFont(AppThemePack pack) async {
    final bytes = await File(pack.path(pack.font!)).readAsBytes();
    final family = 'AppTheme_${pack.id}_${sha1.convert(bytes)}';
    pack.loadedFontFamily = family;
    if (_loadedFonts.contains(family)) return;
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    _loadedFonts.add(family);
  }

  Future<void> validate(AppThemePack pack) async {
    final checked = <String, (int, int)>{};
    for (final image in pack.images) {
      final dimensions = (image.width, image.height);
      if (checked.containsKey(image.file)) {
        if (checked[image.file] != dimensions) {
          throw FormatException('同一主题图片声明了不同尺寸: ${image.file}');
        }
        continue;
      }
      await _validateImage(pack.path(image.file), image);
      checked[image.file] = dimensions;
    }
    if (pack.preview != null && !checked.containsKey(pack.preview)) {
      await _validateImage(pack.path(pack.preview!), null);
    }
    if (pack.font != null) {
      final bytes = await File(pack.path(pack.font!)).readAsBytes();
      if (bytes.length < 12 ||
          !((bytes[0] == 0 &&
                  bytes[1] == 1 &&
                  bytes[2] == 0 &&
                  bytes[3] == 0) ||
              ascii.decode(bytes.take(4).toList(), allowInvalid: true) ==
                  'true')) {
        throw const FormatException('无效的 TTF 字体');
      }
      final tables = (bytes[4] << 8) | bytes[5];
      if (tables == 0 || 12 + tables * 16 > bytes.length) {
        throw const FormatException('TTF 字体表损坏');
      }
      final data = ByteData.sublistView(bytes);
      final tags = <String>{};
      for (var i = 0; i < tables; i++) {
        tags.add(ascii.decode(bytes.sublist(12 + i * 16, 16 + i * 16),
            allowInvalid: true));
        final offset = data.getUint32(12 + i * 16 + 8);
        final length = data.getUint32(12 + i * 16 + 12);
        if (offset + length > bytes.length) {
          throw const FormatException('TTF 字体表越界');
        }
      }
      if (!tags.containsAll(['head', 'maxp', 'cmap', 'hhea', 'hmtx', 'name']) ||
          !(tags.containsAll(['glyf', 'loca']) || tags.contains('CFF '))) {
        throw const FormatException('TTF 缺少必要字体表');
      }
    }
  }

  Future<void> _validateImage(String path, ThemeImageAsset? asset) async {
    if (!RegExp(r'\.(png|jpe?g|webp)$', caseSensitive: false).hasMatch(path)) {
      throw const FormatException('主题图片仅支持 PNG/JPG/WebP');
    }
    final bytes = await File(path).readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      if (descriptor.width * descriptor.height > 16777216) {
        throw const FormatException('主题图片像素过大');
      }
      if (asset != null &&
          (descriptor.width != asset.width ||
              descriptor.height != asset.height)) {
        throw FormatException('图片尺寸与清单不符: ${asset.file}');
      }
      final codec =
          await descriptor.instantiateCodec(targetWidth: 64, targetHeight: 64);
      try {
        if (codec.frameCount != 1) throw const FormatException('主题不支持动态图片');
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
      buffer.dispose();
    }
  }

  Future<AppThemePack> install(String zipPath, {bool replace = false}) async {
    final file = File(zipPath);
    if (await file.length() > 50 * 1024 * 1024) {
      throw const FormatException('主题压缩包不能超过 50 MiB');
    }
    final rootDir = await root;
    await rootDir.create(recursive: true);
    final staging = await Directory(
            '${rootDir.path}/.install-${DateTime.now().microsecondsSinceEpoch}')
        .create();
    try {
      await compute(_extractThemeFiles, [zipPath, staging.path]);
      final map = Map<String, dynamic>.from(
          jsonDecode(await File('${staging.path}/content.json').readAsString())
              as Map);
      final pack = AppThemePack.parse(map, staging.path);
      await validate(pack);
      final target = Directory('${rootDir.path}/${pack.id}');
      if (await target.exists() && !replace) {
        throw ThemeAlreadyInstalled(pack.id);
      }
      final old = Directory('${rootDir.path}/.old-${pack.id}');
      if (await old.exists()) await old.delete(recursive: true);
      if (await target.exists()) await target.rename(old.path);
      try {
        await staging.rename(target.path);
        final installedPack = AppThemePack.parse(map, target.path);
        if (activeId == pack.id && pack.font != null) {
          await _loadFont(installedPack);
        }
        installed.removeWhere((p) => p.id == pack.id);
        installed.add(installedPack);
        notifyListeners();
        try {
          if (await old.exists()) await old.delete(recursive: true);
        } catch (e) {
          debugPrint('旧主题清理稍后重试: $e');
        }
        return installedPack;
      } catch (_) {
        if (await target.exists()) await target.delete(recursive: true);
        if (await old.exists()) await old.rename(target.path);
        rethrow;
      }
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  Future<void> delete(String id) async {
    if (activeId == id) await enable(null);
    final pack = installed.firstWhere((p) => p.id == id);
    await Directory(pack.directory).delete(recursive: true);
    installed.removeWhere((p) => p.id == id);
    _overrides.remove(id);
    await (await SharedPreferences.getInstance())
        .setString('app_theme_adjustments', jsonEncode(_overrides));
    notifyListeners();
  }

  Future<List<int>> export(AppThemePack pack) async {
    return compute(_exportThemeFiles, pack.directory);
  }
}

// ZIP inflation/deflation and bulk file I/O run off the UI isolate. Keep all
// archive validation before extraction, including limits and duplicate paths.
void _extractThemeFiles(List<String> paths) {
  final file = File(paths[0]);
  if (file.lengthSync() > 50 * 1024 * 1024) {
    throw const FormatException('主题压缩包不能超过 50 MiB');
  }
  final archive = ZipDecoder().decodeBytes(file.readAsBytesSync());
  var total = 0;
  final names = <String>{};
  for (final entry in archive) {
    if (entry.isSymbolicLink) throw const FormatException('主题包不支持符号链接');
    themeResourcePath(entry.name.endsWith('/')
        ? entry.name.substring(0, entry.name.length - 1)
        : entry.name);
    if (!names.add(entry.name.toLowerCase())) {
      throw const FormatException('主题资源路径重复');
    }
    total += entry.size;
    if (total > 200 * 1024 * 1024 || names.length > 4096) {
      throw const FormatException('主题解压资源过大');
    }
  }
  for (final entry in archive) {
    if (!entry.isFile) continue;
    final target = File('${paths[1]}/${entry.name}');
    target.parent.createSync(recursive: true);
    target.writeAsBytesSync(entry.content as List<int>);
  }
}

List<int> _exportThemeFiles(String directory) {
  final archive = Archive();
  for (final entry
      in Directory(directory).listSync(recursive: true, followLinks: false)) {
    if (entry is File) {
      archive.addFile(ArchiveFile.bytes(
          entry.path.substring(directory.length + 1).replaceAll('\\', '/'),
          entry.readAsBytesSync()));
    }
  }
  return ZipEncoder().encode(archive);
}

class ThemeAlreadyInstalled implements Exception {
  final String id;
  ThemeAlreadyInstalled(this.id);
  @override
  String toString() => '主题 $id 已安装';
}
