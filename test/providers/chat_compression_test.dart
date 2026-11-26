import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_chat/models/message.dart';
import 'package:ai_chat/providers/api_provider.dart';
import 'package:ai_chat/providers/chat_compress.dart';
import 'package:ai_chat/providers/chat_history_builder.dart';
import 'package:ai_chat/providers/chat_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Message message(String id, String content,
        {bool summary = false, MessageType type = MessageType.text}) =>
    Message(
      id: id,
      conversationId: 'conversation',
      content: content,
      sender: summary ? MessageSender.character : MessageSender.user,
      type: type,
      isCompressionSummary: summary,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    final previous = HttpOverrides.current;
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    addTearDown(() => HttpOverrides.global = previous);
  });

  test('history includes latest nonempty summary and recent visible entries',
      () {
    final history = buildChatHistory([
      message('old', 'old'),
      message('s1', 'first', summary: true),
      message('s2', 'second', summary: true),
      message('empty', ' ', summary: true),
      message('image', '/local/image', type: MessageType.image),
      message('recent', 'recent'),
    ], 1, describe: describeMessageForModel);
    expect(history, [
      {'role': 'assistant', 'content': 'second'},
      {'role': 'user', 'content': 'recent'},
    ]);
  });

  test('edit and delete invalidate dependent summaries only', () async {
    final chat = ChatProvider();
    final conversation =
        chat.getOrCreateConversation(characterId: 'c', characterName: 'c');
    await chat.importMessages(conversationId: conversation.id, messages: [
      message('a', 'a'),
      message('s1', 'first', summary: true),
      message('b', 'b'),
      message('s2', 'second', summary: true),
      message('c', 'c'),
    ]);
    await chat.editMessage(
        conversationId: conversation.id, messageId: 'b', content: 'edited');
    expect(chat.getMessages(conversation.id).map((m) => m.id),
        ['a', 's1', 'b', 'c']);
    chat.deleteMessage(conversation.id, 'a');
    expect(chat.getMessages(conversation.id).map((m) => m.id), ['b', 'c']);
  });

  test('history mutations cancel automatic memory work', () async {
    final chat = ChatProvider();
    final cancelled = <String>[];
    var cancelledAll = 0;
    chat.autoMemoryCancel = cancelled.add;
    chat.autoMemoryCancelAll = () => cancelledAll++;
    final conversation =
        chat.getOrCreateConversation(characterId: 'c', characterName: 'c');
    await chat.importMessages(conversationId: conversation.id, messages: [
      message('a', 'a'),
      message('b', 'b'),
      message('c', 'c'),
    ]);

    await chat.editMessage(
        conversationId: conversation.id, messageId: 'a', content: 'edited');
    chat.deleteMessage(conversation.id, 'b');
    await chat.deleteMessages(conversation.id, ['c']);
    await chat.importMessages(
        conversationId: conversation.id, messages: [message('d', 'd')]);
    chat.withdrawMessage(conversation.id, 'd');
    expect(cancelled, List.filled(4, conversation.id));
    chat.dispose();
  });

  test('compression rejects stale prefix and rolls back persistence failure',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requests = StreamController<Completer<String>>();
    addTearDown(requests.close);
    server.listen((request) async {
      await request.drain<void>();
      final response = Completer<String>();
      requests.add(response);
      final content = await response.future;
      request.response.write(jsonEncode({
        'choices': [
          {
            'message': {'content': content}
          }
        ]
      }));
      await request.response.close();
    });
    final iterator = StreamIterator(requests.stream);
    addTearDown(iterator.cancel);
    final model = ApiModel(
        id: 'test',
        displayName: 'test',
        modelName: 'test',
        apiKey: 'key',
        baseUrl: 'http://127.0.0.1:${server.port}');
    final current = [for (var i = 0; i < 8; i++) message('m$i', 'message $i')];
    var failPersist = false;
    Object? error;
    final hooks = ChatCompressHooks(
      getMessages: (_) => current,
      insertMessage: (_, value, index) => current.insert(index, value),
      removeMessage: (_, id) => current.removeWhere((m) => m.id == id),
      onError: (value) => error = value,
      setContextTokens: (_, __) {},
      updateLastMessage: (_, __) {},
      notify: () {},
      persist: () async {
        if (failPersist) throw StateError('disk failure');
      },
      estimateInputBudget: (_, __, {int systemTokens = 0}) => 10000,
    );
    Future<bool> compress() => maybeCompressConversationWithHooks(
          hooks: hooks,
          conversationId: 'conversation',
          compressModel: model,
          contextLength: 10000,
          threshold: 0.5,
          force: true,
        );
    final stale = compress();
    expect(await iterator.moveNext(), isTrue);
    current[0] = current[0].copyWith(content: 'edited');
    iterator.current.complete('summary');
    expect(await stale, isFalse);
    expect(current.where((m) => m.isCompressionSummary), isEmpty);

    failPersist = true;
    final failed = compress();
    expect(await iterator.moveNext(), isTrue);
    iterator.current.complete('summary');
    expect(await failed, isFalse);
    expect(error, isA<StateError>());
    expect(current.where((m) => m.isCompressionSummary), isEmpty);
  });
}
