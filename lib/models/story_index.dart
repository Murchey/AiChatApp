import 'story_package.dart';

/// All index names are siblings of the configured root; detail paths remain
/// relative to that root regardless of the page from which they were loaded.
class StoryIndexReference {
  final String file;
  final String title;
  const StoryIndexReference({required this.file, required this.title});
  Map<String, dynamic> toJson() => {'file': file, 'title': title};

  static List<StoryIndexReference> parse(dynamic json, String rootFile) {
    final raw = json is Map ? json['indexes'] : null;
    if (raw == null) {
      return [StoryIndexReference(file: rootFile, title: '最新故事')];
    }
    if (raw is! List || raw.isEmpty) {
      throw const FormatException('索引目录 indexes 必须是非空数组');
    }
    final seen = <String>{};
    final result = <StoryIndexReference>[];
    for (final value in raw) {
      if (value is! Map || value['file'] is! String) {
        throw const FormatException('索引目录条目缺少 file');
      }
      final file = value['file'] as String;
      if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_.-]*\.json$').hasMatch(file) ||
          !seen.add(file)) {
        throw const FormatException('索引文件必须是同目录的唯一 JSON 文件名');
      }
      final title = (value['title'] ?? file).toString().trim();
      result.add(
          StoryIndexReference(file: file, title: title.isEmpty ? file : title));
    }
    if (result.first.file != rootFile) {
      throw const FormatException('索引目录第一项必须是根索引文件');
    }
    return result;
  }
}

List<StoryCatalogEntry> parseStaticStories(dynamic json) {
  final raw = json is List
      ? json
      : json is Map
          ? json['stories']
          : null;
  if (raw is! List) throw const FormatException('故事目录缺少 stories 列表');
  final ids = <String>{};
  return raw.map((v) {
    if (v is! Map) throw const FormatException('故事条目格式无效');
    final entry = StoryCatalogEntry.fromJson(Map<String, dynamic>.from(v));
    if (entry.storyId.isEmpty ||
        entry.title.isEmpty ||
        !ids.add(entry.storyId)) {
      throw const FormatException('故事条目缺少 ID、标题或 ID 重复');
    }
    return entry;
  }).toList();
}
