import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../config/routes.dart';
import '../config/theme.dart';
import '../models/character.dart';
import '../providers/auth_provider.dart';
import '../providers/character_provider.dart';
import '../providers/chat_provider.dart';
import '../widgets/character_avatar.dart';
import '../widgets/moment_card.dart';
import '../widgets/publish_moment_screen.dart';

/// base64 图片解码缓存：同一 base64 只解码一次并复用同一个 [MemoryImage]。
/// 若每次重建都新建 [MemoryImage]，ImageCache 永不命中（Dart 的 List ==
/// 是引用比较），会导致头像/背景图反复解码、页面闪烁。
final Map<String, MemoryImage> _detailImageCache = {};
MemoryImage _cachedImage(String base64) {
  return _detailImageCache.putIfAbsent(
    base64,
    () {
      if (_detailImageCache.length > 64) _detailImageCache.clear();
      return MemoryImage(base64Decode(base64));
    },
  );
}

class CharacterDetailScreen extends StatefulWidget {
  final String characterId;

  /// 管理模式（从「管理朋友圈」进入）：朋友圈卡片菜单与评论
  /// 对所有角色开放【编辑】【删除】，便于数据维护。
  final bool manageMode;

  const CharacterDetailScreen({
    super.key,
    required this.characterId,
    this.manageMode = false,
  });

  @override
  State<CharacterDetailScreen> createState() => _CharacterDetailScreenState();
}

class _CharacterDetailScreenState extends State<CharacterDetailScreen> {
  /// 封面背景图高度比例（相对屏高）
  static const double _coverRestRatio = 0.40; // 常态露出高度
  static const double _coverFullRatio = 0.70; // 下拉展开后的完整高度
  static const double _coverMinRatio = 0.10; // 上滑浏览朋友圈时收缩到的下限

  /// 封面背景图交互状态：是否固定展开、当前拖拽偏移、是否正在拖拽、
  /// 上滑浏览朋友圈时的收缩偏移（封面可缩小到页面 10%）
  bool _coverExpanded = false;
  double _coverDragOffset = 0;
  double _coverShrink = 0;
  bool _isDragging = false;

  /// 点击头像选择图片（相册 / 拍照）
  Future<void> _pickAvatar(Character character) async {
    final picker = ImagePicker();
    final chatProvider = context.read<ChatProvider>();
    final characterProvider = context.read<CharacterProvider>();
    final authProvider = context.read<AuthProvider>();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 500,
      maxHeight: 500,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final characterId = character.id;
    await characterProvider.updateAvatar(characterId, base64Encode(bytes));
    if (widget.characterId == CharacterProvider.selfCharacterId) {
      // "自己"的头像与个人资料头像保持一致
      await authProvider.updateProfile(avatar: base64Encode(bytes));
    } else {
      // 同步会话快照，首页消息列表头像实时更新
      chatProvider.updateCharacterAvatar(
        characterId,
        base64Encode(bytes),
      );
    }
  }

