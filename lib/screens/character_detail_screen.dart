import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../config/routes.dart';
import '../config/theme.dart';
import '../models/character.dart';
import '../models/moment.dart';
import '../providers/character_provider.dart';
import '../providers/chat_provider.dart';

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

  const CharacterDetailScreen({super.key, required this.characterId});

  @override
  State<CharacterDetailScreen> createState() => _CharacterDetailScreenState();
}

class _CharacterDetailScreenState extends State<CharacterDetailScreen> {
  /// 封面背景图交互状态：是否固定展开、当前拖拽偏移、是否正在拖拽
  bool _coverExpanded = false;
  double _coverDragOffset = 0;
  bool _isDragging = false;

  /// 点击头像选择图片（相册 / 拍照）
  Future<void> _pickAvatar(Character character) async {
    final picker = ImagePicker();
    final chatProvider = context.read<ChatProvider>();
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
    await context
        .read<CharacterProvider>()
        .updateAvatar(characterId, base64Encode(bytes));
    // 同步会话快照，首页消息列表头像实时更新
    chatProvider.updateCharacterAvatar(
      characterId,
      base64Encode(bytes),
    );
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

        return CupertinoPageScaffold(
          navigationBar: CupertinoNavigationBar(
            middle: Text(character.name),
          ),
          child: Column(
            children: [
              // 头部：背景图 + 骑跨交界处的头像 + 左侧昵称/签名
              _buildHeader(character),
              // 朋友圈：黑色背景，覆盖屏幕下半部分，内容可滚动
              Expanded(child: _buildMomentsPanel(character)),
              // 底部操作：发送消息（提示词仅可在聊天页右上角菜单的折叠 panel 中编辑）
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: CupertinoButton.filled(
                    onPressed: () {
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
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                    child: const Text(
                      '发送消息',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
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
    final expandDelta = MediaQuery.of(context).size.height * 0.3; // 70% - 40%
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

  /// 头部：背景图（完整高度占屏幕 70%，常态只露出 40%，可下拉展开）+ 骑跨
  /// 交界处的头像（靠右）+ 头像左侧的昵称与个性签名（昵称底边对齐背景区
  /// 底部）。下拉到底（接近完整 70%）松手固定展开，只拉到中间松手回弹 40%；
  /// 「更换封面」按钮仅固定展开时显示在背景图右下角。
  Widget _buildHeader(Character character) {
    final screenHeight = MediaQuery.of(context).size.height;
    const double avatarSize = 84;
    const double avatarOverhang = 42; // 头像下半部分伸出背景图的高度（骑跨区）
    const double restRatio = 0.4; // 常态露出背景图高度 = 40% 屏高
    const double fullRatio = 0.7; // 完整背景图高度 = 70% 屏高
    final double restHeight = screenHeight * restRatio;
    final double fullHeight = screenHeight * fullRatio;
    final double expandDelta = fullHeight - restHeight;

    // 当前背景图高度：固定展开态取完整值，拖拽态 = 常态 + 拖拽偏移
    final double coverHeight =
        _coverExpanded ? fullHeight : restHeight + _coverDragOffset;
    final signature = character.signature.trim();

    return SizedBox(
      height: coverHeight + avatarOverhang,
      // 头部整块响应下拉手势，展开封面
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) => _isDragging = true,
        onVerticalDragUpdate: (details) {
          setState(() {
            _isDragging = true;
            // 固定展开态也允许继续拖拽（向上拉可收回）
            if (_coverExpanded) _coverExpanded = false;
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
      color: const Color(0xFF18181A),
      // 朋友圈滚到顶部后继续下拉（过度滚动）时，驱动背景图自然展开
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollUpdateNotification &&
              notification.dragDetails != null &&
              notification.metrics.pixels < 0) {
            setState(() {
              _isDragging = true;
              if (_coverExpanded) _coverExpanded = false;
              _coverDragOffset = (-notification.metrics.pixels).clamp(
                0.0,
                MediaQuery.of(context).size.height * 0.3,
              );
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
          padding: const EdgeInsets.only(top: 8, bottom: 16),
          children: [
            // 朋友圈标题栏
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.circle_grid_3x3_fill,
                    size: 16,
                    color: CupertinoColors.systemGrey,
                  ),
                  SizedBox(width: 8),
                  Text(
                    '朋友圈',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.systemGrey,
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
                    '这里将展示角色的朋友圈动态',
                    style: TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.systemGrey.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              )
            else
              ...moments.map((m) => _buildMomentCard(character, m)),
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
                        color: CupertinoColors.white.withValues(alpha: 0.9),
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
                        color: CupertinoColors.white.withValues(alpha: 0.9),
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

  /// 单条朋友圈卡片：小头像 + 昵称、正文、图片、点赞/评论、时间
  Widget _buildMomentCard(Character character, Moment moment) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF202024),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMomentAvatar(character),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  character.displayName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.white,
                  ),
                ),
                if (moment.content.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    moment.content,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.4,
                      color: CupertinoColors.white,
                    ),
                  ),
                ],
                if (moment.images.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildMomentImages(moment.images),
                ],
                if (moment.likes.isNotEmpty || moment.comments.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildMomentInteractions(moment),
                ],
                const SizedBox(height: 6),
                Text(
                  _formatMomentTime(moment.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: CupertinoColors.systemGrey.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 朋友圈小头像：已设置用图片，未设置用默认用户图标
  Widget _buildMomentAvatar(Character character) {
    if (character.avatar.isNotEmpty) {
      return Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          image: DecorationImage(
            image: _cachedImage(character.avatar),
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: CupertinoColors.white.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: const Icon(
        CupertinoIcons.person_fill,
        size: 20,
        color: CupertinoColors.white,
      ),
    );
  }

  /// 朋友圈图片：最多展示 9 张，1 张大图、多张 3 列网格（对齐微信朋友圈）；
  /// 图片缺失时只显示文字占位。点击图片全屏预览。
  Widget _buildMomentImages(List<String> paths) {
    final shown = paths.where((p) => File(p).existsSync()).take(9).toList();
    if (shown.isEmpty) {
      return Text(
        '图片加载失败',
        style: TextStyle(
          fontSize: 12,
          color: CupertinoColors.systemGrey.withValues(alpha: 0.7),
        ),
      );
    }
    if (shown.length == 1) {
      return GestureDetector(
        onTap: () => _previewImage(shown.first),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: double.infinity,
            height: 150,
            child: Image(
              image: FileImage(File(shown.first)),
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          ),
        ),
      );
    }
    // 多图：3 列网格，单格按卡片内可用宽度均分
    final screenWidth = MediaQuery.of(context).size.width;
    final cell = (screenWidth - 32 - 24 - 34 - 10 - 8) / 3;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: shown.map((p) {
        return GestureDetector(
          onTap: () => _previewImage(p),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: cell,
              height: cell,
              child: Image(
                image: FileImage(File(p)),
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// 点赞 + 评论区：浅底块内先点赞昵称，再逐条评论（昵称蓝色）
  Widget _buildMomentInteractions(Moment moment) {
    final hasLikes = moment.likes.isNotEmpty;
    final hasComments = moment.comments.isNotEmpty;
    if (!hasLikes && !hasComments) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF18181A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasLikes) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  CupertinoIcons.heart_fill,
                  size: 13,
                  color: Color(0xFFFA5151),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    moment.likes.join('、'),
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF8FB8E8),
                    ),
                  ),
                ),
              ],
            ),
            if (hasComments) const SizedBox(height: 6),
          ],
          if (hasComments)
            ...moment.comments.map(
              (c) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${c.sender}：',
                        style: const TextStyle(color: Color(0xFF8FB8E8)),
                      ),
                      TextSpan(text: c.content),
                    ],
                  ),
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: CupertinoColors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 全屏预览朋友圈图片（点击任意位置关闭）
  void _previewImage(String path) {
    if (!File(path).existsSync()) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: CupertinoColors.black.withValues(alpha: 0.9),
        barrierDismissible: true,
        pageBuilder: (_, __, ___) => GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Center(
            child: InteractiveViewer(
              maxScale: 4,
              child: Image.file(File(path)),
            ),
          ),
        ),
      ),
    );
  }

  /// 朋友圈时间显示：今天/昨天显示时分，同一年省略年份
  String _formatMomentTime(DateTime? time) {
    if (time == null) return '';
    final now = DateTime.now();
    final d = time.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    String two(int n) => n.toString().padLeft(2, '0');
    final hm = '${two(d.hour)}:${two(d.minute)}';
    final diff = today.difference(day).inDays;
    if (diff == 0) return '今天 $hm';
    if (diff == 1) return '昨天 $hm';
    if (d.year == now.year) return '${two(d.month)}-${two(d.day)} $hm';
    return '${d.year}-${two(d.month)}-${two(d.day)} $hm';
  }

  /// 角色头像：已设置显示图片，未设置显示默认用户图标
  Widget _buildAvatar(Character character) {
    if (character.avatar.isNotEmpty) {
      return Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: CupertinoColors.white.withValues(alpha: 0.5),
            width: 2,
          ),
          image: DecorationImage(
            image: _cachedImage(character.avatar),
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        color: CupertinoColors.white.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: CupertinoColors.white.withValues(alpha: 0.5),
          width: 2,
        ),
      ),
      alignment: Alignment.center,
      child: const Icon(
        CupertinoIcons.person_fill,
        size: 44,
        color: CupertinoColors.white,
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
