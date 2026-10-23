import 'package:ai_chat/providers/chat_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ChatProvider seededChat() {
    SharedPreferences.setMockInitialValues({});
    final chat = ChatProvider();
    final conversation = chat.getOrCreateConversation(
      characterId: 'char-1',
      characterName: '角色',
    );
    chat.markConversationActive(conversation.id);
    chat.addProactiveMessage(conversation.id, '第一条');
    chat.addProactiveMessage(conversation.id, '第二条');
    chat.addProactiveMessage(conversation.id, '第三条');
    return chat;
  }

  test('deleteMessages removes only the selected messages', () async {
    final chat = seededChat();
    final conversationId = chat.conversations.single.id;
    final messages = chat.getMessages(conversationId);

    await chat.deleteMessages(
      conversationId,
      [messages[0].id, messages[2].id],
    );

    expect(
      chat.getMessages(conversationId).map((m) => m.content),
      ['第二条'],
    );
    expect(chat.conversations.single.lastMessage, '第二条');
    chat.dispose();
  });

  test('deleting every message clears the conversation preview', () async {
    final chat = seededChat();
    final conversationId = chat.conversations.single.id;
    final ids = chat.getMessages(conversationId).map((m) => m.id).toList();

    await chat.deleteMessages(conversationId, ids);

    expect(chat.getMessages(conversationId), isEmpty);
    expect(chat.conversations.single.lastMessage, isEmpty);
    chat.dispose();
  });

  test('deleteMessages ignores unknown ids', () async {
    final chat = seededChat();
    final conversationId = chat.conversations.single.id;

    await chat.deleteMessages(conversationId, ['missing-id']);

    expect(chat.getMessages(conversationId).length, 3);
    chat.dispose();
  });
}
