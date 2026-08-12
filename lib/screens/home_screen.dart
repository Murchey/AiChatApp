import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/routes.dart';
import '../config/theme.dart';
import '../providers/chat_provider.dart';
import '../providers/character_provider.dart';
import '../providers/settings_provider.dart';
import '../services/update_service.dart';
import '../widgets/alphabet_index_bar.dart';
import '../widgets/update_dialogs.dart';
import 'profile_screen.dart';

/// base64 头像解码缓存：同一个 base64 只解码一次，并复用同一个 [MemoryImage]。
/// 若每次 build 都新建 [MemoryImage]，图片缓存键会随之改变（Dart 的 List ==
/// 是引用比较），导致 ImageCache 永不命中、反复解码，进出聊天界面时头像频闪。
final Map<String, MemoryImage> _avatarImageCache = {};

MemoryImage _cachedAvatarImage(String base64) {
  return _avatarImageCache.putIfAbsent(
    base64,
    () {
      if (_avatarImageCache.length > 64) _avatarImageCache.clear();
      return MemoryImage(base64Decode(base64));
    },
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with RouteAware {
  final CupertinoTabController _tabController = CupertinoTabController();

  // 通讯录字母导航状态
  final Map<String, GlobalKey> _sectionKeys = {};
  bool _showCharIndexTooltip = false;
  String _currentCharTooltipLetter = '';
  bool _routeSubscribed = false;

  @override
  void initState() {
    super.initState();
    context.read<ChatProvider>().init();
    context.read<CharacterProvider>().loadCharacters();
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
    routeObserver.unsubscribe(this);
    _tabController.dispose();
    super.dispose();
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
    // 监听未读数变化，驱动底部导航栏角标刷新
    return Consumer<ChatProvider>(
      builder: (context, chatProvider, _) {
        final totalUnread = chatProvider.conversations.fold<int>(
          0,
          (sum, c) => sum + c.unreadCount,
        );
        return CupertinoTabScaffold(
          controller: _tabController,
          tabBar: CupertinoTabBar(
            backgroundColor: context.navBarColor,
            activeColor: context.accentColor,
            inactiveColor: context.textSecondaryColor,
            border: Border(
              top: BorderSide(color: context.separatorColor, width: 0.5),
            ),
            items: [
              BottomNavigationBarItem(
                icon: _buildTabIcon(CupertinoIcons.chat_bubble, totalUnread),
                activeIcon: _buildTabIcon(
                  CupertinoIcons.chat_bubble_fill,
                  totalUnread,
                ),
                label: 'AiChat',
              ),
              const BottomNavigationBarItem(
                icon: Icon(CupertinoIcons.person_2),
                label: '通讯录',
              ),
              const BottomNavigationBarItem(
                icon: Icon(CupertinoIcons.person_crop_circle),
                label: '我',
              ),
            ],
          ),
          tabBuilder: (context, index) {
            switch (index) {
              case 0:
                return _buildChatList();
              case 1:
                return _buildCharacterList();
              default:
                return const ProfileScreen();
            }
          },
        );
      },
    );
  }

  Widget _buildChatList() {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('AiChat'),
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
                return CupertinoListTile(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
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

          if (provider.characters.isEmpty) {
            return Center(
              child: Text(
                '暂无可用角色',
                style: TextStyle(color: context.textSecondaryColor),
              ),
            );
          }

          // 按拼音首字母分组排序（类似手机通讯录）
          final groups = provider.sortedCharactersGrouped;
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
                            character.name,
                            character.avatar,
                          ),
                          title: Text(
                            character.name,
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
    // 未设置头像时显示默认用户图标
    if (avatar.isEmpty) {
      return Container(
        width: 45,
        height: 45,
        decoration: BoxDecoration(
          color: context.accentColor.withValues(alpha: 0.15),
        ),
        alignment: Alignment.center,
        child: Icon(
          CupertinoIcons.person_fill,
          size: 24,
          color: context.accentColor,
        ),
      );
    }
    return Container(
      width: 45,
      height: 45,
      decoration: BoxDecoration(
        color: context.accentColor.withValues(alpha: 0.15),
        image: DecorationImage(
          image: _cachedAvatarImage(avatar),
          fit: BoxFit.cover,
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
