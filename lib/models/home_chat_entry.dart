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
}
