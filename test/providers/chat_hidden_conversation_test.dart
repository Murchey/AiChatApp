import 'package:ai_chat/providers/chat_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('hiding a conversation keeps its messages and returns on new message',
      () async {
    SharedPreferences.setMockInitialValues({});
    final chat = ChatProvider();
    final conversation = chat.getOrCreateConversation(
      characterId: 'char-1',
      characterName: '角色',
    );
    // 打开中会话不触发系统通知（测试环境无通知插件）
    chat.markConversationActive(conversation.id);
    chat.addProactiveMessage(conversation.id, '历史消息');

    await chat.hideConversation(conversation.id);

    final hidden =
        chat.conversations.firstWhere((c) => c.id == conversation.id);
    expect(hidden.hidden, isTrue);
    // 删除会话只隐藏首页列表，聊天记录必须保留
    expect(chat.getMessages(conversation.id).single.content, '历史消息');

    // 收到新消息后自动回到首页
    chat.addProactiveMessage(conversation.id, '新消息');
    final visible =
        chat.conversations.firstWhere((c) => c.id == conversation.id);
    expect(visible.hidden, isFalse);
    expect(chat.getMessages(conversation.id).length, 2);
    chat.dispose();
  });
}
