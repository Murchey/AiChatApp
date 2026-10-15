import 'package:ai_chat/providers/chat_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('send signals local insertion before history persistence finishes',
      () async {
    SharedPreferences.setMockInitialValues({});
    final provider = ChatProvider();
    var completed = false;
    var added = false;
    final sending = provider
        .sendMessage(
            conversationId: 'a',
            content: '中文\n消息',
            onLocalMessageAdded: () {
              added = true;
              expect(provider.getMessages('a').single.content, '中文\n消息');
              expect(completed, false);
            })
        .then((_) {
      completed = true;
    });
    expect(added, true);
    expect(completed, false);
    // No SQLite is configured in this unit test: failure must propagate after
    // local acceptance so the input can restore its draft.
    await expectLater(sending, throwsStateError);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('chat_messages_v1'), contains('中文'));
    expect(completed, false);
    provider.dispose();
  });
}
