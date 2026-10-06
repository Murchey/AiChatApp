/// 首页会话列表条目（私聊 / 群聊统一模型）。
class HomeChatEntry {
  final bool isGroup;
  final String id;
  final String title;
  final String avatar;
  final String lastMessage;
  final DateTime lastMessageTime;
  final bool pinned;
  final int unreadCount;

  const HomeChatEntry({
    required this.isGroup,
    required this.id,
    required this.title,
    required this.avatar,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.pinned,
    required this.unreadCount,
  });

  @override
  bool operator ==(Object other) {
    return other is HomeChatEntry &&
        other.isGroup == isGroup &&
        other.id == id &&
        other.title == title &&
        other.avatar == avatar &&
        other.lastMessage == lastMessage &&
        other.lastMessageTime == lastMessageTime &&
        other.pinned == pinned &&
        other.unreadCount == unreadCount;
  }

  @override
  int get hashCode => Object.hash(
        isGroup,
        id,
        title,
        avatar,
        lastMessage,
        lastMessageTime,
        pinned,
        unreadCount,
      );
}
