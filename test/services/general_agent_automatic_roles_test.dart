import 'dart:io';

import 'package:ai_chat/models/character.dart';
import 'package:ai_chat/models/moment.dart';
import 'package:ai_chat/providers/api_provider.dart';
import 'package:ai_chat/providers/auto_moment_provider.dart';
import 'package:ai_chat/providers/character_provider.dart';
import 'package:ai_chat/providers/chat_provider.dart';
import 'package:ai_chat/providers/chat_settings_provider.dart';
import 'package:ai_chat/providers/group_chat_provider.dart';
import 'package:ai_chat/providers/memory_point_provider.dart';
import 'package:ai_chat/providers/moment_notification_provider.dart';
import 'package:ai_chat/providers/proactive_greeting_provider.dart';
import 'package:ai_chat/services/auto_moment_service.dart';
import 'package:ai_chat/services/moment_ai_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Characters extends CharacterProvider {
  final Character general =
      Character(id: 'general', name: '助手', isGeneralAgent: true);

  @override
  List<Character> get manageableCharacters => [general];

  @override
  Character? getCharacterById(String id) => id == general.id ? general : null;
}

class _Api extends ApiProvider {
  final ApiModel model;

  _Api(this.model);

  @override
  String? get momentModelId => model.id;

  @override
  List<ApiModel> get models => [model];

  @override
  ApiModel? getModelById(String? id) => id == model.id ? model : null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'general agent skips due moments, forced greetings and moment interactions',
      () async {
    final previous = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previous);
    SharedPreferences.setMockInitialValues({});
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var requests = 0;
    server.listen((request) async {
      requests++;
      request.response.statusCode = 400;
      await request.response.close();
    });
    final api = _Api(ApiModel(
        id: 'test',
        displayName: 'test',
        modelName: 'test',
        apiKey: 'key',
        baseUrl: 'http://127.0.0.1:${server.port}'));
    final characters = _Characters();
    final chat = ChatProvider();
    final settings = ChatSettingsProvider();
    final groups = GroupChatProvider();
    final memories = MemoryPointProvider();
    final notifications = MomentNotificationProvider();
    final autoMoments = AutoMomentProvider();
    final greetings = ProactiveGreetingProvider();
    final dueAt = DateTime.now().subtract(const Duration(hours: 1));
    await autoMoments.setEnabled('general', true);
    await autoMoments.setNextDueAt('general', dueAt);
    await greetings.setEnabled('general', true);
    await greetings.setNextDueAt('general', dueAt);

    await AutoMomentService.instance.checkAndPublish(
      characterProvider: characters,
      apiProvider: api,
      chatProvider: chat,
      chatSettings: settings,
      groupChatProvider: groups,
      notificationProvider: notifications,
      autoMomentProvider: autoMoments,
      memoryPointProvider: memories,
    );
    await AutoMomentService.instance.checkProactiveGreeting(
      characterProvider: characters,
      apiProvider: api,
      chatProvider: chat,
      chatSettings: settings,
      greetingProvider: greetings,
      memoryPointProvider: memories,
      force: true,
    );
    const moment = Moment(id: 'moment', content: '动态');
    await MomentAiService.run(
      characterProvider: characters,
      apiProvider: api,
      notificationProvider: notifications,
      chatProvider: chat,
      chatSettings: settings,
      groupChatProvider: groups,
      memoryPointProvider: memories,
      moment: moment,
      characters: [characters.general],
    );
    await MomentAiService.replyToUserComment(
      apiProvider: api,
      chatSettings: settings,
      chatProvider: chat,
      groupChatProvider: groups,
      characterProvider: characters,
      notificationProvider: notifications,
      memoryPointProvider: memories,
      character: characters.general,
      owner: characters.general,
      moment: moment,
      userNickname: '用户',
      userComment: '评论',
    );

    expect(requests, 0);
    expect(chat.conversations, isEmpty);
    expect(characters.general.moments, isEmpty);
    expect(autoMoments.configFor('general').nextDueAt, dueAt);
    expect(greetings.configFor('general').nextDueAt, dueAt);
  });
}
