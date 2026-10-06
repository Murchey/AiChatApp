import 'package:ai_chat/config/theme.dart';
import 'package:ai_chat/config/motion.dart';
import 'package:ai_chat/config/ui_spec.dart';
import 'package:ai_chat/providers/settings_provider.dart';
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
import 'package:ai_chat/providers/sticker_provider.dart';
import 'package:ai_chat/providers/token_usage_provider.dart';
import 'package:ai_chat/providers/workshop_provider.dart';
import 'package:ai_chat/screens/home_screen.dart';
import 'package:ai_chat/screens/settings_screen.dart';
import 'package:ai_chat/models/character.dart';
import 'package:ai_chat/models/moment.dart';
import 'package:ai_chat/widgets/message_input.dart';
import 'package:ai_chat/widgets/chat_title_bar.dart';
import 'package:ai_chat/widgets/moment_card.dart';
import 'package:ai_chat/widgets/settings/color_picker_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget themed(Widget child, {Brightness brightness = Brightness.light}) {
    return CupertinoApp(
      theme: AppTheme.buildTheme(
        brightness: brightness,
        accent: AppColors.presetColors.first,
      ),
      home: child,
    );
  }

  test('mobile shell tokens preserve the floating navigation geometry', () {
    expect(UiSpec.floatingNavHeight, 64);
    expect(UiSpec.floatingHorizontal, 16);
    expect(UiSpec.floatingBottomGap, 8);
    expect(UiSpec.floatingNavBlurSigma, 22);
    expect(UiSpec.floatingNavDarkOpacity, 0.58);
    expect(UiSpec.floatingNavLightOpacity, 0.70);
    expect(UiSpec.floatingSelectedSurfaceLightOpacity, 0.86);
    expect(UiSpec.floatingSelectedSurfaceDarkOpacity, 0.82);
    expect(UiSpec.floatingSelectedBorderLightOpacity, 0.24);
    expect(UiSpec.floatingSelectedBorderDarkOpacity, 0.32);
    expect(UiSpec.floatingSelectedShadowBlur, 10);
    expect(UiSpec.floatingContentBottomInset, 88);
    expect(AppMotion.tabSelection, const Duration(milliseconds: 240));
    expect(AppMotion.tabIconFade, const Duration(milliseconds: 140));
    expect(UiSpec.radiusInputCapsule, 24);
    expect(UiSpec.conversationAvatar, 44);
  });

  test('setting icon roles keep distinct light and dark semantic colors', () {
    final lightColors = [
      AppColors.settingIconAppearanceLight,
      AppColors.settingIconStickersLight,
      AppColors.settingIconDisplayLight,
      AppColors.settingIconDeveloperLight,
      AppColors.settingIconMemoryLight,
      AppColors.settingIconStorageLight,
    ];
    final darkColors = [
      AppColors.settingIconAppearanceDark,
      AppColors.settingIconStickersDark,
      AppColors.settingIconDisplayDark,
      AppColors.settingIconDeveloperDark,
      AppColors.settingIconMemoryDark,
      AppColors.settingIconStorageDark,
    ];

    expect(lightColors.map((color) => color.toARGB32()).toSet(),
        hasLength(lightColors.length));
    expect(darkColors.map((color) => color.toARGB32()).toSet(),
        hasLength(darkColors.length));
  });

  test('mobile shell changes do not replace bubble palettes', () {
    expect(AppColors.bubbleSelfLight, const Color(0xFF0A84FF));
    expect(AppColors.bubbleOtherDark, const Color(0xFF2C2C2C));
    expect(SrBubbleColors.selfColor, const Color(0xFFD2BC95));
    expect(WwBubbleColors.selfColorLight, const Color(0xFF20252E));
    expect(ZmdBubbleColors.selfBorderColor, const Color(0xFF000000));
  });

  testWidgets('message input renders as a floating capsule', (tester) async {
    await tester.pumpWidget(
      themed(
        MessageInput(
          onSend: (_) {},
          showStickerButton: false,
        ),
      ),
    );

    expect(find.byKey(const ValueKey('message-input-capsule')), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.text('输入消息...'), findsOneWidget);
  });

  testWidgets('chat title keeps a compact name and subtitle hierarchy',
      (tester) async {
    final settings = SettingsProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: themed(
          const ChatTitleBar(
            name: '艾维莉亚',
            signature: '今天也要保持好心情',
          ),
        ),
      ),
    );

    expect(find.text('艾维莉亚'), findsOneWidget);
    expect(find.text('今天也要保持好心情'), findsOneWidget);
  });

  testWidgets('settings keeps five preset colors and updates selection',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.init();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: themed(const SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PresetColorDot), findsNWidgets(5));
    expect(
      tester.widget<Icon>(find.byIcon(CupertinoIcons.smiley)).color,
      AppColors.settingIconStickersLight,
    );
    expect(
      tester.widget<Icon>(find.byIcon(CupertinoIcons.chat_bubble_2_fill)).color,
      AppColors.settingIconDisplayLight,
    );
    await tester.tap(find.byType(PresetColorDot).at(2));
    await tester.pump();

    expect(settings.accentColor, AppColors.presetColors[2]);
  });

  testWidgets('settings semantic icons use the dark color tier',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.init();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: themed(
          const SettingsScreen(),
          brightness: Brightness.dark,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<Icon>(find.byIcon(CupertinoIcons.smiley)).color,
      AppColors.settingIconStickersDark,
    );
    expect(
      tester.widget<Icon>(find.byIcon(CupertinoIcons.chat_bubble_2_fill)).color,
      AppColors.settingIconDisplayDark,
    );
  });

  testWidgets('moment cards fold long content and comment previews',
      (tester) async {
    var opened = false;
    final owner = Character(id: 'c1', name: '角色');
    final moment = Moment(
      id: 'm1',
      content: List.filled(160, '长').join(),
      comments: [
        for (var i = 0; i < 11; i++)
          MomentComment(sender: '评论者$i', content: '评论内容$i'),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: themed(
          SizedBox(
            width: 360,
            child: MomentCard(
              character: owner,
              moment: moment,
              onOpenDetail: () => opened = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('全文'), findsOneWidget);
    expect(find.text('查看全部 11 条评论'), findsOneWidget);
    expect(find.text('评论者0：评论内容0'), findsOneWidget);
    expect(find.text('评论者3：评论内容3'), findsNothing);

    await tester.tap(find.text('查看全部 11 条评论'));
    expect(opened, isTrue);
  });

  testWidgets('home exposes four floating navigation entries', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.init();
    await settings.setAutoCheckUpdate(false);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => ChatProvider()),
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
        child: themed(const HomeScreen()),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('home-floating-nav')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-floating-nav-indicator')),
        findsOneWidget);
    final indicator = tester.widget<DecoratedBox>(
      find.byKey(
        const ValueKey('home-floating-nav-selected-indicator'),
      ),
    );
    final indicatorDecoration = indicator.decoration as BoxDecoration;
    expect(indicatorDecoration.color, isNot(settings.accentColor));
    expect(indicatorDecoration.border, isNotNull);
    expect(indicatorDecoration.boxShadow, isNotEmpty);
    expect(find.text('AiChat'), findsAtLeastNWidgets(1));
    expect(find.text('通讯录'), findsOneWidget);
    expect(find.text('朋友圈'), findsOneWidget);
    expect(find.text('我'), findsOneWidget);

    await tester.tap(find.text('通讯录'));
    await tester.pump();
    expect(find.byKey(const ValueKey('home-floating-nav-indicator')),
        findsOneWidget);
    expect(find.byIcon(Icons.people_rounded), findsOneWidget);
  });
}
