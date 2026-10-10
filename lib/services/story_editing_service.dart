import '../models/story_package.dart';
import 'story_service.dart';

/// Editor reads its own complete catalog so a filtered community feed cannot
/// hide posts from search or remove posts when publishing.
class StoryEditingService {
  const StoryEditingService();

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
    if (story.storyId != entry.storyId || story.version != entry.version) {
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
            StoryCatalogEntry.fromJson(rows[position]).version !=
                story.version)) {
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
    if (isNew) {
      rows.insert(0, metadata);
    } else {
      rows[position] = {...rows[position], ...metadata};
    }
    await StoryService.putStaticJson(config, _detailUri(config, file), detail);
    index['stories'] = rows;
    try {
      await StoryService.putStaticJson(
          config, StoryService.staticIndexUri(config), index);
    } catch (_) {
      throw StateError('详情已上传，但索引更新失败。请保留当前内容并再次保存');
    }
  }
}
