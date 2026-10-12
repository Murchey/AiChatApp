import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/story_package.dart';
import '../models/story_index.dart';
import 'dart:convert';
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

  String rootIndexFile(StorySourceConfig config) =>
      StoryService.staticIndexUri(config).pathSegments.last;

  Future<Map<String, dynamic>> loadIndexPage(
      StorySourceConfig config, String file) async {
    if (file == rootIndexFile(config)) return loadIndex(config);
    StoryIndexReference.parse({
      'indexes': [
        {'file': rootIndexFile(config)},
        {'file': file}
      ]
    }, rootIndexFile(config));
    final value = await StoryService.getStaticJson(
        config, StoryService.staticIndexUri(config).resolve(file),
        filePath: StoryService.staticFilePath(
            config, StoryService.staticIndexUri(config).resolve(file)));
    parseStaticStories(value);
    return Map<String, dynamic>.from(value as Map);
  }

  Future<Map<String, Map<String, dynamic>>> _loadAllIndexes(
      StorySourceConfig config) async {
    final rootFile = rootIndexFile(config);
    final root = await loadIndex(config);
    parseStaticStories(root);
    final refs = StoryIndexReference.parse(root, rootFile);
    final pages = <String, Map<String, dynamic>>{rootFile: root};
    for (final ref in refs.skip(1)) {
      pages[ref.file] = await loadIndexPage(config, ref.file);
    }
    final ids = <String>{};
    for (final page in pages.values) {
      for (final entry in parseStaticStories(page)) {
        if (!ids.add(entry.storyId)) {
          throw const FormatException('不同索引包含重复故事编号，请先修正仓库');
        }
      }
    }
    return pages;
  }

  Future<void> _writeIndexChanges(
      StorySourceConfig config,
      Map<String, Map<String, dynamic>> before,
      Map<String, Map<String, dynamic>> after) async {
    final root = rootIndexFile(config);
    final changed = after.keys
        .where((k) => jsonEncode(before[k]) != jsonEncode(after[k]))
        .toList();
    changed.sort((a, b) => a == root
        ? 1
        : b == root
            ? -1
            : 0);
    final attempted = <String>[];
    try {
      for (final file in changed) {
        attempted.add(file);
        await StoryService.putStaticJson(config,
            StoryService.staticIndexUri(config).resolve(file), after[file]!);
      }
    } catch (_) {
      var restored = true;
      for (final file in attempted.reversed) {
        try {
          final uri = StoryService.staticIndexUri(config).resolve(file);
          if (before[file] == null) {
            await StoryService.deleteStaticObject(config, uri);
          } else {
            await StoryService.putStaticJson(config, uri, before[file]!);
          }
        } catch (_) {
          restored = false;
        }
      }
      throw StateError(restored
          ? '详情已上传，但索引更新失败。已尝试恢复原索引，请保留当前内容并再次保存'
          : '索引更新失败，部分索引恢复失败。请保留当前内容，刷新检查远端索引后再发布');
    }
  }

  Future<Map<String, dynamic>> loadDetail(
      StorySourceConfig config, StoryCatalogEntry entry) async {
    final value = await StoryService.getStaticJson(
        config, _detailUri(config, entry.file),
        filePath: StoryService.staticFilePath(
            config, _detailUri(config, entry.file)));
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
      {required bool isNew, StoryCatalogEntry? previousEntry}) async {
    final story = StoryPackage.fromJson(detail);
    if (story.introduction.isEmpty) throw const FormatException('请填写帖子正文');
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_-]*$').hasMatch(story.storyId)) {
      throw const FormatException('故事编号只能包含英文、数字、短横线和下划线');
    }
    final before = await _loadAllIndexes(config);
    final pages = <String, Map<String, dynamic>>{
      for (final page in before.entries)
        page.key: Map<String, dynamic>.from(
            jsonDecode(jsonEncode(page.value)) as Map),
    };
    final rootFile = rootIndexFile(config);
    final refs = StoryIndexReference.parse(pages[rootFile], rootFile).toList();
    String? owner;
    Map<String, dynamic>? originalRow;
    final oldId = previousEntry?.storyId ?? story.storyId;
    for (final page in pages.entries) {
      for (final value in page.value['stories'] as List) {
        final row = Map<String, dynamic>.from(value as Map);
        if (row['storyId'] == story.storyId &&
            (isNew || row['storyId'] != oldId)) {
          throw const FormatException('故事编号已存在，请使用另一个编号');
        }
        if (!isNew && row['storyId'] == oldId) {
          owner = page.key;
          originalRow = row;
        }
        if (row['file'] == file && row['storyId'] != oldId) {
          throw const FormatException('其他帖子已使用此详情文件');
        }
      }
    }
    if (!isNew && (owner == null || originalRow == null)) {
      throw const FormatException('该帖子已从索引移除，请刷新后重试');
    }
    if (!isNew &&
        (originalRow!['file'] != (previousEntry?.file ?? file) ||
            (originalRow['version'] != null &&
                StoryCatalogEntry.fromJson(originalRow).version !=
                    (previousEntry?.version ?? story.version)))) {
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
    ).toJson()
      ..remove('version');
    if (isNew) {
      var overflow = <dynamic>[metadata];
      var i = 0;
      while (i < refs.length || overflow.isNotEmpty) {
        if (i == refs.length) {
          var number = 2;
          String name;
          do {
            name = 'index-${number++}.json';
          } while (pages.containsKey(name) || name == rootFile);
          refs.add(
              StoryIndexReference(file: name, title: '第 ${refs.length + 1} 页'));
          pages[name] = {'stories': <dynamic>[]};
        }
        final page = pages[refs[i].file]!;
        final values = [...overflow, ...page['stories'] as List];
        page['stories'] = values.take(100).toList();
        overflow = values.skip(100).toList();
        i++;
      }
    } else {
      final values = pages[owner]!['stories'] as List;
      final position = values.indexWhere((v) => (v as Map)['storyId'] == oldId);
      values[position] = {...originalRow!, ...metadata}..remove('version');
    }
    final root = pages[rootFile]!;
    if (isNew || root.containsKey('indexes')) {
      final previousRefs = before[rootFile]!['indexes'] as List? ?? [];
      root['indexes'] = [
        for (final ref in refs)
          {
            for (final old in previousRefs)
              if (old is Map && old['file'] == ref.file)
                ...Map<String, dynamic>.from(old),
            ...ref.toJson(),
          }
      ];
    }
    root.remove('schemaVersion');
    await StoryService.putStaticJson(config, _detailUri(config, file), detail);
    await _writeIndexChanges(config, before, pages);
    if (!isNew && previousEntry != null && previousEntry.file != file) {
      try {
        await StoryService.deleteStaticObject(
            config, _detailUri(config, previousEntry.file));
      } catch (_) {
        // The committed index already references the new detail file.
      }
    }
  }

  Future<void> deletePost(
      StorySourceConfig config, StoryCatalogEntry entry) async {
    if (config.type != StorySourceType.cos) {
      throw StateError('只有 COS / OSS 来源支持删除帖子');
    }
    final uri = _detailUri(config, entry.file);
    final before = await _loadAllIndexes(config);
    final pages = <String, Map<String, dynamic>>{
      for (final page in before.entries)
        page.key: Map<String, dynamic>.from(
            jsonDecode(jsonEncode(page.value)) as Map),
    };
    Map<String, dynamic>? owner;
    for (final page in pages.values) {
      final rows = page['stories'] as List;
      for (final row in rows) {
        final item =
            StoryCatalogEntry.fromJson(Map<String, dynamic>.from(row as Map));
        if (item.storyId == entry.storyId) {
          if (item.file != entry.file ||
              (item.hasVersion && item.version != entry.version)) {
            throw const FormatException('帖子已更新，请刷新列表后重新删除');
          }
          owner = page;
        } else if (item.file == entry.file) {
          throw const FormatException('其他帖子也引用了此详情文件，请先修正索引');
        }
      }
    }
    if (owner == null) return;
    // Save the indexes before deleting the detail so failed writes preserve a
    // readable post. No compaction is performed after deletion.
    (owner['stories'] as List)
        .removeWhere((v) => (v as Map)['storyId'] == entry.storyId);
    await _writeIndexChanges(config, before, pages);
    try {
      await StoryService.deleteStaticObject(config, uri);
    } catch (_) {
      throw StateError('帖子已从索引删除，但旧详情文件清理失败：${entry.file}');
    }
  }
}
