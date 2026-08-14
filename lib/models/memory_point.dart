import 'package:uuid/uuid.dart';

/// 角色的持久化记忆点：用户从聊天中挑选的、需要模型在后续对话中长期记住的关键信息。
///
/// 每个记忆点按角色独立存储，生成系统提示词时统一追加在角色基础提示词之后。
class MemoryPoint {
  final String id;
  final String content;
  final DateTime createdAt;

  MemoryPoint({
    String? id,
    required this.content,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  factory MemoryPoint.fromJson(Map<String, dynamic> json) {
    return MemoryPoint(
      id: json['id'] as String? ?? const Uuid().v4(),
      content: json['content'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'created_at': createdAt.toIso8601String(),
      };

  MemoryPoint copyWith({String? content, DateTime? createdAt}) => MemoryPoint(
        id: id,
        content: content ?? this.content,
        createdAt: createdAt ?? this.createdAt,
      );
}
