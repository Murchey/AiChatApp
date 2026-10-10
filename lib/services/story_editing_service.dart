import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/story_package.dart';
import 'story_service.dart';

/// Editor reads its own complete catalog so a filtered community feed cannot
/// hide posts from search or remove posts when publishing.
class StoryEditingService {
  const StoryEditingService();

  Uri imageUri(StorySourceConfig config, String file, String image) =>
      _detailUri(config, file).resolve(image);

  Future<String> uploadImage(
      StorySourceConfig config, String file, Uint8List bytes) async {
    if (config.type != StorySourceType.cos) {
      throw StateError('只有 COS / OSS 来源支持图片上传');
    }
    final directory = _detailUri(config, file).resolve('.');
    String extension;
    String mime;
    if (bytes.length >= 8 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71) {
      extension = 'png';
      mime = 'image/png';
    } else if (bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255) {
      extension = 'jpg';
      mime = 'image/jpeg';
    } else if (bytes.length >= 6 &&
        String.fromCharCodes(bytes.take(6)).startsWith('GIF8')) {
      extension = 'gif';
      mime = 'image/gif';
    } else if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
        String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP') {
      extension = 'webp';
      mime = 'image/webp';
    } else {
      throw const FormatException('请选择 PNG、JPEG、GIF 或 WebP 图片');
    }
    final object = 'assets/img/${const Uuid().v4()}.$extension';
    final uri = _detailUri(config, object);
    final response = await http
        .put(uri,
            headers: {
              'Content-Type': mime,
              ...StoryService.staticHeaders(config, uri,
                  method: 'PUT', contentType: mime),
            },
            body: bytes)
        .timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('图片上传失败（HTTP ${response.statusCode}）');
    }
    final rootDirectory = StoryService.staticIndexUri(config).resolve('.');
    final folders = directory.path
        .substring(rootDirectory.path.length)
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList();
    final target = object.split('/');
    var common = 0;
    while (common < folders.length &&
        common < target.length &&
        folders[common] == target[common]) {
      common++;
    }
    return [
      ...List.filled(folders.length - common, '..'),
      ...target.skip(common)
    ].join('/');
  }

  Future<void> deleteImage(StorySourceConfig config, String file, String image,
      {StoryCatalogEntry? entry}) async {
    if (config.type != StorySourceType.cos) {
      throw StateError('只有 COS / OSS 来源支持图片删除');
    }
    final uri = imageUri(config, file, image);
    final allowed = _detailUri(config, 'assets/img/placeholder').resolve('.');
    if (uri.origin != allowed.origin ||
        !uri.path.startsWith(allowed.path) ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path == allowed.path) {
      throw const FormatException('只能删除当前故事仓库 assets/img/ 下的图片');
    }
    Map<String, dynamic>? detail;
    if (entry != null) detail = await loadDetail(config, entry);
    await StoryService.deleteStaticObject(config, uri);
    if (detail != null) {
      detail['images'] = (detail['images'] as List? ?? [])
          .where((p) => imageUri(config, file, p as String) != uri)
          .toList();
      try {
        await StoryService.putStaticJson(
            config, _detailUri(config, file), detail);
      } catch (_) {
        throw StateError('图片已删除，但帖子图片路径同步失败，请重试删除或保存帖子');
      }
    }
  }

  Future<void> checkWrite(StorySourceConfig config) =>
      StoryService.probeStaticWrite(config);

  Future<Map<String, dynamic>> loadIndex(StorySourceConfig config) async {
    final value = await StoryService.getStaticJson(
        config, StoryService.staticIndexUri(config),
        filePath: config.path);
    if (value is! Map ||
        value['stories'] is! List ||
        (value['stories'] as List).any((v) => v is! Map)) {
      throw const FormatException('索引格式无效，需要 stories 列表');
    }
    return Map<String, dynamic>.from(value);
  }

  Future<Map<String, dynamic>> loadDetail(
      StorySourceConfig config, StoryCatalogEntry entry) async {
    final value = await StoryService.getStaticJson(
        config, _detailUri(config, entry.file),
        filePath: entry.file);
    if (value is! Map) throw const FormatException('帖子详情格式无效');
    final detail = Map<String, dynamic>.from(value);
    final story = StoryPackage.fromJson(detail);
    if (story.storyId != entry.storyId ||
        (entry.hasVersion && story.version != entry.version)) {
      throw const FormatException('帖子编号或版本与索引不一致，请刷新');
    }
    return detail;
  }

  Uri _detailUri(StorySourceConfig config, String file) {
    final index = StoryService.staticIndexUri(config);
    final directory = index.resolve('.');
    final uri = StoryService.resolveStaticFile(index, file);
    if (uri.origin != index.origin ||
        !uri.path.startsWith(directory.path) ||
        uri == index ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('详情文件必须位于当前故事目录内');
    }
    return uri;
  }

  Future<void> publish(
      StorySourceConfig config, Map<String, dynamic> detail, String file,
      {required bool isNew}) async {
    final story = StoryPackage.fromJson(detail);
    if (story.introduction.isEmpty) throw const FormatException('请填写帖子正文');
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_-]*$').hasMatch(story.storyId)) {
      throw const FormatException('故事编号只能包含英文、数字、短横线和下划线');
    }
    // Always merge into the current remote index, preserving unrelated posts
    // and additional fields rather than overwriting with the visible list.
    final index = await loadIndex(config);
    final rows = (index['stories'] as List)
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
    final position = rows.indexWhere(
        (v) => StoryCatalogEntry.fromJson(v).storyId == story.storyId);
    if (isNew && position >= 0) {
      throw const FormatException('故事编号已存在，请使用另一个编号');
    }
    if (!isNew && position < 0) {
      throw const FormatException('该帖子已从索引移除，请刷新后重试');
    }
    if (!isNew &&
        (rows[position]['file'] != file ||
            (rows[position]['version'] != null &&
                StoryCatalogEntry.fromJson(rows[position]).version !=
                    story.version))) {
      throw const FormatException('帖子版本已更新，请刷新后重新编辑');
    }
    final metadata = StoryCatalogEntry(
      storyId: story.storyId,
      version: story.version,
      title: story.title,
      author: story.author,
      summary: story.summary,
      publishedAt: story.publishedAt,
      tags: story.tags,
      file: file,
    ).toJson();
    metadata.remove('version');
    if (isNew) {
      rows.insert(0, metadata);
    } else {
      rows[position] = {...rows[position], ...metadata};
      rows[position].remove('version');
    }
    await StoryService.putStaticJson(config, _detailUri(config, file), detail);
    index['stories'] = rows;
    index.remove('schemaVersion');
    try {
      await StoryService.putStaticJson(
          config, StoryService.staticIndexUri(config), index);
    } catch (_) {
      throw StateError('详情已上传，但索引更新失败。请保留当前内容并再次保存');
    }
  }
}
