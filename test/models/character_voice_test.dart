import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat/models/character.dart';

void main() {
  test('character voice card round trips through JSON', () {
    final character = Character(
      id: 'c1',
      name: '爱弥斯',
      voiceId: 'Cherry',
      voiceInstructions: '温柔、明亮',
    );
    final restored = Character.fromJson(character.toJson());
    expect(restored.voiceId, 'Cherry');
    expect(restored.voiceInstructions, '温柔、明亮');
  });

  test('legacy character without voice remains compatible', () {
    final character = Character.fromJson({'id': 'c1', 'name': '角色'});
    expect(character.voiceId, isEmpty);
    expect(character.voiceInstructions, isEmpty);
  });
}
