import 'package:flutter_test/flutter_test.dart';

import 'package:ai_chat/models/message.dart';
import 'package:ai_chat/screens/chat/chat_proactive_reply.dart';

Message _message({
  required String id,
  required String content,
  MessageType type = MessageType.text,
  MessageSender sender = MessageSender.user,
  String? stickerLabel,
}) {
  return Message(
    id: id,
    conversationId: 'conversation',
    content: content,
    type: type,
    sender: sender,
    stickerLabel: stickerLabel,
  );
}

void main() {
  test('uses latest persisted user image after the screen is recreated', () {
    final result = ChatProactiveReply.resolveReplyImage(
      messages: [
        _message(id: 'old', content: r'C:old.png', type: MessageType.image),
        _message(
            id: 'reply',
            content: 'previous reply',
            sender: MessageSender.character),
        _message(
            id: 'latest', content: r'C:latest.png', type: MessageType.image),
      ],
      replyToUser: true,
    );

    expect(result.imagePath, r'C:latest.png');
    expect(result.stickerLabel, isNull);
  });

  test('keeps image when later text belongs to same unanswered turn', () {
    final result = ChatProactiveReply.resolveReplyImage(
      messages: [
        _message(id: 'image', content: r'C:old.png', type: MessageType.image),
        _message(id: 'text', content: 'what is in this picture?'),
      ],
      replyToUser: true,
      requestedImagePath: r'C:stale.png',
    );

    expect(result.imagePath, r'C:old.png');
    expect(result.stickerLabel, isNull);
  });

  test('does not reuse an image once an assistant reply exists', () {
    final result = ChatProactiveReply.resolveReplyImage(
      messages: [
        _message(id: 'image', content: r'C:old.png', type: MessageType.image),
        _message(
          id: 'reply',
          content: 'answered image',
          sender: MessageSender.character,
        ),
      ],
      replyToUser: true,
      requestedImagePath: r'C:old.png',
    );

    expect(result.imagePath, isNull);
    expect(result.stickerLabel, isNull);
  });

  test('text after an assistant reply does not recover the answered image', () {
    final result = ChatProactiveReply.resolveReplyImage(
      messages: [
        _message(id: 'image', content: r'C:old.png', type: MessageType.image),
        _message(
          id: 'reply',
          content: 'answered image',
          sender: MessageSender.character,
        ),
        _message(id: 'new-text', content: 'new question'),
      ],
      replyToUser: true,
      requestedImagePath: r'C:old.png',
    );

    expect(result.imagePath, isNull);
    expect(result.stickerLabel, isNull);
  });

  test('selects latest attachment within unanswered turn and keeps its label',
      () {
    final result = ChatProactiveReply.resolveReplyImage(
      messages: [
        _message(id: 'image', content: r'C:old.png', type: MessageType.image),
        _message(
          id: 'sticker',
          content: r'C:sticker.webp',
          type: MessageType.sticker,
          stickerLabel: '开心',
        ),
        _message(id: 'text', content: 'same turn'),
      ],
      replyToUser: true,
    );

    expect(result.imagePath, r'C:sticker.webp');
    expect(result.stickerLabel, '开心');
  });

  test('file-only unanswered turn has no visual attachment', () {
    final result = ChatProactiveReply.resolveReplyImage(
      messages: [
        _message(id: 'file', content: r'C:report.pdf', type: MessageType.file),
      ],
      replyToUser: true,
      requestedImagePath: r'C:stale.png',
    );

    expect(result.imagePath, isNull);
    expect(result.stickerLabel, isNull);
  });

  test('restores the latest sticker path and label', () {
    final result = ChatProactiveReply.resolveReplyImage(
      messages: [
        _message(
          id: 'sticker',
          content: r'C:sticker.webp',
          type: MessageType.sticker,
          stickerLabel: '开心',
        ),
      ],
      replyToUser: true,
    );

    expect(result.imagePath, r'C:sticker.webp');
    expect(result.stickerLabel, '开心');
  });

  test('keeps explicit path for non-user-targeted proactive replies', () {
    final result = ChatProactiveReply.resolveReplyImage(
      messages: const [],
      replyToUser: false,
      requestedImagePath: r'C:explicit.png',
      requestedStickerLabel: '标签',
    );

    expect(result.imagePath, r'C:explicit.png');
    expect(result.stickerLabel, '标签');
  });
}
