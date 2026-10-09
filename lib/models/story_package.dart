import 'dart:convert';

enum StorySourceType { server, cos, github, gitee }

class StoryMemory {
  final String id;
  final int order;
  final String content;

  const StoryMemory(
      {required this.id, required this.order, required this.content});
}

class StoryChapter {
  final String id;
  final String title;
  final int order;
  final List<StoryMemory> memories;

  const StoryChapter({
    required this.id,
    required this.title,
    required this.order,
    required this.memories,
  });
}

extension StorySourceTypeX on StorySourceType {
  String get displayName => switch (this) {
        StorySourceType.server => '自建服务器',
        StorySourceType.cos => 'COS / OSS',
        StorySourceType.github => 'GitHub',
        StorySourceType.gitee => 'Gitee',
      };

  String get description => switch (this) {
        StorySourceType.server => '支持搜索、标签和下载统计',
        StorySourceType.cos => '读取公共对象存储中的静态故事目录',
        StorySourceType.github => '读取公开仓库中的静态故事目录',
        StorySourceType.gitee => '读取公开仓库中的静态故事目录',
      };
}

class StorySourceConfig {
  final StorySourceType type;
  final String baseUrl;
  final String port;
  final String token;
  final String indexUrl;
  final String repository;
  final String branch;
  final String path;

  /// Object storage prefix, e.g. `stories`.
  final String storagePath;
  final String secretId;
  final String secretKey;

  const StorySourceConfig({
    this.type = StorySourceType.server,
    this.baseUrl = '',
    this.port = '',
    this.token = '',
    this.indexUrl = '',
    this.repository = '',
    this.branch = 'main',
    this.path = 'index.json',
    this.storagePath = '',
    this.secretId = '',
    this.secretKey = '',
  });

  StorySourceConfig copyWith({
    StorySourceType? type,
    String? baseUrl,
    String? port,
    String? token,
    String? indexUrl,
    String? repository,
    String? branch,
    String? path,
    String? storagePath,
    String? secretId,
    String? secretKey,
  }) {
    return StorySourceConfig(
      type: type ?? this.type,
      baseUrl: baseUrl ?? this.baseUrl,
      port: port ?? this.port,
      token: token ?? this.token,
      indexUrl: indexUrl ?? this.indexUrl,
      repository: repository ?? this.repository,
      branch: branch ?? this.branch,
      path: path ?? this.path,
      storagePath: storagePath ?? this.storagePath,
      secretId: secretId ?? this.secretId,
      secretKey: secretKey ?? this.secretKey,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'base_url': baseUrl,
        'port': port,
        'token': token,
        'index_url': indexUrl,
        'repository': repository,
        'branch': branch,
        'path': path,
        'storage_path': storagePath,
        'secret_id': secretId,
        'secret_key': secretKey,
      };

  factory StorySourceConfig.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String?;
    return StorySourceConfig(
      type: StorySourceType.values.firstWhere(
        (value) => value.name == typeName,
        orElse: () => StorySourceType.server,
      ),
      baseUrl: json['base_url'] as String? ?? '',
      port: json['port'] as String? ?? '',
      token: json['token'] as String? ?? '',
      indexUrl: json['index_url'] as String? ?? '',
      repository: json['repository'] as String? ?? '',
      branch: json['branch'] as String? ?? 'main',
      path: json['path'] as String? ?? 'index.json',
      storagePath: json['storage_path'] as String? ?? '',
      secretId: json['secret_id'] as String? ?? '',
      secretKey: json['secret_key'] as String? ?? '',
    );
  }
}

class StoryCatalogEntry {
  final String storyId;
  final int version;
  final String title;
  final String author;
  final String summary;
  final String publishedAt;
  final List<String> tags;
  final String file;
  final int? downloadCount;

  const StoryCatalogEntry({
    required this.storyId,
    required this.version,
    required this.title,
    required this.author,
    required this.summary,
    this.publishedAt = '',
    required this.tags,
    required this.file,
    this.downloadCount,
  });