  /// 头像选择弹窗
  void _showAvatarMenu(Character character) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('设置角色头像'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _pickAvatar(character);
            },
            child: const Text('从相册选择'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
      ),
    );
  }

  /// 点击背景图选择图片
  Future<void> _pickBackground(Character character) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1080,
      maxHeight: 1080,
      imageQuality: 80,
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    await context
        .read<CharacterProvider>()
        .updateBackground(character.id, base64Encode(bytes));
  }

  /// 背景图选择弹窗
  void _showBackgroundMenu(Character character) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('设置角色背景图'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _pickBackground(character);
            },
            child: const Text('从相册选择'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<CharacterProvider, ChatProvider>(
      builder: (context, characterProvider, chatProvider, _) {
        final character =
            characterProvider.getCharacterById(widget.characterId);

        if (character == null) {
          return CupertinoPageScaffold(
            navigationBar: const CupertinoNavigationBar(middle: Text('角色详情')),
            child: Center(
              child: Text(
                '角色不存在',
                style: TextStyle(color: context.textSecondaryColor),
              ),
            ),
          );
        }

        // 评论输入时软键盘拉起：隐藏头部背景图与悬浮按钮，
        // 让朋友圈列表占满可用空间（键盘收回后恢复）
        final keyboardUp = MediaQuery.of(context).viewInsets.bottom > 0;

        return CupertinoPageScaffold(
          navigationBar: CupertinoNavigationBar(
            middle: Text(character.name),
          ),
          child: Stack(
            children: [
              Column(
                children: [
                  // 头部：背景图 + 骑跨交界处的头像 + 左侧昵称/签名
                  if (!keyboardUp) _buildHeader(character),
                  // 朋友圈：黑色背景，覆盖屏幕下半部分，内容可滚动
                  Expanded(child: _buildMomentsPanel(character)),
                ],
              ),
              // 悬浮按钮（无背景面板，右下角）：
              // 其他角色为聊天入口；"自己"不能发起聊天，改为发布朋友圈
              if (!keyboardUp)
                Positioned(
                  right: 20,
                  bottom: 28,
                  child: _buildFloatingButton(character, chatProvider),
                ),
            ],
          ),
        );
      },
    );
  }

  /// 松手后吸附：接近完整高度（90% 以上）则固定展开 70%，否则回弹到常态 40%。
  /// 头部拖拽与朋友圈下拉到顶的过度滚动共用此判定。
  void _settleCover() {
    final screenHeight = MediaQuery.of(context).size.height;
    final expandDelta = screenHeight * (_coverFullRatio - _coverRestRatio);
    setState(() {
      _isDragging = false;
      if (_coverDragOffset >= expandDelta * 0.9) {
        _coverExpanded = true;
        _coverDragOffset = expandDelta;
      } else {
        _coverExpanded = false;
        _coverDragOffset = 0;
      }
    });
  }

  /// 右下角悬浮按钮：非"自己"为聊天入口；"自己"不能发起聊天，改为发布朋友圈
  Widget _buildFloatingButton(Character character, ChatProvider chatProvider) {
    if (widget.characterId == CharacterProvider.selfCharacterId) {
      return GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            CupertinoPageRoute(builder: (_) => const PublishMomentScreen()),
          );
        },
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: context.accentColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: CupertinoColors.black.withValues(alpha: 0.25),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            CupertinoIcons.camera_fill,
            size: 26,
            color: CupertinoColors.white,
          ),
        ),
      );
    }
    return _buildFloatingSendButton(character, chatProvider);
  }

  /// 悬浮发送按钮：圆形，右下角，无背景面板。点击进入聊天
  Widget _buildFloatingSendButton(Character character, ChatProvider chatProvider) {
    return GestureDetector(
      onTap: () {
        final conversation = chatProvider.getOrCreateConversation(
          characterId: character.id,
          characterName: character.displayName,
          characterAvatar: character.avatar,
        );
        Navigator.pushNamed(
          context,
          AppRoutes.chat,
          arguments: {
            'conversationId': conversation.id,
            'characterName': character.displayName,
            'characterAvatar': character.avatar,
          },
        );
      },
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: context.accentColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: CupertinoColors.black.withValues(alpha: 0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(
          CupertinoIcons.chat_bubble_fill,
          size: 26,
          color: CupertinoColors.white,
        ),
      ),
    );
  }

  /// 头部：背景图（完整高度占屏幕 70%，常态只露出 40%，可下拉展开）+ 骑跨
  /// 交界处的头像（靠右）+ 头像左侧的昵称与个性签名（昵称底边对齐背景区
  /// 底部）。下拉到底（接近完整 70%）松手固定展开，只拉到中间松手回弹 40%；
  /// 「更换封面」按钮仅固定展开时显示在背景图右下角。
  Widget _buildHeader(Character character) {
    final screenHeight = MediaQuery.of(context).size.height;
    const double avatarSize = 84;
    const double avatarOverhang = 42; // 头像下半部分伸出背景图的高度（骑跨区）
    final double restHeight = screenHeight * _coverRestRatio;
    final double fullHeight = screenHeight * _coverFullRatio;
    final double expandDelta = fullHeight - restHeight;
    final double minHeight = screenHeight * _coverMinRatio; // 上滑收缩下限

    // 当前背景图高度：展开态取完整值、常态取 40%，再减去上滑收缩偏移
    final double baseHeight = _coverExpanded ? fullHeight : restHeight;
    final double coverHeight = (baseHeight + _coverDragOffset - _coverShrink)
        .clamp(minHeight, fullHeight);
    final signature = character.signature.trim();

    return SizedBox(
      height: coverHeight + avatarOverhang,
      // 头部整块响应下拉手势，展开封面
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) {
          setState(() => _isDragging = true);
        },
        onVerticalDragUpdate: (details) {
          setState(() {
            _isDragging = true;
            // 固定展开态也允许继续拖拽（向上拉可收回）
            if (_coverExpanded) _coverExpanded = false;
            _coverShrink = 0;
            _coverDragOffset = (_coverDragOffset + details.delta.dy).clamp(
              0.0,
              expandDelta,
            );
          });
        },
        onVerticalDragEnd: (_) => _settleCover(),
        child: Stack(
          children: [
            // 背景图区域（下拉手势由外层统一处理；更换封面仅可点右下角按钮）
            Positioned.fill(
              child: AnimatedContainer(
                // 拖拽中即时跟随手指，松手后平滑回弹/固定
                duration: _isDragging
                    ? Duration.zero
                    : const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      context.accentColor,
                      context.accentColor.withValues(alpha: 0.85),
                    ],
                  ),
                ),
                child: character.background.isEmpty
                    // 未设置背景图：渐变 + 交互提示
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              CupertinoIcons.photo,
                              size: 26,
                              color:
                                  CupertinoColors.white.withValues(alpha: 0.85),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '下拉查看完整封面',
                              style: TextStyle(
                                fontSize: 13,
                                color: CupertinoColors.white
                                    .withValues(alpha: 0.85),
                              ),
                            ),
                          ],
                        ),
                      )
                    // 已设置背景图：放大铺满整个区域（BoxFit.cover）
                    : Image(
                        image: _cachedImage(character.background),
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
              ),
            ),
            // 更换封面按钮：仅在拉到底部（固定展开）时显示在背景图右下角
            if (_coverExpanded)
              Positioned(
                right: 12,
                bottom: coverHeight - 40,
                child: GestureDetector(
                  onTap: () => _showBackgroundMenu(character),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: CupertinoColors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.camera_fill,
                          size: 13,
                          color: CupertinoColors.white,
                        ),
                        SizedBox(width: 4),
                        Text(
                          '更换封面',
                          style: TextStyle(
                            fontSize: 12,
                            color: CupertinoColors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // 头像：骑跨背景图与朋友圈区交界处，靠右（昵称在其左侧）
            Positioned(
              right: 16,
              top: coverHeight - avatarSize / 2,
              child: GestureDetector(
                onTap: () => _showAvatarMenu(character),
                child: _buildAvatar(character),
              ),
            ),
            // 昵称 + 签名：头像左侧，整体略低于背景区底部，避免视觉上浮
            Positioned(
              left: 16,
              right: 16 + avatarSize + 12,
              bottom: avatarOverhang - 35,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    character.displayName,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: CupertinoColors.white,
                    ),
                  ),
                  if (signature.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        signature,
                        textAlign: TextAlign.right,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.white.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 朋友圈面板：黑色背景，覆盖屏幕下半部分，内容可滚动。
  /// 展示角色的朋友圈动态（文案 / 图片 / 点赞 / 评论 / 时间），
  /// 无动态时显示空态提示；滚到顶部继续下拉会自然展开背景图。
  Widget _buildMomentsPanel(Character character) {
    final moments = character.moments;
    return Container(
      color: context.momentsBgColor,
      // 朋友圈滚到顶部后继续下拉（过度滚动）时，驱动背景图自然展开；
      // 上滑浏览内容时，背景图从常态 40% 逐步收缩到页面 25%
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollUpdateNotification) {
            // 手指拖动时跟手（瞬时动画），惯性滚动/程序滚动时用动画平滑过渡
            final isTouchDrag = notification.dragDetails != null;
            final screenHeight = MediaQuery.of(context).size.height;
            final pixels = notification.metrics.pixels;
            setState(() {
              _isDragging = isTouchDrag;
              if (pixels < 0) {
                // 滚到顶部继续下拉：展开背景图
                if (_coverExpanded) _coverExpanded = false;
                _coverShrink = 0;
                _coverDragOffset = (-pixels).clamp(
                  0.0,
                  screenHeight * (_coverFullRatio - _coverRestRatio),
                );
              } else if (pixels > 0) {
                // 上滑浏览朋友圈：封面从常态比例逐步收缩到下限比例
                _coverDragOffset = 0;
                final shrinkMax =
                    screenHeight * (_coverRestRatio - _coverMinRatio);
                _coverShrink = (pixels / (screenHeight * 0.3) * shrinkMax)
                    .clamp(0.0, shrinkMax);
              } else {
                _coverShrink = 0;
                _coverDragOffset = 0;
              }
            });
          } else if (notification is ScrollEndNotification) {
            _settleCover();
          }
          return false;
        },
        child: ListView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          // 底部留出悬浮按钮空间，避免遮挡最后一条内容
          padding: const EdgeInsets.only(top: 8, bottom: 100),
          children: [
            // 朋友圈标题栏
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.circle_grid_3x3_fill,
                    size: 16,
                    color: context.textSecondaryColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '朋友圈',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.textSecondaryColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // 动态列表（无动态时显示空态）
            if (moments.isEmpty)
              SizedBox(
                height: 90,
                child: Center(
                  child: Text(
                    widget.characterId == CharacterProvider.selfCharacterId
                        ? '还没有发布过朋友圈，点击右下角相机按钮发布第一条'
                        : '这里将展示角色的朋友圈动态',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.systemGrey.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              )
            else
              ...moments.map(
                (m) => Padding(
                  padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                  child: MomentCard(
                    character: character,
                    moment: m,
                    manageMode: widget.manageMode,
                  ),
                ),
              ),
            // 角色资料卡片（跟随滚动，黑色背景上使用白色标题）
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (character.description.isNotEmpty) ...[
                    Text(
                      '角色介绍',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimaryColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _infoCard(context, character.description),
                    const SizedBox(height: 16),
                  ],
                  if (character.greeting.isNotEmpty) ...[
                    Text(
                      '开场白',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimaryColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _infoCard(context, character.greeting),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 角色头像：跟随全局设置（方形 / 仿 QQ 圆形），未设置时显示默认用户图标
  Widget _buildAvatar(Character character) {
    return CharacterAvatar(
      base64: character.avatar,
      size: 84,
      borderRadius: BorderRadius.circular(16),
      backgroundColor: CupertinoColors.white.withValues(alpha: 0.3),
      iconColor: CupertinoColors.white,
      iconSize: 44,
      border: Border.all(
        color: CupertinoColors.white.withValues(alpha: 0.5),
        width: 2,
      ),
    );
  }

  Widget _infoCard(BuildContext context, String content) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.listBgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        content,
        style: TextStyle(
          fontSize: 15,
          height: 1.6,
          color: context.textPrimaryColor,
        ),
      ),
    );
  }
}
