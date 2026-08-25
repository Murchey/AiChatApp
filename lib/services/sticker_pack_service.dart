import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:uuid/uuid.dart';
import '../models/sticker_pack.dart';
import '../utils/sticker_path_helper.dart';

/// 创意工坊表情包 ZIP 解析服务。
///
/// ZIP 约定（V1.3.0）：
/// - 直接包含若干图片（png/jpg/jpeg/gif/webp/bmp）；
/// - 可选的同名 .txt 文件（如 `1.png` 对应 `1.txt`），其第一行作为该图片备注；
/// - 解析后图片集中保存到 `stickers/packs/{uuid}/`，由 0 起编号命名。
class StickerPackService {
  static const Set<String> _imageExts = {
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
    '.bmp',
  };

  /// 解析 zip 并落盘，返回 [StickerPack]；zip 内没有可识别图片时返回 null。
  /// [targetDirectory] 供测试注入临时目录；不传时写入 `stickers/packs/{uuid}/`。
  static Future<StickerPack?> parseStickerPackZip(
    String zipPath, {
    required String name,
    required String author,
    Directory? targetDirectory,
  }) async {
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final images = <ArchiveFile>[];
    final labelByStem = <String, String>{};
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      final lower = entry.name.toLowerCase();
      if (_imageExts.any((ext) => lower.endsWith(ext))) {
        images.add(entry);
      } else if (lower.endsWith('.txt')) {
        // .txt 标签按 UTF-8 解码，避免中文备注变成乱码。
        final text = utf8
            .decode(entry.content as List<int>, allowMalformed: true)
            .trim();
        final firstLine = text.split(RegExp(r'\r?\n')).first.trim();
        if (firstLine.isNotEmpty) {
          labelByStem[_normalizeStem(entry.name)] = firstLine;
        }
      }
    }
    if (images.isEmpty) return null;

    images.sort((a, b) => a.name.compareTo(b.name));
    final packId = const Uuid().v4();
    final dir =
        targetDirectory ?? await StickerPathHelper.packDirectory(packId);
    await dir.create(recursive: true);
    final paths = <String>[];
    final labels = <int, String>{};
    for (var i = 0; i < images.length; i++) {
      final entry = images[i];
      final file = File('${dir.path}/${i + 1}${_extensionOf(entry.name)}');
      if (!file.existsSync()) {
        await file.writeAsBytes(entry.content as List<int>, flush: true);
      }
      paths.add(file.path);
      final label = labelByStem[_normalizeStem(entry.name)];
      if (label != null) labels[i] = label;
    }

    return StickerPack(
      id: packId,
      name: name,
      author: author,
      coverImagePath: paths.first,
      imagePaths: paths,
      labels: labels,
      importedAt: DateTime.now(),
    );
  }

  /// 去掉目录与扩展名，并归一化大小写与分隔符，用于匹配同名 .txt。
  static String _normalizeStem(String entryName) {
    final fileName = entryName.split('/').last.split('\\').last;
    final dot = fileName.lastIndexOf('.');
    final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
    return stem.toLowerCase().replaceAll(RegExp(r'[_\- ]+'), '');
  }

  static String _extensionOf(String entryName) {
    final dot = entryName.lastIndexOf('.');
    return dot > 0 ? entryName.substring(dot).toLowerCase() : '.png';
  }
}
