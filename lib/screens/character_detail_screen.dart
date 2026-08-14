import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../config/routes.dart';
import '../config/theme.dart';
import '../models/character.dart';
import '../models/moment.dart';
import '../providers/auth_provider.dart';
import '../providers/character_provider.dart';
import '../providers/chat_provider.dart';
import '../utils/app_toast.dart';
import '../widgets/character_avatar.dart';
import '../widgets/moment_card.dart';
import '../widgets/publish_moment_screen.dart';

/// 朋友圈列表滚动物理：顶部保留 iOS 橡皮筋回弹（供封面下拉展开），
/// 底部改为硬截止（到达列表末尾立即停止，不再越界回弹），
/// 彻底消除快速滑动到底部时内容越界往复导致的"抖动"。
class _MomentsScrollPhysics extends BouncingScrollPhysics {
  const _MomentsScrollPhysics({super.parent});

  @override
  _MomentsScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _MomentsScrollPhysics(parent: buildParent(ancestor));

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    final double result = _applyBoundaryConditions(position, value);
    return result;
  }

  double _applyBoundaryConditions(ScrollMetrics position, double value) {
    // 顶部：允许越界（Bouncing 行为），供下拉展开封面
    if (value < position.minScrollExtent) return 0.0;
    // 底部：硬截止（Clamping 行为），到达 maxScrollExtent 后不再越界
    if (value > position.maxScrollExtent &&
        position.pixels <= position.maxScrollExtent) {
      return value - position.maxScrollExtent;
    }
    // 防御：极端情况下已越过底部，继续增大时按越界量返回
    if (position.pixels > position.maxScrollExtent &&
        value >= position.pixels) {
      return value - position.pixels;
    }
    return 0.0;
  }

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    final Tolerance tolerance = toleranceFor(position);
    // 顶部越界：橡皮筋回弹到 0（下拉展开封面后松手回弹）。
    // 速度取原始 velocity（与官方 BouncingScrollSimulation._underscrollSimulation
    // 一致）：负速度先继续深入越界区再回弹，避免 -velocity 造成的收敛振荡。
    if (position.pixels < position.minScrollExtent) {
      return ScrollSpringSimulation(
        spring,
        position.pixels,
        position.minScrollExtent,
        velocity,
        tolerance: tolerance,
      );
    }
    // 底部越界（防御分支，正常拖拽已被硬截止）：回弹到 maxScrollExtent
    if (position.pixels > position.maxScrollExtent) {
      return ScrollSpringSimulation(
        spring,
        position.pixels,
        position.maxScrollExtent,
        math.min(0.0, velocity),
        tolerance: tolerance,
      );
    }
    // 正常范围：惯性滚动
    if (velocity.abs() < tolerance.velocity) return null;
    // 向下（朝底部）：Clamping 摩擦减速，配合拖拽硬截止，到底即停
    if (velocity > 0.0) {
      if (position.pixels >= position.maxScrollExtent) return null;
      return ClampingScrollSimulation(
        position: position.pixels,
        velocity: velocity,
        tolerance: tolerance,
      );
    }
    // 向上（朝顶部）：官方 BouncingScrollSimulation —— 摩擦减速，接近顶部时
    // 转入受限弹簧回弹。不能再用 ClampingScrollSimulation：顶部为开边界而
    // 惯性模拟不经过 applyBoundaryConditions，会直接穿透顶部滑进深度越界区
    // （-100~-160px）再缓慢回弹，即用户感知的"抖动"。
    return BouncingScrollSimulation(
      spring: spring,
      position: position.pixels,
      velocity: velocity,
      leadingExtent: position.minScrollExtent,
      trailingExtent: position.maxScrollExtent,
      tolerance: tolerance,
    );
  }
}

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

