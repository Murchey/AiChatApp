import 'package:ai_chat/config/theme.dart';
import 'package:ai_chat/providers/api_provider.dart';
import 'package:ai_chat/providers/auth_provider.dart';
import 'package:ai_chat/providers/character_provider.dart';
import 'package:ai_chat/providers/chat_background_provider.dart';
import 'package:ai_chat/providers/chat_provider.dart';
import 'package:ai_chat/providers/chat_settings_provider.dart';
import 'package:ai_chat/providers/settings_provider.dart';
import 'package:ai_chat/screens/chat_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('多选后删除选中的消息', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.init();
    await settings.setAutoCheckUpdate(false);

    final chat = ChatProvider();
    final conversation = chat.getOrCreateConversation(
      characterId: 'char-1',
      characterName: '测试角色',
    );
    chat.markConversationActive(conversation.id);
    chat.addProactiveMessage(conversation.id, '第一条消息');
    chat.addProactiveMessage(conversation.id, '第二条消息');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider.value(value: chat),
          ChangeNotifierProvider(create: (_) => CharacterProvider()),
          ChangeNotifierProvider(create: (_) => ChatBackgroundProvider()),
          ChangeNotifierProvider(create: (_) => ApiProvider()),
          ChangeNotifierProvider(create: (_) => ChatSettingsProvider()),
        ],
        child: CupertinoApp(
          theme: AppTheme.buildTheme(
            brightness: Brightness.light,
            accent: AppColors.presetColors.first,
          ),
          home: ChatScreen(
            conversationId: conversation.id,
            characterName: '测试角色',
          ),
        ),
      ),
    );
    await tester.pump();

    // 气泡正文是 RichText，需用 findRichText 定位
    final firstMessage = find.textContaining('第一条消息', findRichText: true);
    expect(firstMessage, findsOneWidget);

    // 长按气泡 → 菜单里选择「多选」
    await tester.longPress(firstMessage);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('多选'), findsOneWidget);
    await tester.tap(find.text('多选'));
    await tester.pump();

    expect(find.text('已选 1 条'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('删除消息'), findsOneWidget);

    await tester.tap(find.text('删除').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('第一条消息', findRichText: true), findsNothing);
    expect(find.textContaining('第二条消息', findRichText: true), findsOneWidget);
    expect(chat.getMessages(conversation.id).single.content, '第二条消息');
  });
}