  factory StoryCatalogEntry.fromJson(Map<String, dynamic> json) {
    return StoryCatalogEntry(
      storyId: (json['storyId'] ?? json['story_id'] ?? '').toString(),
      version: int.tryParse('${json['version'] ?? 1}') ?? 1,
      title: (json['title'] ?? '').toString(),
      author: (json['author'] ?? '').toString(),
      summary: (json['summary'] ?? '').toString(),
      publishedAt:
          (json['publishedAt'] ?? json['published_at'] ?? '').toString(),
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
      file: (json['file'] ?? '').toString(),
      downloadCount: json['downloadCount'] == null
          ? (json['download_count'] as num?)?.toInt()
          : (json['downloadCount'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'storyId': storyId,
        'version': version,
        'title': title,
        'author': author,
        'summary': summary,
        if (publishedAt.isNotEmpty) 'publishedAt': publishedAt,
        'tags': tags,
        'file': file,
        if (downloadCount != null) 'downloadCount': downloadCount,
      };
}

class StoryPackage {
  final String storyId;
  final int version;
  final String title;
  final String author;
  final String summary;
  final List<String> tags;
  final String publishedAt;
  final String introduction;
  final List<StoryMemory> memories;
  final List<String> images;
  final List<StoryChapter> chapters;

  StoryPackage({
    required this.storyId,
    required this.version,
    required this.title,
    required this.author,
    required this.summary,
    required this.tags,
    this.publishedAt = '',
    this.introduction = '',
    List<StoryMemory>? memories,
    List<StoryChapter> chapters = const [],
    this.images = const [],
  })  : memories = memories ??
            chapters
                .expand((chapter) => chapter.memories)
                .toList(growable: false),
        chapters = chapters;

  factory StoryPackage.fromJson(Map<String, dynamic> json) {
    final storyId =
        (json['storyId'] ?? json['story_id'] ?? '').toString().trim();
    final title = (json['title'] ?? '').toString().trim();
    if (storyId.isEmpty || title.isEmpty) {
      throw const FormatException('故事包缺少 storyId 或标题');
    }
    final rawMemories = json['memories'];
    final memoryTexts = rawMemories is List
        ? rawMemories
            .map((value) => value is Map
                ? (value['content'] ?? '').toString().trim()
                : value.toString().trim())
            .where((value) => value.isNotEmpty)
            .toList(growable: false)
        : _legacyMemories(json);
    final memoryPoints = [
      for (var i = 0; i < memoryTexts.length; i++)
        StoryMemory(id: 'memory_${i + 1}', order: i, content: memoryTexts[i]),
    ];
    return StoryPackage(
      storyId: storyId,
      version: int.tryParse('${json['version'] ?? 1}') ?? 1,
      title: title,
      author: (json['author'] ?? '').toString(),
      summary: (json['summary'] ?? '').toString(),
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      publishedAt:
          (json['publishedAt'] ?? json['published_at'] ?? '').toString(),
      introduction: (json['introduction'] ?? '').toString().trim(),
      memories: memoryPoints,
      images: (json['images'] as List<dynamic>? ?? const [])
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
    );
  }

  factory StoryPackage.fromText(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map) throw const FormatException('故事包 JSON 格式无效');
    return StoryPackage.fromJson(decoded.cast<String, dynamic>());
  }

  static List<String> _legacyMemories(Map<String, dynamic> json) {
    final chapters = json['chapters'];
    if (chapters is! List) return const [];
    return [
      for (final chapter in chapters.whereType<Map>())
        for (final memory in (chapter['memories'] as List? ?? const []))
          (memory is Map ? (memory['content'] ?? '') : memory)
              .toString()
              .trim(),
    ].where((value) => value.isNotEmpty).toList(growable: false);
  }

  Iterable<StoryMemory> get allMemories => memories;
}

class InstalledStory {
  final String storyId;
  final String title;
  final int version;
  final String characterId;

  const InstalledStory({
    required this.storyId,
    required this.title,
    required this.version,
    required this.characterId,
  });

  Map<String, dynamic> toJson() => {
        'story_id': storyId,
        'title': title,
        'version': version,
        'character_id': characterId,
      };

  factory InstalledStory.fromJson(Map<String, dynamic> json) => InstalledStory(
        storyId: (json['story_id'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        version: int.tryParse('${json['version'] ?? 1}') ?? 1,
        characterId: (json['character_id'] ?? '').toString(),
      );
}
