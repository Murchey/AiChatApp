import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import 'package:provider/provider.dart';
import 'config/theme.dart';
import 'config/routes.dart';
import 'providers/auto_moment_provider.dart';
import 'providers/proactive_greeting_provider.dart';
import 'providers/api_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/chat_settings_provider.dart';
import 'providers/group_chat_provider.dart';
import 'providers/memory_point_provider.dart';
import 'providers/moment_notification_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/token_usage_provider.dart';
import 'providers/workshop_provider.dart';
import 'providers/story_provider.dart';
import 'providers/sticker_provider.dart';
import 'services/backup_schedule_service.dart';
import 'services/notification_service.dart';
import 'services/widget_sync_service.dart';
import 'utils/app_toast.dart';
import 'utils/platform_support.dart';
import 'widgets/update_dialogs.dart';
import 'screens/desktop/desktop_theme.dart' show kDesktopFontFallback;

class AiChatApp extends StatefulWidget {
  const AiChatApp({super.key});

  @override
  State<AiChatApp> createState() => _AiChatAppState();
}

class _AiChatAppState extends State<AiChatApp> {
  static const _navChannel = MethodChannel('com.aichat.ai_chat/navigation');

  @override
  void initState() {
    super.initState();
    _initProviders();
    context.read<GroupChatProvider>().init();
    context.read<MomentNotificationProvider>().init();
    context.read<MemoryPointProvider>().init();
    context.read<AutoMomentProvider>().init();
    context.read<ProactiveGreetingProvider>().init();
    context.read<WorkshopProvider>().init();
    context.read<StoryProvider>().init();
    context.read<StickerProvider>().init();
    // 预加载累计 tokens 统计：数据就绪后再进入统计页，避免显示"清零"假象
    context.read<TokenUsageProvider>().init();
    // 初始化系统通知（创建渠道并请求 Android 13+ 通知权限）
    NotificationService.instance.init();
    // 检查仓库更新通知
    _checkWorkshopUpdates();
    // 定时备份：打开 APP 时检查本地/云端是否到期
    _runScheduledBackups();
    // 监听小组件导航
    _setupNavigationHandler();
    // 初始化时同步数据到小组件
    _syncWidgetData();
  }

  /// 先加载 API 与聊天设置；仅有一个模型且未选聊天模型时自动选中，
  /// 免去用户手动到「聊天设置」里点一次。
  Future<void> _initProviders() async {
    final api = context.read<ApiProvider>();
    final settings = context.read<ChatSettingsProvider>();
    await Future.wait([api.init(), settings.init()]);
    if (!mounted) return;
    await settings
        .ensureSoleModelSelected(api.models.map((m) => m.id).toList());
  }

  /// 打开 APP 时执行到期的自动备份（延迟，等 Provider 加载完再打包）
  void _runScheduledBackups() {
    Future.delayed(const Duration(seconds: 3), () async {
      if (!mounted) return;
      try {
        final messages = await BackupScheduleService.checkAndRunOnAppOpen();
        if (!mounted || messages.isEmpty) return;
        showAppToast(messages.join('；'));
      } catch (e) {
        debugPrint('[BackupSchedule] check on app open failed: $e');
      }
    });
  }

  void _syncWidgetData() {
    Future.delayed(const Duration(seconds: 2), () async {
      if (!mounted) return;
      try {
        // 保存需要的数据引用
        final tokenProvider = context.read<TokenUsageProvider>();
        final chatProvider = context.read<ChatProvider>();

        // 同步 Token 数据
        final allUsages = tokenProvider.allUsages;
        int privateChat = 0, groupChat = 0, moment = 0;
        allUsages.forEach((id, usage) {
          if (id == TokenUsageProvider.kMomentUsageId) {
            moment = usage.totalTokens;
          } else if (id.startsWith('group_')) {
            groupChat += usage.totalTokens;
          } else {
            privateChat += usage.totalTokens;
          }
        });

        await WidgetSyncService.syncTokenUsage(
          total: tokenProvider.total,
          sent: tokenProvider.sentTotal,
          received: tokenProvider.receivedTotal,
          privateChat: privateChat,
          groupChat: groupChat,
          moment: moment,
        );

        // 同步会话数据
        final convList = chatProvider.conversations
            .map((conv) => {
                  'id': conv.id,
                  'character_id': conv.characterId,
                  'character_name': conv.characterName,
                  'last_message': conv.lastMessage,
                  'last_message_time':
                      conv.lastMessageTime.millisecondsSinceEpoch,
                  'unread_count': conv.unreadCount,
                  'pinned': conv.pinned,
                })
            .toList();

        await WidgetSyncService.syncConversations(convList);

        debugPrint('[App] Widget data synced on startup');
      } catch (e) {
        debugPrint('[App] Widget sync failed: $e');
      }
    });
  }

  void _setupNavigationHandler() {
    _navChannel.setMethodCallHandler((call) async {
      if (call.method == 'openChat') {
        final conversationId = call.arguments as String?;
        if (conversationId != null && mounted) {
          // 延迟导航，等待页面加载完成
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) {
            appNavigatorKey.currentState?.pushNamed(
              '/chat',
              arguments: conversationId,
            );
          }
        }
      }
    });
  }

  Future<void> _checkWorkshopUpdates() async {
    // 等待 WorkshopProvider 初始化完成
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final workshopProvider = context.read<WorkshopProvider>();
    final updateBody = await workshopProvider.checkForUpdates();
    if (updateBody != null && mounted) {
      // 显示更新通知
      _showUpdateNotification(updateBody);
    }
  }

  void _showUpdateNotification(String body) {
    final navContext = appNavigatorKey.currentContext;
    if (navContext == null) return;
    showMarkdownUpdatePanel(
      navContext,
      title: '角色仓库有更新',
      body: body,
      footer: '可在「创意工坊设置」中管理通知',
    );
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
            fontFamily: PlatformSupport.isDesktop ? 'Segoe UI' : null,
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
                fontFamily: PlatformSupport.isDesktop ? 'Segoe UI' : null,
              ),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  fontFamily: PlatformSupport.isDesktop ? 'Segoe UI' : null,
                  fontFamilyFallback:
                      PlatformSupport.isDesktop ? kDesktopFontFallback : null,
                ),
                child: child ?? const SizedBox.shrink(),
              ),
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
