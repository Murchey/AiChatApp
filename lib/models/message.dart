enum MessageType { text, image, system }

enum MessageSender { user, character }

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
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isFromUser => sender == MessageSender.user;

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
    };
  }
}
