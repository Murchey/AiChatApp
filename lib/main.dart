import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'providers/api_provider.dart';
import 'providers/sticker_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/auto_moment_provider.dart';
import 'providers/chat_background_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/chat_settings_provider.dart';
import 'providers/character_provider.dart';
import 'providers/group_chat_provider.dart';
import 'providers/memory_point_provider.dart';
import 'providers/moment_notification_provider.dart';
import 'providers/proactive_greeting_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/token_usage_provider.dart';
import 'providers/workshop_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 自定义开屏依赖本地图片路径。必须在首帧前完成读取，避免先绘制默认
  // Logo、随后异步切换成自定义图片而产生闪现。
  final settingsProvider = SettingsProvider();
  await settingsProvider.init();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsProvider),
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
      child: const AiChatApp(),
    ),
  );
}
