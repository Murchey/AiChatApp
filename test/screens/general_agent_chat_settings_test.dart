import 'package:ai_chat/models/character.dart';
import 'package:ai_chat/models/conversation.dart';
import 'package:ai_chat/providers/api_provider.dart';
import 'package:ai_chat/providers/character_provider.dart';
import 'package:ai_chat/providers/chat_provider.dart';
import 'package:ai_chat/providers/chat_settings_provider.dart';
import 'package:ai_chat/screens/chat_settings_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestChat extends ChatProvider {
  @override
  List<Conversation> get conversations => [
        Conversation(
          id: 'general-conversation',
          characterId: 'general-agent',
          characterName: '助手',
        )
      ];
}

class _TestCharacters extends CharacterProvider {
  @override
  Character? getCharacterById(String id) => Character(
        id: 'general-agent',
        name: '助手',
        isGeneralAgent: true,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('一般智能体会话设置只显示普通聊天配置', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = ChatSettingsProvider();
    await settings.init();
    final chat = _TestChat();
    final characters = _TestCharacters();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ChatSettingsProvider>.value(value: settings),
        ChangeNotifierProvider<ApiProvider>(create: (_) => ApiProvider()),
        ChangeNotifierProvider<ChatProvider>.value(value: chat),
        ChangeNotifierProvider<CharacterProvider>.value(value: characters),
      ],
      child: const CupertinoApp(
        home: ChatSettingsScreen(conversationId: 'general-conversation'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('携带上下文条数'), findsOneWidget);
    final contextSlider =
        tester.widget<CupertinoSlider>(find.byType(CupertinoSlider).first);
    contextSlider.onChanged!(contextSlider.max);
    await tester.pumpAndSettle();
    expect(settings.isUnlimitedContext, isTrue);
    expect(settings.enableCompression, isFalse);
    expect(find.text('使用的模型'), findsOneWidget);
    expect(find.text('输入框'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('模型思考强度'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('模型思考强度'), findsOneWidget);
    expect(find.text('朋友圈记忆'), findsNothing);
    expect(find.text('回复格式'), findsNothing);
    expect(find.text('语C/短信模式'), findsNothing);
    expect(find.text('生成语C候选行动'), findsNothing);
    expect(find.text('自动压缩历史消息'), findsNothing);
    expect(find.text('压缩会话'), findsNothing);
    expect(find.text('记忆点自动托管'), findsNothing);
    expect(settings.enableCompression, isFalse);
  });
}
