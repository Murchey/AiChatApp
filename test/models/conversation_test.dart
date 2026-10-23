import 'package:ai_chat/models/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hidden state survives a JSON round trip', () {
    final conversation = Conversation(
      id: 'conv-1',
      characterId: 'char-1',
      characterName: '角色',
      hidden: true,
    );
    final restored = Conversation.fromJson(conversation.toJson());
    expect(restored.hidden, isTrue);
  });

  test('legacy conversation JSON has no hidden state', () {
    final restored = Conversation.fromJson({
      'id': 'conv-1',
      'character_id': 'char-1',
      'character_name': '角色',
    });
    expect(restored.hidden, isFalse);
  });

  test('copyWith can clear the hidden state', () {
    final conversation = Conversation(
      id: 'conv-1',
      characterId: 'char-1',
      characterName: '角色',
      hidden: true,
    );
    expect(conversation.copyWith(hidden: false).hidden, isFalse);
    expect(conversation.copyWith().hidden, isTrue);
  });
}
