import 'package:ai_chat/config/theme.dart';
import 'package:ai_chat/providers/api_provider.dart';
import 'package:ai_chat/providers/auth_provider.dart';
import 'package:ai_chat/providers/auto_moment_provider.dart';
import 'package:ai_chat/providers/character_provider.dart';
import 'package:ai_chat/providers/chat_background_provider.dart';
import 'package:ai_chat/providers/chat_provider.dart';
import 'package:ai_chat/providers/chat_settings_provider.dart';
import 'package:ai_chat/providers/group_chat_provider.dart';
import 'package:ai_chat/providers/memory_point_provider.dart';
import 'package:ai_chat/providers/moment_notification_provider.dart';
import 'package:ai_chat/providers/proactive_greeting_provider.dart';
import 'package:ai_chat/providers/settings_provider.dart';
import 'package:ai_chat/providers/sticker_provider.dart';
import 'package:ai_chat/providers/token_usage_provider.dart';
import 'package:ai_chat/providers/workshop_provider.dart';
import 'package:ai_chat/screens/home_screen.dart';
import 'package:ai_chat/screens/chat_search_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpHome(
  WidgetTester tester,
  SettingsProvider settings,
  ChatProvider chat,
) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider.value(value: chat),
        ChangeNotifierProvider(create: (_) => CharacterProvider()),
        ChangeNotifierProvider(create: (_) => GroupChatProvider()),
        ChangeNotifierProvider(create: (_) => ChatBackgroundProvider()),
        ChangeNotifierProvider(create: (_) => ApiProvider()),
        ChangeNotifierProvider(create: (_) => ChatSettingsProvider()),
        ChangeNotifierProvider(create: (_) => MomentNotificationProvider()),
        ChangeNotifierProvider(create: (_) => MemoryPointProvider()),
        ChangeNotifierProvider(create: (_) => AutoMomentProvider()),
        ChangeNotifierProvider(create: (_) => ProactiveGreetingProvider()),
        ChangeNotifierProvider(create: (_) => WorkshopProvider()),
        ChangeNotifierProvider(create: (_) => StickerProvider()),
        ChangeNotifierProvider.value(value: TokenUsageProvider.instance),
      ],
      child: CupertinoApp(
        theme: AppTheme.buildTheme(
          brightness: Brightness.light,
          accent: AppColors.presetColors.first,
        ),
        home: const HomeScreen(),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('删除会话只从首页移除，新消息后重新出现', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.init();
    await settings.setAutoCheckUpdate(false);

    final chat = ChatProvider();
    final conversation = chat.getOrCreateConversation(
      characterId: 'hidden-char',
      characterName: '隐藏测试角色',
    );
    chat.markConversationActive(conversation.id);
    chat.addProactiveMessage(conversation.id, '第一条消息');

    await _pumpHome(tester, settings, chat);
    expect(find.text('隐藏测试角色'), findsOneWidget);

    await chat.hideConversation(conversation.id);
    await tester.pump();

    expect(find.text('隐藏测试角色'), findsNothing);
    // 会话只是从首页隐藏，聊天记录仍然保留
    expect(chat.getMessages(conversation.id).single.content, '第一条消息');

    chat.addProactiveMessage(conversation.id, '第二条消息');
    await tester.pump();

    expect(find.text('隐藏测试角色'), findsOneWidget);
  });

  testWidgets('长按会话菜单提供删除会话并保留聊天记录', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.init();
    await settings.setAutoCheckUpdate(false);

    final chat = ChatProvider();
    final conversation = chat.getOrCreateConversation(
      characterId: 'menu-char',
      characterName: '菜单测试角色',
    );
    chat.markConversationActive(conversation.id);
    chat.addProactiveMessage(conversation.id, '保留的消息');

    await _pumpHome(tester, settings, chat);

    await tester.longPress(find.text('菜单测试角色'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('置顶聊天'), findsOneWidget);
    expect(find.text('删除会话'), findsOneWidget);

    await tester.tap(find.text('删除会话'));
    await tester.pump(const Duration(milliseconds: 300));

    // 确认弹窗说明只会从首页移除，聊天记录仍会保留
    expect(find.text('删除'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('菜单测试角色'), findsNothing);
    expect(
      chat.getMessages(conversation.id).single.content,
      '保留的消息',
    );
    expect(
      chat.conversations.firstWhere((c) => c.id == conversation.id).hidden,
      isTrue,
    );
  });

  testWidgets('加号在 PageView 标签滑动时固定并淡出', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.init();
    await settings.setAutoCheckUpdate(false);
    final chat = ChatProvider();
    await _pumpHome(tester, settings, chat);

    final button = find.byKey(const Key('home-create-button'));
    expect(button, findsOneWidget);
    var opacity = tester
        .widget<Opacity>(
          find.ancestor(of: button, matching: find.byType(Opacity)).first,
        )
        .opacity;
    expect(opacity, 1);

    await tester.drag(find.byType(PageView), const Offset(-700, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    opacity = tester
        .widget<Opacity>(
          find.ancestor(of: button, matching: find.byType(Opacity)).first,
        )
        .opacity;
    expect(opacity, lessThan(0.01));
  });

  testWidgets('搜索返回时首页导航栏与加号保持同一转场层', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.init();
    await settings.setAutoCheckUpdate(false);
    await _pumpHome(tester, settings, ChatProvider());

    final title = find.text('AiChat');
    final navigationBar = tester.widget<CupertinoNavigationBar>(
      find
          .ancestor(of: title, matching: find.byType(CupertinoNavigationBar))
          .first,
    );
    expect(navigationBar.transitionBetweenRoutes, isFalse);
    expect(find.ancestor(of: title, matching: find.byType(Hero)), findsNothing);

    final button =
        find.byKey(const ValueKey('home-create-button'), skipOffstage: false);
    final buttonElement = tester.element(button);
    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.tap(find.byIcon(CupertinoIcons.search));
      await tester.pumpAndSettle();
      expect(find.byType(ChatSearchScreen), findsOneWidget);
      Navigator.of(tester.element(find.byType(ChatSearchScreen))).pop();
      await tester.pump();
      for (var frame = 0; frame < 24; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.element(button), same(buttonElement));
        final opacity = tester.widget<Opacity>(find
            .ancestor(
              of: button,
              matching: find.byType(Opacity),
            )
            .first);
        expect(opacity.opacity, 1);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      expect(button.hitTestable(), findsOneWidget);
    }
    await tester.tap(button);
    await tester.pump();
    expect(find.text('创建群聊'), findsOneWidget);
    expect(find.text('创建一般智能体'), findsOneWidget);
  });

  testWidgets('加号菜单提供创建群聊和一般智能体', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.init();
    await settings.setAutoCheckUpdate(false);
    final chat = ChatProvider();
    await _pumpHome(tester, settings, chat);

    await tester.tap(find.byIcon(CupertinoIcons.add));
    await tester.pump();
    expect(find.text('创建群聊'), findsOneWidget);
    expect(find.text('创建一般智能体'), findsOneWidget);

    await tester.tap(find.text('创建一般智能体'));
    await tester.pumpAndSettle();
    expect(find.text('创建一般智能体'), findsOneWidget);
    expect(find.byKey(const Key('general-agent-name')), findsOneWidget);
    expect(find.byKey(const Key('general-agent-prompt')), findsOneWidget);
  });
}
