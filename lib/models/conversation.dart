class Conversation {
  final String id;
  final String characterId;
  final String characterName;
  final String characterAvatar;
  final String lastMessage;
  final DateTime lastMessageTime;
  final int unreadCount;

  Conversation({
    required this.id,
    required this.characterId,
    required this.characterName,
    this.characterAvatar = '',
    this.lastMessage = '',
    DateTime? lastMessageTime,
    this.unreadCount = 0,
  }) : lastMessageTime = lastMessageTime ?? DateTime.now();

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] as String,
      characterId: json['character_id'] as String,
      characterName: json['character_name'] as String,
      characterAvatar: json['character_avatar'] as String? ?? '',
      lastMessage: json['last_message'] as String? ?? '',
      lastMessageTime: json['last_message_time'] != null
          ? DateTime.parse(json['last_message_time'] as String)
          : DateTime.now(),
      unreadCount: json['unread_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'character_id': characterId,
      'character_name': characterName,
      'character_avatar': characterAvatar,
      'last_message': lastMessage,
      'last_message_time': lastMessageTime.toIso8601String(),
      'unread_count': unreadCount,
    };
  }

  Conversation copyWith({
    String? characterId,
    String? characterName,
    String? characterAvatar,
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCount,
  }) {
    return Conversation(
      id: id,
      characterId: characterId ?? this.characterId,
      characterName: characterName ?? this.characterName,
      characterAvatar: characterAvatar ?? this.characterAvatar,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}
