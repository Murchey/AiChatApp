import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_chat/models/message.dart';
import 'package:ai_chat/providers/api_provider.dart';
import 'package:ai_chat/providers/group_chat_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

GroupMemberReply member(ApiModel model,
        {String id = 'a',
        String prompt = '',
        String memoryPool = '',
        List<String> memory = const []}) =>
    GroupMemberReply(
      characterId: id,
      name: '同名',
      systemPrompt: prompt,
      userRelationship: '',
      activeStart: '',
      activeEnd: '',
      model: model,
      memoryPoints: memory,
      memoryPool: memoryPool,
    );

Message message(
  String groupId,
  String id,
  String content, {
  String? senderId,
  MessageType type = MessageType.text,
}) =>
    Message(
        id: id,
        conversationId: groupId,
        content: content,
        sender: senderId == null ? MessageSender.user : MessageSender.character,
        senderCharacterId: senderId ?? '',
        senderName: senderId == null ? '' : '同名',
        type: type);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  late GroupChatProvider provider;
  late String groupId;
  late ApiModel model;
  late List<Map<String, dynamic>> requests;
  late Future<String> Function(int index) response;

  setUp(() async {
    final previous = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previous);
    SharedPreferences.setMockInitialValues({});
    requests = [];
    response = (_) async => '[]';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      requests.add(jsonDecode(body) as Map<String, dynamic>);
      final content = await response(requests.length - 1);
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'choices': [
          {
            'message': {'content': content}
          }
        ]
      }));
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    model = ApiModel(
        id: 'test',
        displayName: 'test',
        modelName: 'test',
        apiKey: 'test-key',
        baseUrl: 'http://127.0.0.1:${server.port}',
        contextLength: 32000);
    provider = GroupChatProvider();
    groupId =
        provider.createGroup(name: '群聊', memberCharacterIds: ['a', 'b']).id;
    provider.markGroupActive(groupId);
    await provider.setQuoteProbability(groupId, 0);
  });

  Future<void> run(List<GroupMemberReply> members, {int count = 0}) =>
      provider.runGroupReply(
          groupId: groupId,
          members: members,
          userNickname: '用户',
          contextCount: count,
          mentionedCharacterIds: members.map((m) => m.characterId).toList());

  test('unlimited history is blocked visibly without modifying stored messages',
      () async {
    final original = message(groupId, 'long', List.filled(20000, '中').join());
    await provider.importMessages(groupId: groupId, messages: [original]);
    await run([member(model)]);
    expect(requests, isEmpty);
    expect(provider.lastError, contains('上下文超限'));
    expect(provider.lastError, contains('同名'));
    expect(provider.getMessages(groupId), [same(original)]);
    expect(provider.isReplying(groupId), isFalse);
    expect(provider.replyDone, 0);
  });

  test(
      'member budgets include persona, memory, pool and reject unknown capacity',
      () async {
    for (final candidate in [
      member(model.copyWith(contextLength: 0)),
      member(model, prompt: List.filled(20000, '中').join()),
      member(model, memory: [List.filled(20000, '中').join()]),
      member(model, memoryPool: List.filled(20000, '中').join()),
    ]) {
      await run([candidate]);
      expect(provider.lastError, isNotNull);
    }
    expect(requests, isEmpty);
  });

  test('reasoning output reserve and unknown capacity fail before HTTP',
      () async {
    await run([
      member(model.copyWith(modelName: 'vendor/grok-4', contextLength: 5000))
    ]);
    expect(requests, isEmpty);
    expect(provider.lastError, contains('输出预留 4096'));
    await run([member(model.copyWith(contextLength: -1))]);
    expect(provider.lastError, contains('上下文长度无效'));
    expect(requests, isEmpty);
  });

  test('quote instruction is budgeted even outside selected history', () async {
    await provider.setQuoteProbability(groupId, 1);
    await provider.importMessages(groupId: groupId, messages: [
      message(groupId, 'quoted', List.filled(20000, '中').join(), senderId: 'b'),
      message(groupId, 'latest', 'recent'),
    ]);
    await run([member(model)], count: 1);
    expect(requests, isEmpty);
    expect(provider.lastError, contains('上下文超限'));
    expect(provider.getMessages(groupId), hasLength(2));
  });

  test('each member is evaluated against their model budget', () async {
    await provider.sendMessage(groupId: groupId, content: 'hello');
    await run([
      member(model.copyWith(contextLength: 100)),
      member(model, id: 'b'),
    ]);
    expect(requests, hasLength(1));
    expect(provider.lastError, contains('上下文超限'));
    expect(provider.getMessages(groupId), hasLength(1));
  });

  test('self role uses stable id across text and media with duplicate names',
      () async {
    await provider.importMessages(groupId: groupId, messages: [
      message(groupId, 'own', 'own text', senderId: 'a'),
      message(groupId, 'other', 'other text', senderId: 'b'),
      message(groupId, 'legacy', 'legacy text', senderId: ''),
      message(groupId, 'image', '/missing/image.png',
          senderId: 'b', type: MessageType.image),
      message(groupId, 'sticker', '/local/sticker.png',
          senderId: 'b', type: MessageType.sticker),
      message(groupId, 'file', '/local/file.txt',
          senderId: 'b', type: MessageType.file),
      message(groupId, 'system', 'joined',
          senderId: 'b', type: MessageType.system),
    ]);
    await run([member(model)]);
    final sent = (requests.single['messages'] as List).cast<Map>();
    final history = sent.sublist(1, sent.length - 1);
    expect(history.map((m) => m['role']),
        ['assistant', 'user', 'user', 'user', 'user', 'user', 'user']);
    expect(history[0]['content'], contains('ID=a'));
    expect(history[1]['content'], contains('ID=b'));
    expect(history[2]['content'], contains('ID 未知'));
    expect(sent.first['content'], contains('角色 ID 为 a'));
    expect(sent.last['content'], contains('只输出 同名 自己的新内容'));
    expect(jsonEncode(history), isNot(contains('/local/')));
  });

  test('message access prevents untracked source edits', () async {
    await provider.sendMessage(groupId: groupId, content: 'source');
    final exposed = provider.getMessages(groupId);
    expect(() => exposed.clear(), throwsUnsupportedError);
    expect(provider.getMessages(groupId).single.content, 'source');
  });

  test('explicit recent context fits while full history remains recoverable',
      () async {
    await provider.importMessages(groupId: groupId, messages: [
      message(groupId, 'old', List.filled(20000, '中').join()),
      message(groupId, 'new', 'recent'),
    ]);
    await run([member(model)], count: 1);
    expect(requests, hasLength(1));
    expect(provider.lastError, isNull);
    expect(provider.getMessages(groupId).map((m) => m.id), ['old', 'new']);
  });

  test('image estimate respects budget while preserving larger image inputs',
      () async {
    final temp = await Directory.systemTemp.createTemp('group-budget-');
    addTearDown(() => temp.delete(recursive: true));
    final image = File('${temp.path}/image.png');
    await image.writeAsBytes(List.filled(1024, 1));
    await provider.sendImageMessage(groupId: groupId, imagePath: image.path);
    await run([member(model.copyWith(contextLength: 3000))]);
    expect(provider.lastError, contains('上下文超限'));
    expect(requests, isEmpty);
    await run([member(model.copyWith(contextLength: 6000))]);
    expect(provider.lastError, isNull);
    expect(requests, hasLength(1));
    await image.writeAsBytes(List.filled(4 * 1024 * 1024 + 1, 1));
    await run([member(model.copyWith(contextLength: 6000))]);
    expect(provider.lastError, isNull);
    expect(requests, hasLength(2));
    final sent = (requests.last['messages'] as List).cast<Map>();
    final content = sent[1]['content'] as List;
    final imagePart =
        content.cast<Map>().singleWhere((part) => part['type'] == 'image_url');
    final url = (imagePart['image_url'] as Map)['url'] as String;
    expect(base64Decode(url.split(',').last), hasLength(4 * 1024 * 1024 + 1));
    expect(provider.getMessages(groupId), hasLength(1));
  });

  for (final operation in [
    'edit',
    'delete',
    'withdraw',
    'removeMember',
    'deleteGroup',
    'append'
  ]) {
    test('pending reply is discarded after $operation', () async {
      await provider.sendMessage(groupId: groupId, content: 'source');
      final source = provider.getMessages(groupId).single;
      final started = Completer<void>();
      final release = Completer<String>();
      response = (_) {
        started.complete();
        return release.future;
      };
      final pending = run([member(model)]);
      await started.future;
      switch (operation) {
        case 'edit':
          await provider.editMessage(
              groupId: groupId, messageId: source.id, content: 'edited');
        case 'delete':
          provider.deleteMessage(groupId, source.id);
        case 'withdraw':
          provider.withdrawMessage(groupId, source.id);
        case 'removeMember':
          provider.removeMembers(groupId, ['a']);
        case 'deleteGroup':
          provider.deleteGroup(groupId);
        case 'append':
          await provider.sendMessage(groupId: groupId, content: 'new source');
      }
      release.complete(jsonEncode(['stale reply']));
      await pending;
      expect(
          provider.getMessages(groupId).any((m) => m.content == 'stale reply'),
          isFalse);
      if (operation == 'edit') {
        expect(provider.messageFor(groupId, source.id)?.content, 'edited');
        expect(provider.messageRevisionFor(groupId, source.id), 1);
      }
      if (operation == 'deleteGroup') {
        expect(provider.getGroupById(groupId), isNull);
      }
      expect(provider.isReplying(groupId), isFalse);
    });
  }

  test('finishing an old round preserves newer round progress', () async {
    await provider.sendMessage(groupId: groupId, content: 'source');
    final firstStarted = Completer<void>();
    final secondStarted = Completer<void>();
    final firstResult = Completer<String>();
    final secondResult = Completer<String>();
    response = (index) {
      if (index == 0) {
        firstStarted.complete();
        return firstResult.future;
      }
      secondStarted.complete();
      return secondResult.future;
    };
    final oldRound = run([member(model)]);
    await firstStarted.future;
    final newRound = run([member(model)]);
    await secondStarted.future;
    firstResult.complete('[]');
    await oldRound;
    expect(provider.isReplying(groupId), isTrue);
    expect(provider.replyTotal, 1);
    secondResult.complete('[]');
    await newRound;
    expect(provider.isReplying(groupId), isFalse);
  });
}