class _CharacterDetailScreenState extends State<CharacterDetailScreen>
    with TickerProviderStateMixin {
  /// 封面背景图高度比例（相对屏高）
  static const double _coverRestRatio = 0.40; // 常态露出高度
  static const double _coverFullRatio = 0.70; // 下拉展开后的完整高度
  static const double _coverMinRatio = 0.10; // 上滑浏览朋友圈时收缩到的下限

  /// 封面背景图交互状态：是否固定展开、当前拖拽偏移、
  /// 上滑浏览朋友圈时的收缩偏移（封面可缩小到页面 10%）
  bool _coverExpanded = false;
  double _coverDragOffset = 0;
  double _coverShrink = 0;

  /// 封面吸附动画：仅在松手吸附（回弹/固定展开）时由 [AnimationController]
  /// 显式播放一次；滚动跟手 / 惯性滚动期间一律瞬时跟随，绝不依赖隐式动画
  /// 逐帧重启，避免封面动画反复追逐导致界面卡屏。
  late final AnimationController _settleController;
  Animation<double>? _settleAnim;

  /// 当前渲染的封面高度（px）：滚动期间等于目标高度，吸附动画期间取动画插值，
  /// 作为吸附动画的起始高度。
  double _renderedCoverHeight = 0;

  @override
  void initState() {
    super.initState();
    _settleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..addListener(() {
        if (_settleAnim != null) setState(() {});
      });
  }

  @override
  void dispose() {
    _settleController.dispose();
    super.dispose();
  }

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

  /// 头像选择弹窗：查看 / 保存 / 更换
  void _showAvatarMenu(Character character) {
    final hasAvatar = character.avatar.isNotEmpty;
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('角色头像'),
        actions: [
          // 未设置头像时无需「查看 / 保存」
          if (hasAvatar)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                _viewAvatar(character);
              },
              child: const Text('查看头像'),
            ),
          if (hasAvatar)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                _saveAvatar(character);
              },
              child: const Text('保存头像'),
            ),
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

  /// 全屏查看头像大图（单击关闭、双击缩放、可放大拖动）
  void _viewAvatar(Character character) {
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => _AvatarPreviewScreen(base64: character.avatar),
      ),
    );
  }

  /// 保存头像到系统相册（base64 头像解码为图片字节后通过 gal 写入）
  Future<void> _saveAvatar(Character character) async {
    // gal 不自动申请权限：Android 6–9 需要 WRITE_EXTERNAL_STORAGE 才能写入相册
    if (!await Gal.hasAccess()) {
      final granted = await Gal.requestAccess();
      if (!granted) {
        if (mounted) showAppToast('未获得相册权限，无法保存头像');
        return;
      }
    }
    try {
      final bytes = base64Decode(character.avatar);
      // name 无需扩展名：gal 会根据图片字节自动检测格式
      await Gal.putImageBytes(
        bytes,
        name: 'aichat_avatar_${DateTime.now().millisecondsSinceEpoch}',
      );
      if (mounted) showAppToast('头像已保存到系统相册');
    } on GalException catch (e) {
      if (!mounted) return;
      showAppToast(
        switch (e.type) {
          GalExceptionType.accessDenied => '未获得相册权限，无法保存头像',
          GalExceptionType.notEnoughSpace => '存储空间不足，保存失败',
          GalExceptionType.notSupportedFormat => '头像格式不支持保存',
          GalExceptionType.unexpected => '保存失败，请重试',
        },
      );
    } catch (_) {
      if (mounted) showAppToast('保存头像失败，请重试');
    }
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
  /// 吸附动画由 [AnimationController] 从当前渲染高度显式播放一次；
  /// 播放期间若有新的滚动/拖拽会立即取消（见滚动回调），不会循环。
  void _settleCover() {
    final screenHeight = MediaQuery.of(context).size.height;
    final expandDelta = screenHeight * (_coverFullRatio - _coverRestRatio);
    final expanded = _coverDragOffset >= expandDelta * 0.9;
    final targetHeight =
        (((expanded ? screenHeight * _coverFullRatio : screenHeight * _coverRestRatio) +
                    (expanded ? expandDelta : 0) -
                    _coverShrink))
            .clamp(screenHeight * _coverMinRatio, screenHeight * _coverFullRatio);
    setState(() {
      _coverExpanded = expanded;
      _coverDragOffset = expanded ? expandDelta : 0;
    });
    _playSettleAnimation(targetHeight);
  }

  /// 取消进行中的吸附动画（用户重新滚动/拖拽时调用），转回瞬时跟随
  void _cancelSettleAnimation() {
    if (_settleAnim == null) return;
    _settleController.stop();
    _settleAnim = null;
  }

  /// 播放一次封面吸附动画：从当前渲染高度过渡到 [targetHeight]。
  /// 距离过小（<0.5px）时直接跳过，避免无意义的动画。
  void _playSettleAnimation(double targetHeight) {
    _settleController.stop();
    _settleAnim = null;
    final from = _renderedCoverHeight;
    if ((from - targetHeight).abs() < 0.5) return;
    _settleAnim = Tween<double>(begin: from, end: targetHeight)
        .chain(CurveTween(curve: Curves.easeOutCubic))
        .animate(_settleController)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _settleAnim = null);
        }
      });
    _settleController.forward(from: 0);
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

    // 当前背景图高度：展开态取完整值、常态取 40%，再减去上滑收缩偏移；
    // 吸附动画期间取动画插值高度（一次性播放），滚动期间瞬时跟随目标值
    final double baseHeight = _coverExpanded ? fullHeight : restHeight;
    final double targetCoverHeight =
        (baseHeight + _coverDragOffset - _coverShrink).clamp(minHeight, fullHeight);
    final double coverHeight =
        _settleAnim != null ? _settleAnim!.value : targetCoverHeight;
    _renderedCoverHeight = coverHeight;
    final signature = character.signature.trim();

    return SizedBox(
      height: coverHeight + avatarOverhang,
      // 头部整块响应下拉手势，展开封面
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) {
          _cancelSettleAnimation();
        },
        onVerticalDragUpdate: (details) {
          setState(() {
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
              child: Container(
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
            // 背景图底部与朋友圈区交接处：黑色渐变蒙版，
            // 提升骑跨交界处的昵称 / 个性签名可读性（文字为白色）
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: (coverHeight * 0.35).clamp(72.0, 190.0),
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        CupertinoColors.black.withValues(alpha: 0.0),
                        CupertinoColors.black.withValues(alpha: 0.55),
                      ],
                    ),
                  ),
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
            // 跟手拖动与惯性滚动期间一律瞬时跟随封面；若吸附动画正在播放
            // （松手后尚未结束又继续滚动）则立即取消，转回瞬时跟随，
            // 避免封面动画反复追逐导致界面卡屏
            final screenHeight = MediaQuery.of(context).size.height;
            final pixels = notification.metrics.pixels;
            // 高复杂度降级：松手后的越界回弹（惯性弹簧）期间不跟手驱动封面，
            // 朋友圈只做纯滚动（不加动画），避免回弹过程中封面反复 setState
            // 整页重建造成的抖动；封面在 ScrollEnd 时由 _settleCover 吸附到位。
            // 跟手拖动（下拉展开封面）与正常范围内的惯性滚动仍实时跟随。
            final bool degraded = notification.dragDetails == null &&
                notification.metrics.outOfRange;
            // 先计算目标状态，仅当封面状态实际发生变化时才 setState：
            // 越界回弹/饱和期封面已到极限或冻结，若仍每帧 setState 整页重建，
            // 会造成掉帧与视觉抖动。
            double newShrink = _coverShrink;
            double newDragOffset = _coverDragOffset;
            var newExpanded = _coverExpanded;
            if (!degraded) {
              if (pixels < 0) {
                // 滚到顶部继续下拉：展开背景图
                newExpanded = false;
                newShrink = 0;
                newDragOffset = (-pixels).clamp(
                  0.0,
                  screenHeight * (_coverFullRatio - _coverRestRatio),
                );
              } else if (pixels > 0) {
                // 上滑浏览朋友圈：封面从常态比例逐步收缩到下限比例
                newDragOffset = 0;
                final shrinkMax =
                    screenHeight * (_coverRestRatio - _coverMinRatio);
                newShrink = (pixels / (screenHeight * 0.3) * shrinkMax)
                    .clamp(0.0, shrinkMax);
              } else {
                newShrink = 0;
                newDragOffset = 0;
              }
            }
            final coverChanged = _settleAnim != null ||
                newShrink != _coverShrink ||
                newDragOffset != _coverDragOffset ||
                newExpanded != _coverExpanded;
            if (coverChanged) {
              setState(() {
                _cancelSettleAnimation();
                _coverExpanded = newExpanded;
                _coverShrink = newShrink;
                _coverDragOffset = newDragOffset;
              });
            }
          } else if (notification is ScrollEndNotification) {
            _settleCover();
          }
          return false;
        },
        child: ListView.builder(
          physics: const _MomentsScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          // 底部留出悬浮按钮空间，避免遮挡最后一条内容
          padding: const EdgeInsets.only(top: 8, bottom: 100),
          // 列表结构：朋友圈标题栏(1) + 动态卡(N，空态占1) + 角色资料卡片(1)
          // 动态多时只按需构建可见卡（ListView 懒加载），避免一次性全量 build
          itemCount: _momentInfoIndex(moments) + 1,
          itemBuilder: (context, i) {
            // 标题栏
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                    const SizedBox(height: 12),
                  ],
                ),
              );
            }
            // 角色资料卡片（标题栏 + 动态/空态之后的固定尾部）
            if (i == _momentInfoIndex(moments)) {
              return Padding(
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
              );
            }
            // 空态
            if (moments.isEmpty) {
              return SizedBox(
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
              );
            }
            // 动态卡
            final m = moments[i - 1];
            return RepaintBoundary(
              child: Padding(
                padding: const EdgeInsets.only(
                    left: 16, right: 16, bottom: 12),
                child: MomentCard(
                  character: character,
                  moment: m,
                  manageMode: widget.manageMode,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// 列表尾部"角色资料卡片"的索引：标题栏(1) + 动态/空态项数
  int _momentInfoIndex(List<Moment> moments) =>
      1 + (moments.isEmpty ? 1 : moments.length);

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

/// 头像全屏预览页：黑底居中展示，单击关闭、双击缩放、双指缩放后
/// 可自由拖动查看。子组件为整屏大小的盒子、图片在其内部居中，
/// 避免 InteractiveViewer(constrained: false) 把图片锚定到左上角。
class _AvatarPreviewScreen extends StatefulWidget {
  final String base64;

  const _AvatarPreviewScreen({required this.base64});

  @override
  State<_AvatarPreviewScreen> createState() => _AvatarPreviewScreenState();
}

class _AvatarPreviewScreenState extends State<_AvatarPreviewScreen> {
  final TransformationController _transform = TransformationController();
  Offset _doubleTapPos = Offset.zero;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  /// 双击：放大 2.5 倍（以点击处为中心），再次双击复位
  void _toggleZoom() {
    if (_transform.value.getMaxScaleOnAxis() > 1.05) {
      _transform.value = Matrix4.identity();
    } else {
      final p = _doubleTapPos;
      _transform.value = Matrix4.identity()
        ..translateByDouble(p.dx, p.dy, 0, 1)
        ..scaleByDouble(2.5, 2.5, 1, 1)
        ..translateByDouble(-p.dx, -p.dy, 0, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.of(context).size;
    return ColoredBox(
      color: CupertinoColors.black,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        onDoubleTapDown: (details) => _doubleTapPos = details.localPosition,
        onDoubleTap: _toggleZoom,
        child: InteractiveViewer(
          transformationController: _transform,
          constrained: false,
          boundaryMargin: const EdgeInsets.all(200),
          minScale: 1,
          maxScale: 6,
          child: SizedBox(
            width: viewport.width,
            height: viewport.height,
            child: Center(
              child: Image.memory(
                base64Decode(widget.base64),
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
