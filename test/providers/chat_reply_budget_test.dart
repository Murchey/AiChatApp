import 'dart:convert';
import 'dart:io';

import 'package:ai_chat/providers/api_provider.dart';
import 'package:ai_chat/providers/chat_reply_builder.dart';
import 'package:ai_chat/providers/chat_token_estimator.dart';
import 'package:ai_chat/providers/chat_reply_runner.dart';
import 'package:ai_chat/providers/token_usage_provider.dart';
import 'package:ai_chat/services/llm_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReplyHarness {
  String? error;
  int systemTokens = 0;
  int compressionTokens = 0;
  int compressionContext = 0;
  int compressionCalls = 0;
  List<Map<String, Object>> history = [];
  List<Map<String, Object>>? compressedHistory;

  ChatReplyHooks get hooks => ChatReplyHooks(
        setLastError: (message) => error = message,
        estimateTokens: ChatTokenEstimator.estimateText,
        setSystemTokens: (_, tokens) => systemTokens = tokens,
        compress: ({
          required conversationId,
          required compressModel,
          required contextLength,
          required threshold,
          required systemPromptTokens,
          required contextCount,
        }) async {
          compressionCalls++;
          compressionTokens = systemPromptTokens;
          compressionContext = contextLength;
          if (compressedHistory != null) history = compressedHistory!;
        },
        buildHistory: (_, __) => history,
      );

  Future<ProactiveResult> generate(ApiModel model,
          {bool compress = false,
          List<Map<String, Object>>? explicitHistory}) =>
      generateProactiveMessagesWithHooks(
        hooks: hooks,
        conversationId: 'conversation',
        model: model,
        characterName: 'Character',
        characterSystemPrompt: 'Reply as Character',
        userRelationship: '',
        userNickname: 'User',
        enableCompression: compress,
        compressModel: model,
        historyMessages: explicitHistory,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  late List<Map<String, dynamic>> requests;
  late String responseMode;

  setUp(() async {
    final previous = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previous);
    requests = [];
    responseMode = 'success';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      requests.add(jsonDecode(body) as Map<String, dynamic>);
      final empty = responseMode == 'empty';
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'choices': [
          {
            'message': {'content': empty ? '' : '["reply"]'},
            'finish_reason': empty ? 'length' : 'stop',
          }
        ],
        'usage': {
          'prompt_tokens': 10,
          'completion_tokens': 20,
          'total_tokens': 30
        },
      }));
      await request.response.close();
    });
  });

  ApiModel model({String name = 'test', int contextLength = 16000}) => ApiModel(
        id: name,
        displayName: name,
        modelName: name,
        apiKey: 'test-key',
        contextLength: contextLength,
        baseUrl: 'http://127.0.0.1:${server.port}',
      );

  test('sends rebuilt projection and reserves output during compression',
      () async {
    final harness = ReplyHarness()
      ..history = [
        {'role': 'user', 'content': 'old' * 10000}
      ]
      ..compressedHistory = [
        {'role': 'assistant', 'content': 'summary'}
      ];
    final result = await harness.generate(model(), compress: true);
    expect(result.messages, ['reply'], reason: harness.error);
    expect(harness.error, isNull);
    expect(harness.compressionCalls, 1);
    expect(harness.compressionContext, 16000);
    expect(harness.compressionTokens, harness.systemTokens + 1024 + 1600);
    final outgoing = requests.single['messages'] as List;
    expect((outgoing[1] as Map)['content'], 'summary');
    expect(
        ChatTokenEstimator.estimatePayload([
          Map<String, Object>.from(outgoing.first as Map),
          Map<String, Object>.from(outgoing.last as Map),
        ]),
        harness.systemTokens);
  });

  test('oversize explicit history reports error and preserves all messages',
      () async {
    final harness = ReplyHarness();
    final history = <Map<String, Object>>[
      {'role': 'user', 'content': 'oversized' * 10000},
      {'role': 'user', 'content': 'latest'},
    ];
    final snapshot = jsonEncode(history);
    final result = await harness.generate(model(),
        compress: true, explicitHistory: history);
    expect(result.messages, isEmpty);
    expect(harness.error, contains('上下文超限'));
    expect(harness.error, contains('输出预留'));
    expect(harness.compressionCalls, 0);
    expect(requests, isEmpty);
    expect(jsonEncode(history), snapshot);
  });

  test('compression that cannot fit context yields a visible error', () async {
    final harness = ReplyHarness()
      ..history = [
        {'role': 'user', 'content': 'large' * 10000}
      ];
    final result = await harness.generate(model(), compress: true);
    expect(result.messages, isEmpty);
    expect(harness.compressionCalls, 1);
    expect(harness.error, contains('上下文超限'));
    expect(harness.history.single['content'], 'large' * 10000);
    expect(requests, isEmpty);
  });

  test('failed empty replies return reported usage for runner accounting',
      () async {
    responseMode = 'empty';
    final harness = ReplyHarness();
    final result = await harness.generate(model(name: 'kimi-test'));
    expect(result.messages, isEmpty);
    expect(harness.error, isNotNull);
    expect(requests.length, 2);
    expect(result.usage.promptTokens, 20);
    expect(result.usage.completionTokens, 40);
    expect(result.usage.totalTokens, 60);
  });

  test('reasoning fallback preserves cache usage in runner accounting',
      () async {
    final usageProvider = TokenUsageProvider.instance;
    SharedPreferences.setMockInitialValues({});
    await usageProvider.reload();
    await processProactiveReplyMessages(
      hooks: ProactiveReplyHooks(
        addProactiveMessage: (_, __,
            {reasoningContent = '', reasoningDurationMs}) {},
        addSticker: (
            {required conversationId, required stickerPath, required label}) {},
        messageCount: (_) => 0,
        conversationAvatar: (_) => '',
        estimateInputBudget: (_, __) => 7,
        setContextTokens: (_, __) {},
        clearReplying: () {},
        notify: () {},
      ),
      conversationId: 'cache-usage-test',
      characterName: 'Character',
      messages: const [],
      result: const ProactiveResult([], ChatUsage()),
      reasoningContent: 'reasoning fallback',
      reasoningDurationMs: null,
      contextCount: 10,
      usage: const ChatUsage(
        promptTokens: 10,
        completionTokens: 5,
        cacheReadTokens: 3,
        cacheCreationTokens: 2,
      ),
    );
    final usage = usageProvider.usageFor('cache-usage-test');
    expect(usage.cacheReadTokens, 3);
    expect(usage.cacheCreationTokens, 2);
    expect(usage.reasoningTokens, greaterThan(0));
  });
}
