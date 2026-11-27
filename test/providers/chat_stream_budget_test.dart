import 'dart:convert';
import 'dart:io';

import 'package:ai_chat/models/message.dart';
import 'package:ai_chat/providers/api_provider.dart';
import 'package:ai_chat/providers/chat_roleplay_stream.dart';
import 'package:ai_chat/providers/chat_token_estimator.dart';
import 'package:ai_chat/providers/token_usage_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StreamHarness {
  final List<Message> history;
  final appended = <Message>[];
  final replaced = <Message>[];
  final removed = <String>[];
  final errors = <String?>[];
  var clearReplyingCalls = 0;

  StreamHarness({this.history = const []});

  ChatStreamHooks get hooks => ChatStreamHooks(
        getMessages: (_) => history,
        appendMessage: (_, message) => appended.add(message),
        replaceMessage: (_, __, message) => replaced.add(message),
        removeMessage: (_, messageId) => removed.add(messageId),
        notify: () {},
        persist: () async {},
        setSystemTokens: (_, __) {},
        setContextTokens: (_, __) {},
        setLastError: errors.add,
        clearReplying: () => clearReplyingCalls++,
        estimateTokens: ChatTokenEstimator.estimateText,
        estimateInputBudget: (_, __, {systemTokens = 0}) => 17,
        conversationAvatar: (_) => '',
        setRoleplayChoices: (_, __) async {},
        updateLastMessage: (_, __) {},
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  late String streamMode;
  late List<Map<String, dynamic>> requests;
  late int usageUpdates;

  setUp(() async {
    final previous = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previous);
    SharedPreferences.setMockInitialValues({});
    await TokenUsageProvider.instance.reload();
    usageUpdates = 0;
    void countUsageUpdate() => usageUpdates++;
    TokenUsageProvider.instance.addListener(countUsageUpdate);
    addTearDown(
        () => TokenUsageProvider.instance.removeListener(countUsageUpdate));
    requests = [];
    streamMode = 'success';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      requests.add(jsonDecode(body) as Map<String, dynamic>);
      request.response.headers.contentType =
          ContentType('text', 'event-stream', charset: 'utf-8');
      request.response.write('data: ${jsonEncode({
            'choices': [
              {
                'delta': {'content': 'reply'}
              }
            ],
            'usage': {'prompt_tokens': 7, 'completion_tokens': 1}
          })}\n\n');
      request.response.write('data: ${jsonEncode({
            'choices': [],
            'usage': {
              'prompt_tokens': 11,
              'completion_tokens': 3,
              'total_tokens': 14,
            }
          })}\n\n');
      if (streamMode == 'error') {
        request.response.write('data: ${jsonEncode({
              'error': {'message': 'server failed'}
            })}\n\n');
      } else {
        request.response.write('data: [DONE]\n\n');
      }
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
  });

  ApiModel model({int contextLength = 16000}) => ApiModel(
        id: 'test',
        displayName: 'test',
        modelName: 'test',
        apiKey: 'test-key',
        contextLength: contextLength,
        baseUrl: 'http://127.0.0.1:${server.port}',
      );

  Future<List<String>> run(StreamHarness harness, ApiModel selected) =>
      runRoleplayStreamWithHooks(
        hooks: harness.hooks,
        conversationId: 'conversation',
        model: selected,
        characterName: 'Character',
        characterSystemPrompt: 'Reply as Character',
        userRelationship: '',
        userNickname: 'User',
        memoryPoints: const [],
        contextCount: 20,
        progressionStyle: '',
        includeChoices: false,
      );

  test('budget overflow sends no HTTP and clears replying without placeholder',
      () async {
    final harness = StreamHarness(history: [
      Message(
        id: 'old',
        conversationId: 'conversation',
        content: List.filled(20000, '中').join(),
        sender: MessageSender.user,
      ),
    ]);

    final result = await run(harness, model(contextLength: 1500));

    expect(result, isEmpty);
    expect(requests, isEmpty);
    expect(harness.appended, isEmpty);
    expect(harness.replaced, isEmpty);
    expect(harness.removed, isEmpty);
    expect(harness.errors, [null, contains('聊天上下文超限')]);
    expect(harness.clearReplyingCalls, 1);
    expect(harness.history, hasLength(1));
    expect(harness.history.single.id, 'old');
    expect(harness.history.single.content, List.filled(20000, '中').join());
    expect(usageUpdates, 0);
    expect(TokenUsageProvider.instance.allUsages, isEmpty);
  });

  test('usage received before stream error is recorded exactly once', () async {
    streamMode = 'error';
    final harness = StreamHarness();

    final result = await run(harness, model());

    expect(result, isEmpty);
    expect(requests, hasLength(1));
    expect(requests.single['stream'], isTrue);
    expect(harness.errors, [null, contains('server failed')]);
    expect(harness.appended, hasLength(1));
    expect(harness.removed, [harness.appended.single.id]);
    expect(harness.replaced.first.content, 'reply');
    expect(harness.clearReplyingCalls, 1);
    final usage = TokenUsageProvider.instance.usageFor('conversation');
    expect(usage.sentTokens, 11);
    expect(usage.receivedTokens, 3);
    expect(usage.totalTokens, 14);
    expect(usage.label, 'Character');
    expect(usageUpdates, 1);
    final prefs = await SharedPreferences.getInstance();
    final stored = jsonDecode(prefs.getString('chat_token_usage_v1')!) as Map;
    expect((stored['conversation'] as Map)['sent'], 11);
    expect((stored['conversation'] as Map)['received'], 3);
  });

  test('successful stream usage is not recorded again after onUsage', () async {
    final harness = StreamHarness();

    final result = await run(harness, model());

    expect(result, ['reply']);
    expect(requests, hasLength(1));
    expect(requests.single['stream'], isTrue);
    expect(harness.errors, [null]);
    expect(harness.replaced.last.content, 'reply');
    expect(harness.appended, hasLength(1));
    expect(harness.removed, isEmpty);
    expect(harness.clearReplyingCalls, 1);
    final usage = TokenUsageProvider.instance.usageFor('conversation');
    expect(usage.sentTokens, 11);
    expect(usage.receivedTokens, 3);
    expect(usage.totalTokens, 14);
    expect(usage.label, 'Character');
    expect(usageUpdates, 1);
    final prefs = await SharedPreferences.getInstance();
    final stored = jsonDecode(prefs.getString('chat_token_usage_v1')!) as Map;
    expect((stored['conversation'] as Map)['sent'], 11);
    expect((stored['conversation'] as Map)['received'], 3);
  });
}
