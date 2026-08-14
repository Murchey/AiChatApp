enum MessageType { text, image, file, system }

enum MessageSender { user, character }

/// 合并转发中的一条原始消息（用于点击卡片后展示原始对话）
class ForwardItem {
  final String senderName; // 发送者显示名（我 / 角色昵称）
  final bool isUser;
  final String content;
  final String type; // 'text' | 'image' | 'file'
  final DateTime createdAt;
  final String characterAvatar; // 源会话角色的头像（base64，转发时固化，防止在目标会话中显示错乱）

  const ForwardItem({
    required this.senderName,
    required this.isUser,
    required this.content,
    this.type = 'text',
    required this.createdAt,
    this.characterAvatar = '',
  });

  Map<String, dynamic> toJson() => {
        'sender_name': senderName,
        'is_user': isUser,
        'content': content,
        'type': type,
        'created_at': createdAt.toIso8601String(),
        'character_avatar': characterAvatar,
      };

  factory ForwardItem.fromJson(Map<String, dynamic> json) => ForwardItem(
        senderName: json['sender_name'] as String? ?? '',
        isUser: json['is_user'] as bool? ?? false,
        content: json['content'] as String? ?? '',
        type: json['type'] as String? ?? 'text',
        createdAt: DateTime.parse(json['created_at'] as String),
        characterAvatar: json['character_avatar'] as String? ?? '',
      );
}

class Message {
  final String id;
  final String conversationId;
  final String content;
  final MessageType type;
  final MessageSender sender;

  /// 群聊中该角色消息对应的角色 id（私聊/用户消息为空串）。
  /// 用于群聊气泡解析发送者头像/昵称与取对应模型。
  final String senderCharacterId;

  /// 群聊中角色消息的发送者显示名（私聊/用户消息为空串）。
  /// 群聊历史上下文需要知道每条角色消息是谁发的。
  final String senderName;
  final DateTime createdAt;
  final bool isRead;
  // 引用消息内容（可选）
  final String quoteContent;
  final String quoteSender;
  // 合并转发的原始消息列表（非空表示这是一条"聊天记录"卡片）
  final List<ForwardItem> forwardedItems;
  // 是否为会话压缩生成的摘要消息（压缩时不删除前文原文，仅用此标记定位上下文起点）
  final bool isCompressionSummary;

  Message({
    required this.id,
    required this.conversationId,
    required this.content,
    this.type = MessageType.text,
    required this.sender,
    this.senderCharacterId = '',
    this.senderName = '',
    DateTime? createdAt,
    this.isRead = false,
    this.quoteContent = '',
    this.quoteSender = '',
    this.forwardedItems = const [],
    this.isCompressionSummary = false,
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
      senderCharacterId: json['sender_character_id'] as String? ?? '',
      senderName: json['sender_name'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      isRead: json['is_read'] as bool? ?? false,
      quoteContent: json['quote_content'] as String? ?? '',
      quoteSender: json['quote_sender'] as String? ?? '',
      forwardedItems: (json['forwarded_items'] as List<dynamic>? ?? [])
          .map((e) => ForwardItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      isCompressionSummary:
          json['is_compression_summary'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'content': content,
      'type': type.name,
      'sender': sender.name,
      'sender_character_id': senderCharacterId,
      'sender_name': senderName,
      'created_at': createdAt.toIso8601String(),
      'is_read': isRead,
      'quote_content': quoteContent,
      'quote_sender': quoteSender,
      'forwarded_items': forwardedItems.map((e) => e.toJson()).toList(),
      'is_compression_summary': isCompressionSummary,
    };
  }
}
