enum MessageType { text, image, file, system }

enum MessageSender { user, character }

/// 合并转发中的一条原始消息（用于点击卡片后展示原始对话）
class ForwardItem {
  final String senderName; // 发送者显示名（我 / 角色昵称）
  final bool isUser;
  final String content;
  final String type; // 'text' | 'image' | 'file'
  final DateTime createdAt;

  const ForwardItem({
    required this.senderName,
    required this.isUser,
    required this.content,
    this.type = 'text',
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'sender_name': senderName,
        'is_user': isUser,
        'content': content,
        'type': type,
        'created_at': createdAt.toIso8601String(),
      };

  factory ForwardItem.fromJson(Map<String, dynamic> json) => ForwardItem(
        senderName: json['sender_name'] as String? ?? '',
        isUser: json['is_user'] as bool? ?? false,
        content: json['content'] as String? ?? '',
        type: json['type'] as String? ?? 'text',
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class Message {
  final String id;
  final String conversationId;
  final String content;
  final MessageType type;
  final MessageSender sender;
  final DateTime createdAt;
  final bool isRead;
  // 引用消息内容（可选）
  final String quoteContent;
  final String quoteSender;
  // 合并转发的原始消息列表（非空表示这是一条"聊天记录"卡片）
  final List<ForwardItem> forwardedItems;

  Message({
    required this.id,
    required this.conversationId,
    required this.content,
    this.type = MessageType.text,
    required this.sender,
    DateTime? createdAt,
    this.isRead = false,
    this.quoteContent = '',
    this.quoteSender = '',
    this.forwardedItems = const [],
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isFromUser => sender == MessageSender.user;

  bool get isForwardCard => forwardedItems.isNotEmpty;

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      content: json['content'] as String,
      type: MessageType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => MessageType.text,
      ),
      sender: MessageSender.values.firstWhere(
        (e) => e.name == json['sender'],
        orElse: () => MessageSender.user,
      ),
      createdAt: DateTime.parse(json['created_at'] as String),
      isRead: json['is_read'] as bool? ?? false,
      quoteContent: json['quote_content'] as String? ?? '',
      quoteSender: json['quote_sender'] as String? ?? '',
      forwardedItems: (json['forwarded_items'] as List<dynamic>? ?? [])
          .map((e) => ForwardItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'content': content,
      'type': type.name,
      'sender': sender.name,
      'created_at': createdAt.toIso8601String(),
      'is_read': isRead,
      'quote_content': quoteContent,
      'quote_sender': quoteSender,
      'forwarded_items': forwardedItems.map((e) => e.toJson()).toList(),
    };
  }
}
