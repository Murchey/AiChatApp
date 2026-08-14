import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:provider/provider.dart';
import '../config/routes.dart';
import '../config/theme.dart';
import '../models/character.dart';
import '../models/conversation.dart';
import '../providers/chat_provider.dart';
import '../providers/chat_settings_provider.dart';
import '../providers/character_provider.dart';
import '../providers/auto_moment_provider.dart';
import '../providers/api_provider.dart';
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
    characterProvider.loadCharacters().then((_) {
      MomentAiService.resumePending(
        characterProvider: characterProvider,
        apiProvider: apiProvider,
        notificationProvider: notificationProvider,
        chatProvider: chatProvider,
        chatSettings: chatSettings,
        memoryPointProvider: memoryPointProvider,
      );
      _checkAutoMoments();
    }).catchError((Object e) {
      DevLogService.instance.log('朋友圈互动断点恢复失败: $e');
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
      notificationProvider: context.read<MomentNotificationProvider>(),
      autoMomentProvider: context.read<AutoMomentProvider>(),
      memoryPointProvider: context.read<MemoryPointProvider>(),
    );
  }

  /// 主内容滑动结束后同步底部 tab 高亮
  void _onPageChanged(int index) {
    if (_currentTab == index) return;
    setState(() => _currentTab = index);
  }

  /// 底部 tab 点击切换时，同步滑动主内容 PageView
  void _onTabTap(int index) {
    if (_currentTab == index) return;
    setState(() => _currentTab = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
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
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
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
    final momentsUnread =
        context.watch<MomentNotificationProvider>().hasUnread;
    // 只监听未读数总和：聊天消息内容/排序变化不重建整个首页（4 个 tab + 底部栏），
    // 仅未读数字变化时才重建角标；会话列表自身由 _buildChatList 内的 Consumer 独立刷新。
    return Selector<ChatProvider, int>(
      selector: (_, p) =>
          p.conversations.fold<int>(0, (sum, c) => sum + c.unreadCount),
      builder: (context, totalUnread, _) {
        return Column(
          children: [
            // 主内容：四个导航页，支持触摸横向滑动切换（与底部 tab 联动）
            Expanded(
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
            CupertinoTabBar(
              currentIndex: _currentTab,
              onTap: _onTabTap,
              backgroundColor: context.navBarColor,
              activeColor: context.accentColor,
              inactiveColor: context.textSecondaryColor,
              border: Border(
                top: BorderSide(color: context.separatorColor, width: 0.5),
              ),
              items: [
                BottomNavigationBarItem(
                  icon: _buildTabIcon(
                    Icons.chat_bubble_outline_rounded,
                    totalUnread,
                  ),
                  activeIcon: _buildTabIcon(
                    Icons.chat_bubble_rounded,
                    totalUnread,
                  ),
                  label: 'AiChat',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.people_outline_rounded),
                  activeIcon: Icon(Icons.people_rounded),
                  label: '通讯录',
                ),
                BottomNavigationBarItem(
                  icon: _buildMomentsTabIcon(
                    momentsUnread,
                    Icons.photo_camera_rounded,
                  ),
                  activeIcon: _buildMomentsTabIcon(
                    momentsUnread,
                    Icons.photo_camera_rounded,
                  ),
                  label: '朋友圈',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.person_outline_rounded),
                  activeIcon: Icon(Icons.person_rounded),
                  label: '我',
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildChatList() {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('AiChat'),
        // 右上角搜索：进入全局聊天记录搜索页
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () {
            Navigator.push(
              context,
              CupertinoPageRoute(builder: (_) => const ChatSearchScreen()),
            );
          },
          child: const Icon(CupertinoIcons.search),
        ),
      ),
      child: Consumer<ChatProvider>(
        builder: (context, chatProvider, _) {
          if (chatProvider.conversations.isEmpty) {
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
              itemCount: chatProvider.conversations.length,
              separatorBuilder: (_, __) => Container(
                height: 0.5,
                margin: const EdgeInsets.only(left: 57),
                color: context.separatorColor,
              ),
              itemBuilder: (context, index) {
                final conversation = chatProvider.conversations[index];
                return GestureDetector(
                  // 长按会话：在长按位置旁弹出悬浮菜单（置顶/取消置顶）
                  onLongPressStart: (details) => _showChatMenu(
                    context,
                    details.globalPosition,
                    conversation,
                  ),
                  child: CupertinoListTile(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    // 置顶会话背景变灰，区分普通会话
                    backgroundColor: conversation.pinned
                        ? context.pinnedChatColor
                        : null,
                    // CupertinoListTile 默认把 leading 约束在 28×28，
                    // 必须显式指定与头像一致的尺寸，否则头像被压缩
                    leadingSize: 45,
                    leading: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _buildSquareAvatar(
                          context,
                          conversation.characterName,
                          conversation.characterAvatar,
                        ),
                        // 未读消息数字角标（退出聊天界面期间角色发来的新消息）
                        if (conversation.unreadCount > 0)
                          Positioned(
                            right: -8,
                            top: -6,
                            child: _buildUnreadBadge(
                              conversation.unreadCount,
                              context.scaffoldColor,
                            ),
                          ),
                      ],
                    ),
                    title: Text(
                      conversation.characterName,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        color: context.textPrimaryColor,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        conversation.lastMessage.isEmpty
                            ? '开始对话...'
                            : conversation.lastMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: context.textSecondaryColor,
                        ),
                      ),
                    ),
                    trailing: Text(
                      _formatTime(conversation.lastMessageTime),
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondaryColor,
                      ),
                    ),
                    onTap: () {
                      Navigator.pushNamed(
                        context,
                        AppRoutes.chat,
                        arguments: {
                          'conversationId': conversation.id,
                          'characterName': conversation.characterName,
                          'characterAvatar': conversation.characterAvatar,
                        },
                      );
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildCharacterList() {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('通讯录'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () {},
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
                  padding: const EdgeInsets.only(right: 28),
                  children: [
                    // 顶部固定的"自己"账号：不能发起聊天，进入自己的空间页
                    if (self != null) ...[
                      _buildSelfTile(context, self),
                      Container(
                        height: 0.5,
                        margin: const EdgeInsets.only(left: 61),
                        color: context.separatorColor,
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
                            vertical: 10,
                          ),
                          // 同消息列表：显式放宽 leading 尺寸约束
                          leadingSize: 45,
                          leading: _buildSquareAvatar(
                            context,
                            character.displayName,
                            character.avatar,
                          ),
                          title: Text(
                            _contactName(character),
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                              color: context.textPrimaryColor,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              character.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.4,
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
                        margin: const EdgeInsets.only(left: 61),
                        color: context.separatorColor,
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      // 同消息列表：显式放宽 leading 尺寸约束
      leadingSize: 45,
      leading: _buildSquareAvatar(context, self.displayName, self.avatar),
      title: Text(
        _contactName(self),
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w500,
          color: context.textPrimaryColor,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          self.signature.isEmpty ? '我的朋友圈' : self.signature,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
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

  /// 底部导航栏图标：右上角带未读数字角标
  Widget _buildTabIcon(IconData icon, int totalUnread) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (totalUnread > 0)
          Positioned(
            right: -10,
            top: -6,
            child: _buildUnreadBadge(totalUnread, context.scaffoldColor),
          ),
      ],
    );
  }

  /// 朋友圈 tab 图标：存在未读互动通知时右上角显示红点
  Widget _buildMomentsTabIcon(bool hasUnread, IconData icon) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (hasUnread)
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
                  color: context.navBarColor,
                  width: 1.2,
                ),
              ),
            ),
          ),
      ],
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

  Widget _buildSquareAvatar(BuildContext context, String name, String avatar) {
    // 头像框样式跟随全局设置（方形 / 仿 QQ 圆形）
    return CharacterAvatar(base64: avatar, size: 45);
  }

  /// 长按会话弹出悬浮菜单（在长按位置旁），提供【置顶聊天】/【取消置顶】
  void _showChatMenu(
    BuildContext context,
    Offset globalPos,
    Conversation conversation,
  ) {
    _dismissChatMenu();
    final overlay = Overlay.of(context);
    final overlayBox =
        overlay.context.findRenderObject() as RenderBox?;
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

    final pinned = conversation.pinned;
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
                    color: const Color(0xFF000000).withValues(alpha: 0.3),
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
                  context.read<ChatProvider>().setPinned(
                        conversation.id,
                        !pinned,
                      );
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
            Icon(icon, size: 18, color: context.accentColor),
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
