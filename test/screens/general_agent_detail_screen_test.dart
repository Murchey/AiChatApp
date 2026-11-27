import 'package:ai_chat/models/character.dart';
import 'package:ai_chat/models/conversation.dart';
import 'package:ai_chat/providers/api_provider.dart';
import 'package:ai_chat/providers/character_provider.dart';
import 'package:ai_chat/providers/chat_background_provider.dart';
import 'package:ai_chat/providers/chat_provider.dart';
import 'package:ai_chat/providers/chat_settings_provider.dart';
import 'package:ai_chat/providers/settings_provider.dart';
import 'package:ai_chat/screens/chat_detail_screen.dart';
import 'package:ai_chat/screens/prompt_edit_screen.dart';
import 'package:ai_chat/screens/chat_settings_screen.dart';
import 'package:ai_chat/screens/character_detail_screen.dart';
import 'package:ai_chat/widgets/chat/chat_detail_character_card.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _AgentCharacters extends CharacterProvider {
  Character character = Character(
    id: 'agent-1',
    name: '助手',
    isGeneralAgent: true,
    remark: '旧备注不应显示',
    signature: '旧签名不应显示',
    region: '旧地区不应显示',
    userRelationship: '旧关系不应显示',
    activeStart: '08:00',
    activeEnd: '20:00',
    voiceId: 'voice-only-role',
    modelId: 'role-model-only',
  );

  @override
  Character? getCharacterById(String id) =>
      id == character.id ? character : null;

  @override
  Future<void> updateCharacterInfo(
    String id, {
    String? name,
    String? remark,
    String? signature,
    String? region,
    String? userRelationship,
    String? voiceId,
    String? voiceInstructions,
    String? voiceType,
    String? voiceSampleFile,
    String? voiceTemplatePath,
    String? voiceMimeType,
    bool clearVoice = false,
    String? activeStart,
    String? activeEnd,
  }) async {
    character = character.copyWith(name: name);
    notifyListeners();
  }

  @override
  Future<void> updateSystemPrompt(String id, String prompt) async {
    character = character.copyWith(systemPrompt: prompt);
    notifyListeners();
  }
}

class _AgentChat extends ChatProvider {
  final Conversation? conversation;
  String? lastDisplayName;

  _AgentChat(this.conversation);

  @override
  List<Conversation> get conversations =>
      conversation == null ? [] : [conversation!];

  @override
  void updateCharacterDisplayName(String characterId, String displayName) {
    lastDisplayName = displayName;
  }
}

Widget _screen(
    _AgentCharacters characters, _AgentChat chat, bool useConversationId) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<CharacterProvider>.value(value: characters),
      ChangeNotifierProvider<ChatProvider>.value(value: chat),
      ChangeNotifierProvider(create: (_) => ChatBackgroundProvider()),
      ChangeNotifierProvider(create: (_) => ApiProvider()),
      ChangeNotifierProvider(create: (_) => ChatSettingsProvider()),
      ChangeNotifierProvider(create: (_) => SettingsProvider()),
    ],
    child: CupertinoApp(
      home: ChatDetailScreen(
        conversationId: useConversationId ? 'conversation-1' : '',
        characterName: '过期名称',
        characterId: useConversationId ? null : 'agent-1',
      ),
    ),
  );
}

void main() {
  for (final useConversationId in [false, true]) {
    testWidgets('一般智能体精简详情和编辑支持入口 ($useConversationId)', (tester) async {
      final characters = _AgentCharacters();
      final chat = _AgentChat(useConversationId
          ? Conversation(
              id: 'conversation-1', characterId: 'agent-1', characterName: '助手')
          : null);
      await tester.pumpWidget(_screen(characters, chat, useConversationId));

      expect(find.text('智能体详情'), findsOneWidget);
      expect(find.text('头像'), findsOneWidget);
      expect(find.text('名称'), findsOneWidget);
      expect(find.text('用户提示词'), findsOneWidget);
      expect(find.text('可留空，点击编辑'), findsOneWidget);
      expect(find.text('聊天设置'), findsOneWidget);
      expect(find.text('清空上下文'),
          useConversationId ? findsOneWidget : findsNothing);
      expect(
          find.text('删除聊天'), useConversationId ? findsOneWidget : findsNothing);
      expect(find.byType(ChatDetailCharacterCard), findsNothing);
      for (final roleOnly in [
        '角色昵称',
        '角色备注',
        '个性签名',
        '定位地区',
        '与我的关系',
        '活跃时段',
        '音频与声音',
        '使用的模型',
        '自动发朋友圈',
        '主动问候',
        '记忆点管理',
        '朋友圈',
        '旧备注不应显示',
        '旧签名不应显示',
        '旧地区不应显示',
      ]) {
        expect(find.text(roleOnly), findsNothing, reason: roleOnly);
      }

      await tester.tap(find.text('名称'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CupertinoTextField), '新助手');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(characters.character.name, '新助手');
      expect(chat.lastDisplayName, '新助手');
      expect(characters.character.displayName, '新助手');
      expect(characters.character.remark, '旧备注不应显示');
      expect(characters.character.signature, '旧签名不应显示');
      expect(characters.character.modelId, 'role-model-only');

      await tester.tap(find.byKey(const ValueKey('agent-avatar')));
      await tester.pumpAndSettle();
      expect(find.text('更换头像'), findsOneWidget);
      expect(find.text('从相册选择'), findsOneWidget);
      expect(find.text('拍照'), findsOneWidget);
      expect(find.byType(CharacterDetailScreen), findsNothing);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('用户提示词'));
      await tester.pumpAndSettle();
      expect(find.byType(PromptEditScreen), findsOneWidget);
      expect(find.text('智能体：新助手'), findsOneWidget);
      await tester.enterText(find.byType(CupertinoTextField), '只输出译文');
      await tester.pump(const Duration(milliseconds: 600));
      expect(characters.character.systemPrompt, '只输出译文');
      await tester.tap(find.text('清空'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(characters.character.systemPrompt, '');
      final navigator =
          tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.pop();
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('聊天设置'));
      await tester.tap(find.text('聊天设置'));
      await tester.pumpAndSettle();
      final settings =
          tester.widget<ChatSettingsScreen>(find.byType(ChatSettingsScreen));
      expect(settings.characterId, 'agent-1');
      expect(
          settings.conversationId, useConversationId ? 'conversation-1' : null);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('普通角色保留角色卡和资料设置', (tester) async {
    final characters = _AgentCharacters();
    characters.character = characters.character.copyWith(isGeneralAgent: false);
    await tester.pumpWidget(_screen(characters, _AgentChat(null), false));
    expect(find.byType(ChatDetailCharacterCard), findsOneWidget);
    expect(find.text('角色昵称'), findsOneWidget);
    expect(find.text('角色备注'), findsOneWidget);
    expect(find.text('个性签名'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('记忆点管理'), findsOneWidget);
  });
}
