import 'package:uuid/uuid.dart';

/// 角色的持久化记忆点：用户从聊天中挑选的、需要模型在后续对话中长期记住的关键信息。
///
/// 每个记忆点按角色独立存储，生成系统提示词时统一追加在角色基础提示词之后。
class MemoryPoint {
  final String id;
  final String content;
  final DateTime createdAt;

  /// 非空时表示该记忆来自故事线社区；普通用户记忆保持为空。
  final String? sourceType;
  final String? sourceId;
  final int? sourceVersion;
  final String? sourceTitle;
  final String? chapterId;

  MemoryPoint({
    String? id,
    required this.content,
    DateTime? createdAt,
    this.sourceType,
    this.sourceId,
    this.sourceVersion,
    this.sourceTitle,
    this.chapterId,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  factory MemoryPoint.fromJson(Map<String, dynamic> json) {
    return MemoryPoint(
      id: json['id'] as String? ?? const Uuid().v4(),
      content: json['content'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      sourceType:
          json['source_type'] as String? ?? json['sourceType'] as String?,
      sourceId: json['source_id'] as String? ?? json['sourceId'] as String?,
      sourceVersion: (json['source_version'] ?? json['sourceVersion']) is num
          ? ((json['source_version'] ?? json['sourceVersion']) as num).toInt()
          : null,
      sourceTitle:
          json['source_title'] as String? ?? json['sourceTitle'] as String?,
      chapterId: json['chapter_id'] as String? ?? json['chapterId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'created_at': createdAt.toIso8601String(),
        if (sourceType != null) 'source_type': sourceType,
        if (sourceId != null) 'source_id': sourceId,
        if (sourceVersion != null) 'source_version': sourceVersion,
        if (sourceTitle != null) 'source_title': sourceTitle,
        if (chapterId != null) 'chapter_id': chapterId,
      };

  static const _unset = Object();

  MemoryPoint copyWith({
    String? content,
    DateTime? createdAt,
    Object? sourceType = _unset,
    Object? sourceId = _unset,
    Object? sourceVersion = _unset,
    Object? sourceTitle = _unset,
    Object? chapterId = _unset,
  }) =>
      MemoryPoint(
        id: id,
        content: content ?? this.content,
        createdAt: createdAt ?? this.createdAt,
        sourceType: identical(sourceType, _unset)
            ? this.sourceType
            : sourceType as String?,
        sourceId:
            identical(sourceId, _unset) ? this.sourceId : sourceId as String?,
        sourceVersion: identical(sourceVersion, _unset)
            ? this.sourceVersion
            : sourceVersion as int?,
        sourceTitle: identical(sourceTitle, _unset)
            ? this.sourceTitle
            : sourceTitle as String?,
        chapterId: identical(chapterId, _unset)
            ? this.chapterId
            : chapterId as String?,
      );
}
