import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:provider/provider.dart';
import '../config/routes.dart';
import '../config/motion.dart';
import '../config/theme.dart';
import '../config/ui_spec.dart';
import '../models/home_chat_entry.dart';
import '../models/character.dart';
import '../providers/chat_provider.dart';
import '../providers/chat_settings_provider.dart';
import '../providers/character_provider.dart';
import '../providers/group_chat_provider.dart';
import '../providers/api_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/auto_moment_provider.dart';
import '../providers/proactive_greeting_provider.dart';
import '../providers/moment_notification_provider.dart';
import '../providers/memory_point_provider.dart';
import '../providers/settings_provider.dart';
import '../services/auto_moment_service.dart';
import '../services/dev_log_service.dart';
import '../services/moment_ai_service.dart';
import '../services/update_service.dart';
import '../widgets/alphabet_index_bar.dart';
import '../widgets/character_avatar.dart';
import '../widgets/update_dialogs.dart';
import 'moments_screen.dart';
import 'profile_screen.dart';
import 'chat_search_screen.dart';
import 'contacts_search_screen.dart';
import 'create_group_screen.dart';
import 'group_chat_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with RouteAware, WidgetsBindingObserver {
  // 主内容横向滑动手势控制：与底部 tab 双向联动
  final PageController _pageController = PageController();
  int _currentTab = 0;
  int? _pressedTab;

  // 通讯录字母导航状态
  final Map<String, GlobalKey> _sectionKeys = {};
  bool _showCharIndexTooltip = false;
  String _currentCharTooltipLetter = '';
  bool _routeSubscribed = false;

  // 会话长按悬浮菜单（Overlay，长按位置旁弹出）
  OverlayEntry? _chatMenuEntry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    context.read<ChatProvider>().init();
    // 角色加载完成后检查朋友圈互动断点：应用中途退出后，从上次未完成的
    // 位置续跑剩余角色的点赞/评论互动（防打断设计）
    final characterProvider = context.read<CharacterProvider>();
    final apiProvider = context.read<ApiProvider>();
    final notificationProvider = context.read<MomentNotificationProvider>();
    final chatProvider = context.read<ChatProvider>();
    final chatSettings = context.read<ChatSettingsProvider>();
    final memoryPointProvider = context.read<MemoryPointProvider>();
    final groupChatProvider = context.read<GroupChatProvider>();
    final user = context.read<AuthProvider>().user;
    // loadCharacters 会同步更新加载状态并通知监听者。延迟到首帧绘制后执行，
    // 避免首帧构建期间触发 Provider rebuild assertion。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      characterProvider.loadCharacters().then((_) {
        if (!mounted) return;
        MomentAiService.resumePending(
          characterProvider: characterProvider,
          apiProvider: apiProvider,
          notificationProvider: notificationProvider,
          chatProvider: chatProvider,
          chatSettings: chatSettings,
          groupChatProvider: groupChatProvider,
          memoryPointProvider: memoryPointProvider,
          user: user,
        );
        _checkAutoMoments();
      }).catchError((Object e) {
        DevLogService.instance.log('朋友圈互动断点恢复失败: $e');
      });
    });
    _cleanupOldApks();
    _checkUpdateOnStartup();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ModalRoute.of 依赖 InheritedWidget，只能在 didChangeDependencies 中调用
    if (!_routeSubscribed) {
      _routeSubscribed = true;
      routeObserver.subscribe(this, ModalRoute.of(context)!);
    }
  }

  @override
  void dispose() {
    _chatMenuEntry?.remove();
    routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 应用回到前台时补发布已到期的自动朋友圈（前台补发布策略）
    if (state == AppLifecycleState.resumed) {
      _checkAutoMoments();
    }
  }

  Future<void> _checkAutoMoments() async {
    if (!mounted) return;
    final characterProvider = context.read<CharacterProvider>();
    if (characterProvider.isLoading) return;
    await AutoMomentService.instance.checkAndPublish(
      characterProvider: characterProvider,
      apiProvider: context.read<ApiProvider>(),
      chatProvider: context.read<ChatProvider>(),
      chatSettings: context.read<ChatSettingsProvider>(),
      groupChatProvider: context.read<GroupChatProvider>(),
      notificationProvider: context.read<MomentNotificationProvider>(),
      autoMomentProvider: context.read<AutoMomentProvider>(),
      memoryPointProvider: context.read<MemoryPointProvider>(),
      user: context.read<AuthProvider>().user,
    );
    // 检查主动问候（不阻塞主流程）
    if (!mounted) return;
    await AutoMomentService.instance.checkProactiveGreeting(
      characterProvider: characterProvider,
      apiProvider: context.read<ApiProvider>(),
      chatProvider: context.read<ChatProvider>(),
      chatSettings: context.read<ChatSettingsProvider>(),
      greetingProvider: context.read<ProactiveGreetingProvider>(),
      memoryPointProvider: context.read<MemoryPointProvider>(),
    );
  }

  /// 主内容滑动结束后同步底部 tab 高亮
  void _onPageChanged(int index) {
    if (_currentTab == index) return;
    setState(() => _currentTab = index);
  }

  /// 底部 tab 点击切换时，同步主内容 PageView：
  /// 相邻页用平滑滑动，跨页（如 0→2）直接跳转无动画，避免长距离滑页。
  void _onTabTap(int index) {
    if (_currentTab == index) return;
    final previous = _currentTab;
    setState(() => _currentTab = index);
    if ((index - previous).abs() == 1) {
      _pageController.animateToPage(
        index,
        duration: AppMotion.tabSelection,
        curve: AppMotion.tabSelectionCurve,
      );
    } else {
      _pageController.jumpToPage(index);
    }
  }

  /// 从聊天等二级页面返回主页时，强制刷新底部导航栏未读角标。
  /// 主页被二级页面覆盖期间，notifyListeners 不会重建外层 Consumer，
  /// 必须在此（主页重新可见时）触发一次重建才能读到最新未读数。
  @override
  void didPopNext() {
    if (mounted) setState(() {});
  }

  /// 启动时自动检测更新（设置中可开关）
  Future<void> _checkUpdateOnStartup() async {
    final settings = context.read<SettingsProvider>();
    if (!settings.autoCheckUpdate) return;
    // 稍作延迟，避免与页面初始化抢占资源
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    final info = await UpdateService.checkForUpdate(
      proxyUrl: settings.updateProxyUrl,
      giteeRepoUrl: settings.updateGiteeRepoUrl,
      githubRepoUrl: settings.updateGitHubRepoUrl,
    );
    if (!mounted || info == null) return;
    showUpdateAvailableDialog(context, info, proxyUrl: settings.updateProxyUrl);
  }

  /// 每次启动兜底清理更新目录中残留的安装包
  Future<void> _cleanupOldApks() async {
    await UpdateService.cleanupDownloadedApks();
  }

  /// 滚动到指定分组标题（对齐顶部）
  void _scrollToSection(String letter) {
    final key = _sectionKeys[letter];
    if (key?.currentContext == null) return;
    Scrollable.ensureVisible(
      key!.currentContext!,
      duration: AppMotion.base,
      curve: AppMotion.soft,
      alignment: 0.0,
    );
  }

  /// 无数据字母就近滚动到下一个有数据的分组
  void _scrollToNearest(String letter, Set<String> availableLetters) {
    if (availableLetters.contains(letter)) {
      _scrollToSection(letter);
      return;
    }
    final letters = ['#', ...'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('')];
    final index = letters.indexOf(letter);
    for (int i = index + 1; i < letters.length; i++) {
      if (availableLetters.contains(letters[i])) {
        _scrollToSection(letters[i]);
        return;
      }
    }
    for (int i = index - 1; i >= 0; i--) {
      if (availableLetters.contains(letters[i])) {
        _scrollToSection(letters[i]);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 朋友圈互动通知未读 → 底部「朋友圈」tab 显示红点
    final momentsUnread = context.watch<MomentNotificationProvider>().hasUnread;
    // 只监听未读数总和：聊天消息内容/排序变化不重建整个首页（4 个 tab + 底部栏），
    // 仅未读数字变化时才重建角标；会话列表自身由 _buildChatList 内的 Consumer 独立刷新。
    return Selector2<ChatProvider, GroupChatProvider, int>(
      selector: (_, chat, group) =>
          chat.conversations.fold<int>(0, (sum, c) => sum + c.unreadCount) +
          group.totalUnreadCount,
      builder: (context, totalUnread, _) {
        final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
        return Stack(
          children: [
            // 主内容：四个导航页，支持触摸横向滑动切换（与底部 tab 联动）。
            // 页面铺满全高，悬浮导航直接覆盖在真实内容上方；各滚动列表
            // 自己预留末尾安全空间，保证最后一项仍能滚到导航上方。
            Positioned.fill(
              child: PageView(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                children: [
                  _buildChatList(),
                  _buildCharacterList(),
                  const MomentsScreen(),
                  const ProfileScreen(),
                ],
              ),
            ),
            Positioned(
              left: UiSpec.floatingHorizontal,
              right: UiSpec.floatingHorizontal,
              bottom: UiSpec.floatingBottomGap + bottomInset,
              child: _buildFloatingTabBar(
                totalUnread: totalUnread,
                momentsUnread: momentsUnread,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFloatingTabBar({
    required int totalUnread,
    required bool momentsUnread,
  }) {
    final tabs = <({IconData icon, IconData activeIcon, String label})>[
      (
        icon: Icons.chat_bubble_outline_rounded,
        activeIcon: Icons.chat_bubble_rounded,
        label: 'AiChat',
      ),
      (
        icon: Icons.people_outline_rounded,
        activeIcon: Icons.people_rounded,
        label: '通讯录',
      ),
      (
        icon: Icons.photo_camera_outlined,
        activeIcon: Icons.photo_camera_rounded,
        label: '朋友圈',
      ),
      (
        icon: Icons.person_outline_rounded,
        activeIcon: Icons.person_rounded,
        label: '我',
      ),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(UiSpec.floatingNavHeight / 2),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: UiSpec.floatingNavBlurSigma,
          sigmaY: UiSpec.floatingNavBlurSigma,
        ),
        child: Container(
          key: const ValueKey('home-floating-nav'),
          height: UiSpec.floatingNavHeight,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            // Use the elevated surface as a translucent tint so page content
            // remains visible through the glass layer in both color schemes.
            color: context.surfaceColor.withValues(
              alpha: context.isDark
                  ? UiSpec.floatingNavDarkOpacity
                  : UiSpec.floatingNavLightOpacity,
            ),
            borderRadius: BorderRadius.circular(UiSpec.floatingNavHeight / 2),
            border: Border.all(
              color: context.outlineColor.withValues(alpha: 0.42),
              width: 0.6,
            ),
            boxShadow: [
              BoxShadow(
                color: CupertinoColors.black.withValues(
                  alpha: context.isDark ? 0.28 : 0.12,
                ),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth / tabs.length;
              return Stack(
                children: [
                  AnimatedPositioned(
                    key: const ValueKey('home-floating-nav-indicator'),
                    duration: AppMotion.tabSelection,
                    curve: AppMotion.tabSelectionCurve,
                    left: itemWidth * _currentTab + 4,
                    top: 4,
                    bottom: 4,
                    width: itemWidth - 8,
                    child: DecoratedBox(
                      key: const ValueKey(
                        'home-floating-nav-selected-indicator',
                      ),
                      decoration: BoxDecoration(
                        color: context.fieldBgColor.withValues(
                          alpha: context.isDark
                              ? UiSpec.floatingSelectedSurfaceDarkOpacity
                              : UiSpec.floatingSelectedSurfaceLightOpacity,
                        ),
                        borderRadius: BorderRadius.circular(
                          UiSpec.floatingIndicatorRadius,
                        ),
                        border: Border.all(
                          color: context.accentColor.withValues(
                            alpha: context.isDark
                                ? UiSpec.floatingSelectedBorderDarkOpacity
                                : UiSpec.floatingSelectedBorderLightOpacity,
                          ),
                          width: 0.7,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: CupertinoColors.black.withValues(
                              alpha: context.isDark
                                  ? UiSpec.floatingSelectedShadowDarkOpacity
                                  : UiSpec.floatingSelectedShadowLightOpacity,
                            ),
                            blurRadius: UiSpec.floatingSelectedShadowBlur,
                            offset: UiSpec.floatingSelectedShadowOffset,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var index = 0; index < tabs.length; index++)
                        Expanded(
                          child: _buildFloatingTab(
                            index: index,
                            icon: tabs[index].icon,
                            activeIcon: tabs[index].activeIcon,
                            label: tabs[index].label,
                            totalUnread: totalUnread,
                            momentsUnread: momentsUnread,
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingTab({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int totalUnread,
    required bool momentsUnread,
  }) {
    final selected = _currentTab == index;
    final badge = index == 0 && totalUnread > 0;
    final momentBadge = index == 2 && momentsUnread;
    return Listener(
      onPointerDown: (_) => setState(() => _pressedTab = index),
      onPointerUp: (_) => setState(() => _pressedTab = null),
      onPointerCancel: (_) => setState(() => _pressedTab = null),
      child: AnimatedScale(
        scale: _pressedTab == index ? AppMotion.pressScale : 1,
        duration: AppMotion.micro,
        curve: AppMotion.out,
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => _onTabTap(index),
          child: SizedBox(
            height: UiSpec.floatingNavHeight - 8,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedSwitcher(
                        duration: AppMotion.tabIconFade,
                        switchInCurve: AppMotion.tabSelectionCurve,
                        switchOutCurve: AppMotion.exit,
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: ScaleTransition(
                              scale: Tween<double>(begin: 0.88, end: 1).animate(
                                animation,
                              ),
                              child: child,
                            ),
                          );
                        },
                        child: Icon(
                          selected ? activeIcon : icon,
                          key: ValueKey(selected),
                          size: selected ? 22 : 21,
                          color: selected
                              ? context.accentColor
                              : context.textSecondaryColor,
                        ),
                      ),
                      if (badge)
                        Positioned(
                          right: -10,
                          top: -6,
                          child: _buildUnreadBadge(
                            totalUnread,
                            context.surfaceColor,
                          ),
                        ),
                      if (momentBadge)
                        Positioned(
                          right: -7,
                          top: -6,
                          child: Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: CupertinoColors.systemRed,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: context.surfaceColor,
                                width: 1.2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  AnimatedDefaultTextStyle(
                    duration: AppMotion.tabIconFade,
                    curve: AppMotion.tabSelectionCurve,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected
                          ? context.accentColor
                          : context.textSecondaryColor,
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  double _floatingContentBottomInset(BuildContext context) {
    return UiSpec.floatingContentBottomInset +
        MediaQuery.viewPaddingOf(context).bottom;
  }

  Widget _buildChatList() {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('AiChat'),
        // 右上角：搜索 + 加号（加号用于创建群聊）
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () {
                Navigator.push(
                  context,
                  CupertinoPageRoute(builder: (_) => const ChatSearchScreen()),
                );
              },
              child: const Icon(CupertinoIcons.search),
            ),
            const SizedBox(width: 8),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _openCreateGroup,
              child: const Icon(CupertinoIcons.add),
            ),
          ],
        ),
      ),
      child: Consumer2<ChatProvider, GroupChatProvider>(
        builder: (context, chatProvider, groupProvider, _) {
          final entries = _buildChatEntries(chatProvider, groupProvider);
          if (entries.isEmpty) {
            return Center(
              child: Text(
                '暂无会话',
                style: TextStyle(
                  fontSize: 16,
                  color: context.textSecondaryColor,
                ),
              ),
            );
          }

          return Container(
            color: context.scaffoldColor,
            child: ListView.separated(
              padding: EdgeInsets.only(
                // CupertinoPageScaffold exposes the translucent navigation
                // bar overlap through MediaQuery.padding.top. Keep the first
                // row below that area so it remains reachable and visible at
                // the top of the list.
                top: MediaQuery.paddingOf(context).top + UiSpec.spaceSm,
                bottom: _floatingContentBottomInset(context),
              ),
              itemCount: entries.length,
              separatorBuilder: (_, __) => Container(
                height: 0.5,
                margin: const EdgeInsets.only(left: 76),
                color: context.conversationDividerColor,
              ),
              itemBuilder: (context, index) {
                final entry = entries[index];
                return GestureDetector(
                  // 长按会话：在长按位置旁弹出悬浮菜单（置顶/取消置顶）
                  onLongPressStart: (details) => _showEntryMenu(
                    context,
                    details.globalPosition,
                    entry,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: UiSpec.conversationRowHeight,
                    ),
                    child: CupertinoListTile(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      // 置顶会话背景变灰，区分普通会话
                      backgroundColor:
                          entry.pinned ? context.pinnedChatColor : null,
                      // CupertinoListTile 默认把 leading 约束在 28×28，
                      // 必须显式指定与头像一致的尺寸，否则头像被压缩
                      leadingSize: UiSpec.conversationAvatar,
                      leading: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          _buildSquareAvatar(
                            context,
                            entry.title,
                            entry.avatar,
                            fallbackIcon: entry.isGroup
                                ? CupertinoIcons.person_3_fill
                                : CupertinoIcons.person_fill,
                          ),
                          // 未读消息数字角标（私聊与群聊统一展示）
                          if (entry.unreadCount > 0)
                            Positioned(
                              right: -8,
                              top: -6,
                              child: _buildUnreadBadge(
                                entry.unreadCount,
                                context.scaffoldColor,
                              ),
                            ),
                        ],
                      ),
                      title: Text(
                        entry.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: context.textPrimaryColor,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          entry.lastMessage.isEmpty
                              ? '开始对话...'
                              : entry.lastMessage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.25,
                            color: context.textSecondaryColor,
                          ),
                        ),
                      ),
                      trailing: Text(
                        _formatTime(entry.lastMessageTime),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: context.textSecondaryColor,
                        ),
                      ),
                      onTap: () => _openChatEntry(entry),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  /// 合并私聊与会话为统一会话列表：置顶优先，其余按最近消息时间倒序
  List<HomeChatEntry> _buildChatEntries(
    ChatProvider chatProvider,
    GroupChatProvider groupProvider,
  ) {
    final entries = <HomeChatEntry>[
      for (final c in chatProvider.conversations)
        HomeChatEntry(
          isGroup: false,
          id: c.id,
          title: c.characterName,
          avatar: c.characterAvatar,
          lastMessage: c.lastMessage,
          lastMessageTime: c.lastMessageTime,
          pinned: c.pinned,
          unreadCount: c.unreadCount,
        ),
      for (final g in groupProvider.groups)
        HomeChatEntry(
          isGroup: true,
          id: g.id,
          title: '${g.name}（${g.memberCount}）',
          avatar: g.avatar,
          lastMessage: g.lastMessage,
          lastMessageTime: g.lastMessageTime,
          pinned: g.pinned,
          unreadCount: g.unreadCount,
        ),
    ];
    entries.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.lastMessageTime.compareTo(a.lastMessageTime);
    });
    return entries;
  }

  void _openCreateGroup() {
    Navigator.push(
      context,
      CupertinoPageRoute(builder: (_) => const CreateGroupScreen()),
    );
  }

  void _openChatEntry(HomeChatEntry entry) {
    if (entry.isGroup) {
      Navigator.push(
        context,
        CupertinoPageRoute(
          builder: (_) => GroupChatScreen(groupId: entry.id),
        ),
      );
      return;
    }
    Navigator.pushNamed(
      context,
      AppRoutes.chat,
      arguments: {
        'conversationId': entry.id,
        'characterName': entry.title,
        'characterAvatar': entry.avatar,
      },
    );
  }

  Widget _buildCharacterList() {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('通讯录'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () {
            Navigator.push(
              context,
              CupertinoPageRoute(
                builder: (_) => const ContactsSearchScreen(),
              ),
            );
          },
          child: const Icon(CupertinoIcons.search),
        ),
      ),
      child: Consumer<CharacterProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CupertinoActivityIndicator());
          }

          final self = provider.selfCharacter;
          if (provider.manageableCharacters.isEmpty && self == null) {
            return Center(
              child: Text(
                '暂无可用角色',
                style: TextStyle(color: context.textSecondaryColor),
              ),
            );
          }

          // 按拼音首字母分组排序（类似手机通讯录，排除固定的"自己"）
          final groups = provider.sortedCharactersGrouped
              .map((g) => MapEntry(
                    g.key,
                    g.value
                        .where((c) => c.id != CharacterProvider.selfCharacterId)
                        .toList(),
                  ))
              .where((g) => g.value.isNotEmpty)
              .toList();
          final availableLetters = groups.map((g) => g.key).toSet();
          for (final group in groups) {
            _sectionKeys.putIfAbsent(group.key, () => GlobalKey());
          }

          return Stack(
            children: [
              // 主列表（普通 ListView 一次性构建，GlobalKey 定位有效）
              Container(
                color: context.scaffoldColor,
                child: ListView(
                  padding: EdgeInsets.only(
                    right: 28,
                    bottom: _floatingContentBottomInset(context),
                  ),
                  children: [
                    // 顶部固定的"自己"账号：不能发起聊天，进入自己的空间页
                    if (self != null) ...[
                      _buildSelfTile(context, self),
                      Container(
                        height: 0.5,
                        margin: const EdgeInsets.only(left: 76),
                        color: context.separatorColor.withValues(alpha: 0.62),
                      ),
                    ],
                    for (final group in groups) ...[
                      // 字母标题
                      Container(
                        key: _sectionKeys[group.key],
                        width: double.infinity,
                        color: context.scaffoldColor,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Text(
                          group.key,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: context.textSecondaryColor,
                          ),
                        ),
                      ),
                      for (final character in group.value)
                        CupertinoListTile(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          // 同消息列表：显式放宽 leading 尺寸约束
                          leadingSize: UiSpec.conversationAvatar,
                          leading: _buildSquareAvatar(
                            context,
                            character.displayName,
                            character.avatar,
                          ),
                          title: Text(
                            _contactName(character),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: context.textPrimaryColor,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              character.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.3,
                                color: context.textSecondaryColor,
                              ),
                            ),
                          ),
                          trailing: Icon(
                            CupertinoIcons.chevron_right,
                            size: 16,
                            color: context.textSecondaryColor,
                          ),
                          onTap: () {
                            Navigator.pushNamed(
                              context,
                              AppRoutes.characterDetail,
                              arguments: character.id,
                            );
                          },
                        ),
                      Container(
                        height: 0.5,
                        margin: const EdgeInsets.only(left: 76),
                        color: context.separatorColor.withValues(alpha: 0.62),
                      ),
                    ],
                  ],
                ),
              ),
              // 右侧字母索引栏
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: AlphabetIndexBar(
                  availableLetters: availableLetters,
                  onLetterChanged: (letter) {
                    setState(() {
                      _showCharIndexTooltip = true;
                      _currentCharTooltipLetter = letter;
                    });
                    _scrollToNearest(letter, availableLetters);
                  },
                  onDragEnd: () {
                    setState(() {
                      _showCharIndexTooltip = false;
                    });
                  },
                ),
              ),
              // 字母提示气泡
              if (_showCharIndexTooltip)
                Positioned(
                  right: 48,
                  top: MediaQuery.of(context).size.height / 2 - 32,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: context.accentColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _currentCharTooltipLetter,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: CupertinoColors.white,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// 通讯录显示名：有备注时显示「备注（昵称）」，无备注仅显示昵称
  String _contactName(Character character) {
    final remark = character.remark.trim();
    if (remark.isEmpty) return character.name;
    return '$remark（${character.name}）';
  }

  /// 通讯录顶部的"自己"账号条目：不能发起聊天，点击进入自己的空间页查看/发布朋友圈
  Widget _buildSelfTile(BuildContext context, Character self) {
    return CupertinoListTile(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      // 同消息列表：显式放宽 leading 尺寸约束
      leadingSize: UiSpec.conversationAvatar,
      leading: _buildSquareAvatar(context, self.displayName, self.avatar),
      title: Text(
        _contactName(self),
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: context.textPrimaryColor,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          self.signature.isEmpty ? '我的朋友圈' : self.signature,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            color: context.textSecondaryColor,
          ),
        ),
      ),
      trailing: Icon(
        CupertinoIcons.chevron_right,
        size: 16,
        color: context.textSecondaryColor,
      ),
      onTap: () {
        Navigator.pushNamed(
          context,
          AppRoutes.characterDetail,
          arguments: CharacterProvider.selfCharacterId,
        );
      },
    );
  }

  /// 未读消息数字角标（>=100 显示 99+，宽度随数字自适应）
  Widget _buildUnreadBadge(int count, Color borderColor) {
    final text = count >= 100 ? '99+' : '$count';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      decoration: BoxDecoration(
        color: CupertinoColors.systemRed,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          color: CupertinoColors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildSquareAvatar(
    BuildContext context,
    String name,
    String avatar, {
    IconData fallbackIcon = CupertinoIcons.person_fill,
    double size = UiSpec.conversationAvatar,
  }) {
    // 头像框样式跟随全局设置（方形 / 仿 QQ 圆形）
    return CharacterAvatar(
      base64: avatar,
      size: size,
      fallbackIcon: fallbackIcon,
    );
  }

  /// 长按会话弹出悬浮菜单（在长按位置旁），提供【置顶聊天】/【取消置顶】
  void _showEntryMenu(
    BuildContext context,
    Offset globalPos,
    HomeChatEntry entry,
  ) {
    _dismissChatMenu();
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (overlayBox == null) return;

    const panelWidth = 160.0;
    const panelHeight = 44.0;
    // 菜单尽量保持在屏幕内（留 8px 边距）
    var left = globalPos.dx;
    if (left + panelWidth > overlayBox.size.width - 8) {
      left = overlayBox.size.width - panelWidth - 8;
    }
    var top = globalPos.dy;
    if (top + panelHeight > overlayBox.size.height - 8) {
      top = overlayBox.size.height - panelHeight - 8;
    }

    final pinned = entry.pinned;
    _chatMenuEntry = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          // 透明遮罩：点击其他区域关闭菜单
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _dismissChatMenu,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            child: Container(
              width: panelWidth,
              decoration: BoxDecoration(
                color: context.listBgColor,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: CupertinoColors.black.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: _chatMenuItem(
                icon: pinned ? CupertinoIcons.pin_slash : CupertinoIcons.pin,
                label: pinned ? '取消置顶' : '置顶聊天',
                onTap: () {
                  _dismissChatMenu();
                  if (entry.isGroup) {
                    context.read<GroupChatProvider>().setPinned(
                          entry.id,
                          !pinned,
                        );
                  } else {
                    context.read<ChatProvider>().setPinned(
                          entry.id,
                          !pinned,
                        );
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_chatMenuEntry!);
  }

  void _dismissChatMenu() {
    _chatMenuEntry?.remove();
    _chatMenuEntry = null;
  }

  /// 悬浮菜单单项样式（图标 + 文字，高亮色图标）
  Widget _chatMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: context.textSecondaryColor),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                color: context.textPrimaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inDays > 0) return '${diff.inDays}天前';
    if (diff.inHours > 0) return '${diff.inHours}小时前';
    if (diff.inMinutes > 0) return '${diff.inMinutes}分钟前';
    return '刚刚';
  }
}

/// 首页会话列表统一条目：私聊与群聊混排使用同一份数据快照
