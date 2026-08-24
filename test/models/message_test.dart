import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat/models/message.dart';

void main() {
  test('sticker message serializes optional metadata and round trips', () {
    final original = Message(
      id: 'message-1',
      conversationId: 'conversation-1',
      content: '/stickers/custom/a.png',
      type: MessageType.sticker,
      sender: MessageSender.user,
      stickerLabel: '笑哭',
      stickerSource: 'local',
    );

    final restored = Message.fromJson(original.toJson());

    expect(restored.type, MessageType.sticker);
    expect(restored.stickerLabel, '笑哭');
    expect(restored.stickerSource, 'local');
    expect(restored.content, original.content);
  });

  test('old message JSON without sticker metadata remains compatible', () {
    final restored = Message.fromJson({
      'id': 'message-2',
      'conversation_id': 'conversation-1',
      'content': 'hello',
      'type': 'text',
      'sender': 'user',
      'created_at': '2026-08-23T10:00:00.000Z',
    });

    expect(restored.type, MessageType.text);
    expect(restored.stickerLabel, isNull);
    expect(restored.stickerSource, isNull);
  });
}
