import 'dart:convert';
import 'dart:io';

import 'package:ai_chat/providers/api_provider.dart';
import 'package:ai_chat/providers/chat_reply_builder.dart';
import 'package:ai_chat/providers/chat_token_estimator.dart';
import 'package:ai_chat/providers/chat_reply_runner.dart';
import 'package:ai_chat/providers/token_usage_provider.dart';
import 'package:ai_chat/models/character.dart';
import 'package:ai_chat/models/message.dart';
import 'package:ai_chat/providers/chat_provider.dart';
import 'package:ai_chat/services/character_pack_service.dart';
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
  test(
      'general-agent Character flag defaults false and survives JSON round trip',
      () {
    final ordinary = Character(id: 'ordinary', name: 'Ordinary');
    expect(ordinary.isGeneralAgent, isFalse);
    final general = ordinary.copyWith(isGeneralAgent: true);
    final json = general.toJson();
    expect(json['is_general_agent'], isTrue);
    expect(Character.fromJson(json).isGeneralAgent, isTrue);
  });
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

  test('general agent sends only history and keeps raw response as one message',
      () async {
    final harness = ReplyHarness();
    final result = await generateProactiveMessagesWithHooks(
      hooks: harness.hooks,
      conversationId: 'general',
      model: model(),
      characterName: 'Ignored display name',
      characterSystemPrompt: '',
      userRelationship: 'ignored relationship',
      userNickname: 'ignored nickname',
      isGeneralAgent: true,
      roleplayMode: true,
      activeStart: '08:00',
      memoryPoints: const ['ignored memory'],
      extraSystemContext: 'ignored memory pool',
      historyMessages: const [
        {'role': 'user', 'content': 'hi'},
      ],
    );
    expect(result.messages, ['["reply"]']);
    expect(requests.single['messages'], [
      {'role': 'user', 'content': 'hi'},
    ]);
    expect(harness.systemTokens, 0);
    expect(requests.single.containsKey('response_format'), isFalse);
  });

  test('general agent vision request has no injected text instruction',
      () async {
    final image = File('${Directory.systemTemp.path}/general-agent.png');
    await image.writeAsBytes([1, 2, 3]);
    addTearDown(() async {
      if (await image.exists()) await image.delete();
    });
    final harness = ReplyHarness();
    final result = await generateProactiveMessagesWithHooks(
      hooks: harness.hooks,
      conversationId: 'general-image',
      model: model(),
      characterName: 'General',
      characterSystemPrompt: '',
      userRelationship: '',
      userNickname: '',
      isGeneralAgent: true,
      imagePath: image.path,
    );
    expect(result.messages, ['["reply"]']);
    final outgoing = requests.single['messages'] as List;
    expect(outgoing, hasLength(1));
    expect((outgoing.single as Map)['role'], 'user');
    final parts = (outgoing.single as Map)['content'] as List;
    expect(parts, hasLength(1));
    expect((parts.single as Map)['type'], 'image_url');
    expect(harness.systemTokens, 0);
  });

  test(
      'general agent ignores whitespace prompt and does not invoke compression hooks',
      () async {
    final harness = ReplyHarness()
      ..history = [
        {'role': 'user', 'content': 'question'}
      ];
    final result = await generateProactiveMessagesWithHooks(
      hooks: harness.hooks,
      conversationId: 'general-compress',
      model: model(),
      characterName: 'General',
      characterSystemPrompt: '   ',
      userRelationship: '',
      userNickname: '',
      isGeneralAgent: true,
      enableCompression: true,
      compressModel: model(),
    );
    expect(result.messages, ['["reply"]']);
    expect(harness.compressionCalls, 0);
    expect(harness.systemTokens, 0);
    expect(requests.single['messages'], [
      {'role': 'user', 'content': 'question'},
    ]);
  });

  test(
      'general agent rejects oversized history before HTTP with no builtin fallback',
      () async {
    final harness = ReplyHarness();
    final result = await generateProactiveMessagesWithHooks(
      hooks: harness.hooks,
      conversationId: 'general-budget',
      model: model(),
      characterName: 'General',
      characterSystemPrompt: '',
      userRelationship: '',
      userNickname: '',
      isGeneralAgent: true,
      historyMessages: [
        {'role': 'user', 'content': 'large' * 100000}
      ],
    );
    expect(result.messages, isEmpty);
    expect(harness.error, contains('上下文超限'));
    expect(requests, isEmpty);
  });

  test('general agent package round trip keeps mode and optional prompt',
      () async {
    final directory = await Directory.systemTemp.createTemp('general-pack-');
    addTearDown(() => directory.delete(recursive: true));
    final packed = await CharacterPackService.encodeCharacterPack([
      Character(id: 'blank', name: 'Blank', isGeneralAgent: true),
      Character(
          id: 'custom',
          name: 'Custom',
          isGeneralAgent: true,
          systemPrompt: 'Custom instruction'),
    ]);
    final file = File('${directory.path}/pack.zip');
    await file.writeAsBytes(packed.bytes);
    final entries = await CharacterPackService.parsePack(file.path);
    expect(entries, hasLength(2));
    expect(entries.every((entry) => entry.character.isGeneralAgent), isTrue);
    expect(
        entries
            .firstWhere((entry) => entry.character.name == 'Blank')
            .character
            .systemPrompt,
        isEmpty);
    expect(
        entries
            .firstWhere((entry) => entry.character.name == 'Custom')
            .character
            .systemPrompt,
        'Custom instruction');
  });

  test(
      'provider general history omits local protocols and restores original text',
      () async {
    SharedPreferences.setMockInitialValues({});
    final chat = ChatProvider();
    addTearDown(chat.dispose);
    final conversation = chat.getOrCreateConversation(
        characterId: 'general', characterName: 'General');
    chat.getMessages(conversation.id).addAll([
      Message(
          id: 'original',
          conversationId: conversation.id,
          content: 'original answer',
          sender: MessageSender.character),
      Message(
          id: 'summary',
          conversationId: conversation.id,
          content: 'Built-in compression header',
          sender: MessageSender.character,
          isCompressionSummary: true),
      Message(
          id: 'narration',
          conversationId: conversation.id,
          content: 'Built-in narration',
          sender: MessageSender.user,
          type: MessageType.narration),
      Message(
          id: 'sticker',
          conversationId: conversation.id,
          content: 'local-sticker.png',
          sender: MessageSender.user,
          type: MessageType.sticker),
      Message(
          id: 'last',
          conversationId: conversation.id,
          content: 'actual question',
          sender: MessageSender.user),
    ]);
    final result = await chat.generateProactiveMessages(
      conversationId: conversation.id,
      model: model(),
      characterName: 'General',
      characterSystemPrompt: 'Custom instruction',
      userRelationship: '',
      userNickname: '',
      isGeneralAgent: true,
      enableCompression: true,
      compressModel: model(),
      contextCount: 2,
    );
    expect(result.messages, ['["reply"]']);
    expect(requests.single['messages'], [
      {'role': 'system', 'content': 'Custom instruction'},
      {'role': 'assistant', 'content': 'original answer'},
      {'role': 'user', 'content': 'actual question'},
    ]);
  });

  test('general runner keeps whitespace and sticker markers as ordinary text',
      () async {
    SharedPreferences.setMockInitialValues({});
    await TokenUsageProvider.instance.reload();
    final stored = <String>[];
    var stickerLookups = 0;
    var contextTokens = 0;
    const content = 'Code sample\n\n[[查询表情包:开心]]  literal';
    final displayed = await processProactiveReplyMessages(
      hooks: ProactiveReplyHooks(
        addProactiveMessage: (_, text,
            {reasoningContent = '', reasoningDurationMs}) {
          stored.add(text);
        },
        addSticker: (
            {required conversationId, required stickerPath, required label}) {
          fail('General reply must remain ordinary text');
        },
        messageCount: (_) => stored.length,
        conversationAvatar: (_) => '',
        estimateInputBudget: (_, __) => 15,
        setContextTokens: (_, tokens) => contextTokens = tokens,
        clearReplying: () {},
        notify: () {},
      ),
      conversationId: 'general-runner',
      characterName: 'General',
      messages: const [content],
      result: const ProactiveResult([content], ChatUsage()),
      reasoningContent: 'reasoning',
      reasoningDurationMs: 20,
      contextCount: 10,
      usage: const ChatUsage(
          promptTokens: 21, completionTokens: 7, totalTokens: 28),
      isGeneralAgent: true,
      findSticker: (_) {
        stickerLookups++;
        return null;
      },
    );
    expect(stored, [content]);
    expect(displayed, [content]);
    expect(stickerLookups, 0);
    expect(contextTokens, 21);
    expect(
        TokenUsageProvider.instance.usageFor('general-runner').totalTokens, 28);
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
