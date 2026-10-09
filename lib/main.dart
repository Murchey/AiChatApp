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
import 'providers/story_provider.dart';
import 'providers/backend_provider.dart';
import 'providers/sync_provider.dart';
import 'services/storage_migration_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 存储迁移：首次启动把角色/会话/消息从 SharedPreferences 导入 SQLite
  // （成功后打标跳过；旧数据保留）。失败不阻塞启动。
  try {
    await StorageMigrationService.init();
  } catch (e) {
    debugPrint('[main] StorageMigrationService.init 失败: $e');
  }
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
        ChangeNotifierProvider(create: (_) => BackendProvider()),
        ChangeNotifierProvider(
            create: (context) => SyncProvider(
                  backend: context.read<BackendProvider>(),
                  settings: context.read<SettingsProvider>(),
                )),
        ChangeNotifierProxyProvider<BackendProvider, StoryProvider>(
          create: (context) =>
              StoryProvider(backend: context.read<BackendProvider>()),
          update: (context, backend, previous) =>
              previous ?? StoryProvider(backend: backend),
        ),
        ChangeNotifierProvider(create: (_) => StickerProvider()),
        ChangeNotifierProvider.value(value: TokenUsageProvider.instance),
      ],
      child: const AiChatApp(),
    ),
  );
}
