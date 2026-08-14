/// 朋友圈互动通知：某角色给某条动态点了赞 / 评论了什么，
/// 或回复了用户在该动态下的评论。
///
/// 由朋友圈 AI 互动引擎在每次角色互动成功后写入，
/// 通过朋友圈左上角铃铛进入通知页查看（无需点击内容跳转）。
class MomentNotification {
  final String id;
  final String characterId; // 互动角色 id
  final String characterName; // 互动角色显示名（昵称/备注）
  final String momentId; // 被互动的动态 id
  final String momentContent; // 动态内容摘要（通知页展示）
  final bool liked; // 是否点赞
  final String comment; // 评论/回复内容（空串表示未评论）
  final bool isReply; // 是否「回复了你的评论」（角色回复用户评论）
  final DateTime createdAt; // 互动时间
  final bool read; // 是否已读（打开通知页后标记）

  const MomentNotification({
    required this.id,
    required this.characterId,
    required this.characterName,
    required this.momentId,
    this.momentContent = '',
    this.liked = false,
    this.comment = '',
    this.isReply = false,
    required this.createdAt,
    this.read = false,
  });

  factory MomentNotification.fromJson(Map<String, dynamic> json) {
    return MomentNotification(
      id: json['id'] as String? ?? '',
      characterId: json['character_id'] as String? ?? '',
      characterName: json['character_name'] as String? ?? '',
      momentId: json['moment_id'] as String? ?? '',
      momentContent: json['moment_content'] as String? ?? '',
      liked: json['liked'] as bool? ?? false,
      comment: json['comment'] as String? ?? '',
      isReply: json['is_reply'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      read: json['read'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'character_id': characterId,
        'character_name': characterName,
        'moment_id': momentId,
        'moment_content': momentContent,
        'liked': liked,
        'comment': comment,
        'is_reply': isReply,
        'created_at': createdAt.toIso8601String(),
        'read': read,
      };

  MomentNotification copyWith({
    String? characterName,
    String? momentContent,
    bool? liked,
    String? comment,
    bool? isReply,
    bool? read,
  }) {
    return MomentNotification(
      id: id,
      characterId: characterId,
      characterName: characterName ?? this.characterName,
      momentId: momentId,
      momentContent: momentContent ?? this.momentContent,
      liked: liked ?? this.liked,
      comment: comment ?? this.comment,
      isReply: isReply ?? this.isReply,
      createdAt: createdAt,
      read: read ?? this.read,
    );
  }
}
