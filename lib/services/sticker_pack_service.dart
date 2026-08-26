import 'dart:io';
import 'package:archive/archive.dart';
import 'package:uuid/uuid.dart';
import '../models/sticker_pack.dart';
import '../utils/sticker_path_helper.dart';

/// 创意工坊表情包 ZIP 解析服务。
///
/// ZIP 约定（V1.3.0）：
/// - 可在任意目录层级包含若干图片（png/jpg/jpeg/gif/webp）；
/// - 每个图片的文件名（去掉扩展名）即为该表情包备注；
/// - 解析后图片集中保存到 `stickers/packs/{uuid}/`，由 0 起编号命名。
class StickerPackService {
  static const Set<String> _imageExts = {
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
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
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      final lower = entry.name.toLowerCase();
      if (_imageExts.any((ext) => lower.endsWith(ext))) {
        images.add(entry);
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
      final label = _labelFromFileName(entry.name);
      if (label.isNotEmpty) labels[i] = label;
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

  /// 取 ZIP 条目的文件名并去掉最后一个扩展名，作为表情包备注。
  /// 保留中文、空格、下划线等原始命名，便于创作者直接用文件名表达语义。
  static String _labelFromFileName(String entryName) {
    final fileName = entryName.split('/').last.split('\\').last;
    final dot = fileName.lastIndexOf('.');
    return (dot > 0 ? fileName.substring(0, dot) : fileName).trim();
  }

  static String _extensionOf(String entryName) {
    final dot = entryName.lastIndexOf('.');
    return dot > 0 ? entryName.substring(dot).toLowerCase() : '.png';
  }
}
