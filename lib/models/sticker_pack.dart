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

  const UserSticker({
    required this.id,
    required this.sha256,
    required this.imagePath,
    required this.label,
    required this.createdAt,
    this.useCount = 0,
  });

  factory UserSticker.fromJson(Map<String, dynamic> json) => UserSticker(
        id: json['id'] as String? ?? '',
        sha256: json['sha256'] as String? ?? json['id'] as String? ?? '',
        imagePath: json['image_path'] as String? ?? '',
        label: json['label'] as String? ?? '',
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.now(),
        useCount: (json['use_count'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sha256': sha256,
        'image_path': imagePath,
        'label': label,
        'created_at': createdAt.toIso8601String(),
        'use_count': useCount,
      };

  UserSticker copyWith({String? label, int? useCount}) => UserSticker(
        id: id,
        sha256: sha256,
        imagePath: imagePath,
        label: label ?? this.label,
        createdAt: createdAt,
        useCount: useCount ?? this.useCount,
      );
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
