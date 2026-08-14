/// 群聊。
///
/// [memberCharacterIds] 为群内的角色成员 id（不含用户，用户恒为群成员）。
/// 群人数展示 = memberCharacterIds.length + 1（含用户）。
/// [avatar] 为空时由展示层按成员头像拼图/默认图标渲染。
class GroupChat {
  final String id;
  final String name;

  /// 群头像（base64，空表示未设置，展示层回退到成员拼图/默认图标）
  final String avatar;

  /// 群简介（进入模型请求上下文，角色会按简介语境对话）
  final String description;

  /// 群聊上下文条数：null=跟随全局聊天设置；0=无限制；>0=携带最近 N 条。
  final int? contextCount;
  final List<String> memberCharacterIds;
  final String lastMessage;
  final DateTime lastMessageTime;
  final bool pinned;
  final DateTime createdAt;

  GroupChat({
    required this.id,
    required this.name,
    this.avatar = '',
    this.description = '',
    this.contextCount,
    this.memberCharacterIds = const [],
    this.lastMessage = '',
    DateTime? lastMessageTime,
    this.pinned = false,
    DateTime? createdAt,
  })  : lastMessageTime = lastMessageTime ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  /// 群人数（含用户）
  int get memberCount => memberCharacterIds.length + 1;

  factory GroupChat.fromJson(Map<String, dynamic> json) {
    return GroupChat(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      avatar: json['avatar'] as String? ?? '',
      description: json['description'] as String? ?? '',
      contextCount: json['context_count'] as int?,
      memberCharacterIds:
          (json['member_character_ids'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList(),
      lastMessage: json['last_message'] as String? ?? '',
      lastMessageTime: json['last_message_time'] != null
          ? DateTime.parse(json['last_message_time'] as String)
          : DateTime.now(),
      pinned: json['pinned'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'avatar': avatar,
      'description': description,
      'context_count': contextCount,
      'member_character_ids': memberCharacterIds,
      'last_message': lastMessage,
      'last_message_time': lastMessageTime.toIso8601String(),
      'pinned': pinned,
      'created_at': createdAt.toIso8601String(),
    };
  }

  GroupChat copyWith({
    String? name,
    String? avatar,
    String? description,
    int? contextCount,
    List<String>? memberCharacterIds,
    String? lastMessage,
    DateTime? lastMessageTime,
    bool? pinned,
  }) {
    return GroupChat(
      id: id,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      description: description ?? this.description,
      contextCount: contextCount ?? this.contextCount,
      memberCharacterIds: memberCharacterIds ?? this.memberCharacterIds,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      pinned: pinned ?? this.pinned,
      createdAt: createdAt,
    );
  }
}
