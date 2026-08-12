import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'config/theme.dart';
import 'config/routes.dart';
import 'providers/api_provider.dart';
import 'providers/chat_settings_provider.dart';
import 'providers/moment_notification_provider.dart';
import 'providers/settings_provider.dart';
import 'services/notification_service.dart';
import 'utils/app_toast.dart';

class AiChatApp extends StatefulWidget {
  const AiChatApp({super.key});

  @override
  State<AiChatApp> createState() => _AiChatAppState();
}

class _AiChatAppState extends State<AiChatApp> {
  @override
  void initState() {
    super.initState();
    context.read<SettingsProvider>().init();
    context.read<ApiProvider>().init();
    context.read<ChatSettingsProvider>().init();
    context.read<MomentNotificationProvider>().init();
    // 初始化系统通知（创建渠道并请求 Android 13+ 通知权限）
    NotificationService.instance.init();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        return CupertinoApp(
          title: 'AiChat',
          debugShowCheckedModeBanner: false,
          // 全局根 navigator key：后台任务（朋友圈 AI 互动等）弹 Toast / 弹窗用
          navigatorKey: appNavigatorKey,
          theme: AppTheme.buildTheme(
            brightness: Brightness.light,
            accent: settings.accentColor,
          ),
          // 在此动态解析明暗模式并注入主题（支持跟随系统）
          builder: (context, child) {
            final brightness = settings.resolveBrightness(
              MediaQuery.platformBrightnessOf(context),
            );
            return CupertinoTheme(
              data: AppTheme.buildTheme(
                brightness: brightness,
                accent: settings.accentColor,
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          initialRoute: AppRoutes.splash,
          onGenerateRoute: AppRoutes.generateRoute,
          navigatorObservers: [routeObserver],
        );
      },
    );
  }
}
