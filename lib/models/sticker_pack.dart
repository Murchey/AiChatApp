/// 从创意工坊导入的表情包合集。
class StickerPack {
  final String id;
  final String name;
  final String author;
  final String coverImagePath;
  final List<String> imagePaths;
  final DateTime importedAt;
  final int version;
  final Map<int, String> labels;

  const StickerPack({
    required this.id,
    required this.name,
    required this.author,
    required this.coverImagePath,
    required this.imagePaths,
    required this.importedAt,
    this.version = 1,
    this.labels = const {},
  });

  factory StickerPack.fromJson(Map<String, dynamic> json) => StickerPack(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        author: json['author'] as String? ?? '',
        coverImagePath: json['cover_image_path'] as String? ?? '',
        imagePaths: (json['image_paths'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        importedAt: DateTime.tryParse(json['imported_at'] as String? ?? '') ??
            DateTime.now(),
        version: (json['version'] as num?)?.toInt() ?? 1,
        labels: _decodeLabels(json['labels']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'author': author,
        'cover_image_path': coverImagePath,
        'image_paths': imagePaths,
        'imported_at': importedAt.toIso8601String(),
        'version': version,
        'labels': labels.map((key, value) => MapEntry(key.toString(), value)),
      };

  StickerPack copyWith({
    String? name,
    String? author,
    String? coverImagePath,
    List<String>? imagePaths,
    DateTime? importedAt,
    int? version,
    Map<int, String>? labels,
  }) =>
      StickerPack(
        id: id,
        name: name ?? this.name,
        author: author ?? this.author,
        coverImagePath: coverImagePath ?? this.coverImagePath,
        imagePaths: imagePaths ?? this.imagePaths,
        importedAt: importedAt ?? this.importedAt,
        version: version ?? this.version,
        labels: labels ?? this.labels,
      );

  static Map<int, String> _decodeLabels(dynamic raw) {
    if (raw is! Map) return {};
    return raw.map((key, value) => MapEntry(
          int.tryParse(key.toString()) ?? 0,
          value.toString(),
        ));
  }
}

/// 用户收藏的单个表情包。sha256 保存完整哈希，id 用于稳定引用。
class UserSticker {
  final String id;
  final String sha256;
  final String imagePath;
  final String label;
  final DateTime createdAt;
  final int useCount;

  /// 用于本地语义检索的图片含义描述，可由用户在管理页维护。
  final String description;

  /// 用于快速召回的关键词，例如“无语、熊猫头、吐槽”。
  final List<String> keywords;

  /// 情绪标签，例如“开心、无奈、撒娇”。
  final List<String> emotionTags;

  const UserSticker({
    required this.id,
    required this.sha256,
    required this.imagePath,
    required this.label,
    required this.createdAt,
    this.useCount = 0,
    this.description = '',
    this.keywords = const [],
    this.emotionTags = const [],
  });

  factory UserSticker.fromJson(Map<String, dynamic> json) => UserSticker(
        id: json['id'] as String? ?? '',
        sha256: json['sha256'] as String? ?? json['id'] as String? ?? '',
        imagePath: json['image_path'] as String? ?? '',
        label: json['label'] as String? ?? '',
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.now(),
        useCount: (json['use_count'] as num?)?.toInt() ?? 0,
        description: json['description'] as String? ?? '',
        keywords: _decodeStringList(json['keywords']),
        emotionTags: _decodeStringList(json['emotion_tags']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sha256': sha256,
        'image_path': imagePath,
        'label': label,
        'created_at': createdAt.toIso8601String(),
        'use_count': useCount,
        'description': description,
        'keywords': keywords,
        'emotion_tags': emotionTags,
      };

  UserSticker copyWith({
    String? label,
    int? useCount,
    String? description,
    List<String>? keywords,
    List<String>? emotionTags,
  }) =>
      UserSticker(
        id: id,
        sha256: sha256,
        imagePath: imagePath,
        label: label ?? this.label,
        createdAt: createdAt,
        useCount: useCount ?? this.useCount,
        description: description ?? this.description,
        keywords: keywords ?? this.keywords,
        emotionTags: emotionTags ?? this.emotionTags,
      );

  static List<String> _decodeStringList(dynamic raw) => raw is List
      ? raw
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList()
      : const [];
}

/// 扁平化后的选择器条目。
class StickerEntry {
  final String imagePath;
  final String? label;
  final String? stickerId;
  final String? packId;
  final String? source;

  const StickerEntry({
    required this.imagePath,
    this.label,
    this.stickerId,
    this.packId,
    this.source,
  });
}

/// 视觉模型自动打标结果：画面描述 + 检索关键词 + 情绪标签。
class StickerAutoTags {
  final String description;
  final List<String> keywords;
  final List<String> emotionTags;

  const StickerAutoTags({
    this.description = '',
    this.keywords = const [],
    this.emotionTags = const [],
  });
}
