import 'package:ai_chat/models/character.dart';
import 'package:ai_chat/models/conversation.dart';
import 'package:ai_chat/providers/character_provider.dart';
import 'package:ai_chat/providers/chat_provider.dart';
import 'package:ai_chat/screens/create_general_agent_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class RecordingCharacters extends CharacterProvider {
  Character? created;
  @override
  Future<Character> addCharacter(Character character) async {
    created = character;
    return character;
  }
}

class RecordingChat extends ChatProvider {
  String? characterId;
  @override
  Conversation getOrCreateConversation({
    required String characterId,
    required String characterName,
    String characterAvatar = '',
  }) {
    this.characterId = characterId;
    return Conversation(
        id: 'new-chat', characterId: characterId, characterName: characterName);
  }
}

void main() {
  for (final prompt in ['', '你是一名翻译，只输出译文。']) {
    testWidgets('创建一般智能体保留可选提示词 ($prompt)', (tester) async {
      final characters = RecordingCharacters();
      final chat = RecordingChat();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<CharacterProvider>.value(value: characters),
          ChangeNotifierProvider<ChatProvider>.value(value: chat),
        ],
        child: CupertinoApp(
          home: const CreateGeneralAgentScreen(),
          onGenerateRoute: (settings) => CupertinoPageRoute<void>(
            builder: (_) => const CupertinoPageScaffold(child: Text('新会话')),
          ),
        ),
      ));
      final button = tester
          .widget<CupertinoButton>(find.widgetWithText(CupertinoButton, '创建'));
      expect(button.onPressed, isNull);
      await tester.enterText(
          find.byKey(const Key('general-agent-name')), '翻译助手');
      if (prompt.isNotEmpty) {
        await tester.enterText(
            find.byKey(const Key('general-agent-prompt')), prompt);
      }
      await tester.pump();
      await tester.tap(find.text('创建'));
      await tester.pumpAndSettle();
      expect(characters.created?.isGeneralAgent, isTrue);
      expect(characters.created?.name, '翻译助手');
      expect(characters.created?.systemPrompt, prompt);
      expect(chat.characterId, characters.created?.id);
      expect(find.text('新会话'), findsOneWidget);
    });
  }
}
