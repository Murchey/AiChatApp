import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:gal/gal.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/character.dart';
import '../models/moment.dart';
import '../providers/api_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/character_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/chat_settings_provider.dart';
import '../providers/moment_notification_provider.dart';
import '../services/moment_ai_service.dart';
import '../utils/app_toast.dart';
import 'character_avatar.dart';
import 'publish_moment_screen.dart';

/// 朋友圈卡片：小头像 + 昵称、正文、图片（最多 9 张，3 列网格）、
/// 点赞/评论、时间。深色朋友圈风格，用于角色空间页与朋友圈页。
///
/// 卡片右上角三点为菜单操作按钮，点击后在按钮旁弹出悬浮菜单：
/// 【赞 / 取消赞】【评论】通用；自己发布的动态额外提供【编辑】【删除】；
/// [manageMode]（管理朋友圈）下任意角色的动态都开放【编辑】【删除】，
/// 评论也支持长按删除 / 编辑。
class MomentCard extends StatefulWidget {
  final Character character;
  final Moment moment;

  /// 管理模式：对任意角色动态/评论开放编辑与删除
  final bool manageMode;

  const MomentCard({
    super.key,
    required this.character,
    required this.moment,
    this.manageMode = false,
  });

  @override
  State<MomentCard> createState() => _MomentCardState();
}

class _MomentCardState extends State<MomentCard> {
  /// 三点按钮定位锚点，用于计算悬浮菜单弹出位置
  final GlobalKey _menuButtonKey = GlobalKey();
  OverlayEntry? _menuEntry;

  /// 评论输入栏（Overlay 悬浮在软键盘上方，不占用页面路由）
  OverlayEntry? _commentInputEntry;

  Character get character => widget.character;
  Moment get moment => widget.moment;

  /// 是否为"自己"发布的动态（可编辑）
  bool get _isSelf => character.id == CharacterProvider.selfCharacterId;

  @override
  void dispose() {
    _menuEntry?.remove();
    _commentInputEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.momentCardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _avatar(context),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      character.displayName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimaryColor,
                      ),
                    ),
                    if (moment.content.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        moment.content,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.4,
                          color: context.textPrimaryColor,
                        ),
                      ),
                    ],
                    if (moment.images.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _images(context),
                    ],
                    if (moment.location.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            CupertinoIcons.location_fill,
                            size: 12,
                            color: Color(0xFF8FB8E8),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              moment.location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF8FB8E8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (moment.likes.isNotEmpty ||
                        moment.comments.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _interactions(context),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      _formatTime(moment.createdAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: context.textSecondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // 右上角三点菜单按钮
          Positioned(
            top: 0,
            right: 0,
            child: GestureDetector(
              key: _menuButtonKey,
              behavior: HitTestBehavior.opaque,
              onTap: _toggleMenu,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  CupertinoIcons.ellipsis,
                  size: 18,
                  color: context.textSecondaryColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- 悬浮菜单 ----------------

  /// 三点按钮旁弹出/收起悬浮菜单（Overlay 定位，浮于列表之上）
  void _toggleMenu() {
    if (_menuEntry != null) {
      _dismissMenu();
      return;
    }
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    final buttonBox =
        _menuButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (overlayBox == null || buttonBox == null) return;

    final buttonPos = buttonBox.localToGlobal(Offset.zero);
    const panelWidth = 148.0;
    // 优先展开在按钮右侧；右侧空间不足时右对齐屏幕边缘
    var panelLeft = buttonPos.dx + buttonBox.size.width + 4;
    if (panelLeft + panelWidth > overlayBox.size.width - 8) {
      panelLeft = overlayBox.size.width - panelWidth - 8;
    }
    final panelTop = buttonPos.dy - 4;

    _menuEntry = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          // 透明遮罩：点击面板外关闭
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _dismissMenu,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: panelLeft,
            top: panelTop,
            child: _buildMenuPanel(),
          ),
        ],
      ),
    );
    overlay.insert(_menuEntry!);
  }

  void _dismissMenu() {
    _menuEntry?.remove();
    _menuEntry = null;
  }

  Widget _buildMenuPanel() {
    final myName = context.read<AuthProvider>().user?.nickname ?? '';
    final isLiked = moment.likes.contains(myName);
    return Container(
      width: 148,
      decoration: BoxDecoration(
        color: context.listBgColor,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _menuItem(
            icon: isLiked ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
            label: isLiked ? '取消赞' : '赞',
            onTap: () {
              _dismissMenu();
              _toggleLike();
            },
          ),
          _menuDivider(),
          _menuItem(
            icon: CupertinoIcons.chat_bubble,
            label: '评论',
            onTap: () {
              _dismissMenu();
              _openCommentInput();
            },
          ),
          if (_isSelf || widget.manageMode) ...[
            _menuDivider(),
            _menuItem(
              icon: CupertinoIcons.pencil,
              label: '编辑',
              onTap: () {
                _dismissMenu();
                _editMoment();
              },
            ),
            _menuItem(
              icon: CupertinoIcons.delete,
              label: '删除',
              color: CupertinoColors.systemRed,
              onTap: () {
                _dismissMenu();
                _deleteMoment();
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _menuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color ?? context.accentColor),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                color: color ?? context.textPrimaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuDivider() {
    return Container(
      height: 0.5,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: context.separatorColor,
    );
  }

  // ---------------- 赞 / 评论 / 编辑 ----------------

  /// 当前用户昵称（用于点赞人、评论人标识）
  String get _myName => context.read<AuthProvider>().user?.nickname ?? '';

  /// 更新当前动态（保持其余字段不变）并持久化
  Future<void> _updateMoment({
    List<String>? likes,
    List<MomentComment>? comments,
    Moment? replaced,
  }) async {
    final target = replaced ??
        Moment(
          id: moment.id,
          content: moment.content,
          location: moment.location,
          visibility: moment.visibility,
          images: moment.images,
          likes: likes ?? moment.likes,
          comments: comments ?? moment.comments,
          createdAt: moment.createdAt,
        );
    final newMoments = character.moments
        .map((m) => m.id == moment.id ? target : m)
        .toList();
    await context.read<CharacterProvider>().updateMoments(
          character.id,
          newMoments,
        );
  }

  Future<void> _toggleLike() async {
    final name = _myName;
    if (name.isEmpty) return;
    // 点赞去重：先清理历史数据中重复的昵称，再执行点赞/取消切换
    final likes = <String>[];
    for (final n in moment.likes) {
      if (!likes.contains(n)) likes.add(n);
    }
    if (likes.contains(name)) {
      likes.remove(name);
    } else {
      likes.add(name);
    }
    await _updateMoment(likes: likes);
  }

  /// 打开评论输入栏：输入框悬浮在软键盘上方，输入框上方仍是可滚动
  /// 操作的朋友圈内容（不进入二级页面）。
  /// [editIndex] 非空时表示编辑该位置的评论，输入框预填原内容。
  /// [replyToName] 非空时表示"回复该昵称"（点击评论条目套用回复输入框）。
  void _openCommentInput({int? editIndex, String? replyToName}) {
    if (_commentInputEntry != null) return;
    final overlay = Overlay.of(context);
    _commentInputEntry = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          // 仅底部悬浮输入栏，不覆盖上方列表（列表仍可滑动操作）
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _CommentInputBar(
              initialText:
                  editIndex != null && editIndex >= 0 && editIndex < moment.comments.length
                      ? moment.comments[editIndex].content
                      : null,
              replyToName: replyToName,
              onClose: _closeCommentInput,
              onSend: (text) =>
                  _submitComment(text, editIndex: editIndex, replyTo: replyToName),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_commentInputEntry!);
  }

  void _closeCommentInput() {
    _commentInputEntry?.remove();
    _commentInputEntry = null;
  }

  /// 提交评论：无 [editIndex] 为新增（可携带 [replyTo] 表示回复某昵称），
  /// 有 [editIndex] 为编辑（发送者与回复对象保持不变）。
  void _submitComment(String text, {int? editIndex, String? replyTo}) {
    _closeCommentInput();
    if (editIndex != null) {
      if (editIndex < 0 || editIndex >= moment.comments.length) return;
      final comments = [...moment.comments];
      comments[editIndex] = MomentComment(
        sender: comments[editIndex].sender,
        content: text,
        replyTo: comments[editIndex].replyTo,
      );
      _updateMoment(comments: comments);
    } else {
      final comments = [
        ...moment.comments,
        MomentComment(
          sender: _myName.isEmpty ? '我' : _myName,
          content: text,
          replyTo: replyTo ?? '',
        ),
      ];
      _updateMoment(comments: comments);
      // 触发 AI 回复（管理模式除外）：
      // - 普通评论：由动态发布者回复（自己的动态不触发）
      // - 回复某评论：优先由被回复的角色（若在通讯录）回复，否则由发布者回复；
      //   回复目标为自己时（如在自己动态下回复陌生人评论）不触发
      if (!widget.manageMode) {
        final replier = _resolveReplier(replyTo);
        if (replier != null &&
            replier.id != CharacterProvider.selfCharacterId) {
          _triggerAiReply(text, replier, replyToName: replyTo);
        }
      }
    }
  }

  /// 解析本次 AI 回复的"回复者"：
  /// [replyTo] 指定的昵称若存在于通讯录（非自己）则用该角色，
  /// 否则回退为该条动态的发布者。
  Character? _resolveReplier(String? replyTo) {
    if (replyTo != null && replyTo.isNotEmpty) {
      final chars = context.read<CharacterProvider>().characters;
      for (final c in chars) {
        if (c.displayName == replyTo) return c;
      }
    }
    // 发布者（自己的动态时为自己，调用方据此跳过）
    return character;
  }

  /// 后台请求回复者（角色）回复用户的评论，不阻塞界面。
  /// [replier] 为以谁的身份回复；回复评论始终追加到发布者 [character] 名下。
  /// [replyToName] 为用户回复的评论者昵称（为空表示直接评论动态），
  /// 连同被回复的评论原文一并交给模型，让回复紧扣上下文。
  void _triggerAiReply(String userComment, Character replier,
      {String? replyToName}) {
    // 用户回复某条评论时，取出被回复评论的原文（最近一条匹配），
    // 模型才知道用户是针对"谁说了什么"在回复
    String repliedComment = '';
    if (replyToName != null && replyToName.isNotEmpty) {
      for (final c in moment.comments.reversed) {
        if (c.sender == replyToName) {
          repliedComment = c.content;
          break;
        }
      }
    }
    unawaited(MomentAiService.replyToUserComment(
      apiProvider: context.read<ApiProvider>(),
      chatSettings: context.read<ChatSettingsProvider>(),
      chatProvider: context.read<ChatProvider>(),
      characterProvider: context.read<CharacterProvider>(),
      notificationProvider: context.read<MomentNotificationProvider>(),
      character: replier,
      owner: character,
      moment: moment,
      userNickname: _myName.isEmpty ? '我' : _myName,
      userComment: userComment,
      replyToName: replyToName ?? '',
      repliedComment: repliedComment,
    ));
  }

  /// 长按自己的评论（或管理模式下任意评论）：在长按位置弹出悬浮菜单，
  /// 可选择【编辑】或【删除】该条评论
  void _showCommentMenu(Offset globalPos, int index) {
    if (_menuEntry != null) _dismissMenu();
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (overlayBox == null) return;

    const panelWidth = 148.0;
    const panelHeight = 88.0;
    var left = globalPos.dx;
    if (left + panelWidth > overlayBox.size.width - 8) {
      left = overlayBox.size.width - panelWidth - 8;
    }
    var top = globalPos.dy;
    if (top + panelHeight > overlayBox.size.height - 8) {
      top = overlayBox.size.height - panelHeight - 8;
    }

    _menuEntry = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _dismissMenu,
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
                    color: CupertinoColors.black.withValues(alpha: 0.18),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _menuItem(
                    icon: CupertinoIcons.pencil,
                    label: '编辑评论',
                    onTap: () {
                      _dismissMenu();
                      _openCommentInput(editIndex: index);
                    },
                  ),
                  _menuDivider(),
                  _menuItem(
                    icon: CupertinoIcons.delete,
                    label: '删除评论',
                    color: CupertinoColors.systemRed,
                    onTap: () {
                      _dismissMenu();
                      _deleteComment(index);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_menuEntry!);
  }

  /// 删除一条评论并持久化
  void _deleteComment(int index) {
    if (index < 0 || index >= moment.comments.length) return;
    final comments = [...moment.comments];
    comments.removeAt(index);
    _updateMoment(comments: comments);
  }

  Future<void> _editMoment() async {
    final updated = await Navigator.push<Moment>(
      context,
      CupertinoPageRoute(
        builder: (_) => PublishMomentScreen(editingMoment: moment),
      ),
    );
    if (updated == null || !mounted) return;
    await _updateMoment(replaced: updated);
  }

  /// 删除自己发布的这条朋友圈（需确认，并清理 user_moments/ 下图片）
  Future<void> _deleteMoment() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('删除这条朋友圈？'),
        content: const Text('删除后不可恢复'),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    // 清理动态图片（仅"自己"发布目录 user_moments/ 下的文件）
    for (final p in moment.images) {
      try {
        if (p.replaceAll('\\', '/').contains('/user_moments/')) {
          final f = File(p);
          if (f.existsSync()) f.deleteSync();
        }
      } catch (_) {}
    }
    final newMoments =
        character.moments.where((m) => m.id != moment.id).toList();
    await context.read<CharacterProvider>().updateMoments(
          character.id,
          newMoments,
        );
  }

  // ---------------- 展示 ----------------

  /// 小头像：已设置用图片，未设置用默认用户图标；形状跟随全局设置
  Widget _avatar(BuildContext context) {
    return CharacterAvatar(
      base64: character.avatar,
      size: 34,
      iconSize: 20,
    );
  }

  /// 图片文件存在性缓存：build 中不直接调用 File.existsSync（同步 IO 会阻塞
  /// 主线程，朋友圈图片多时滚动/重建卡顿）。图片文件只在删除动态时消失，
  /// 缓存命中后复用结果，超容量时整体清空。
  static final Map<String, bool> _imageExistsCache = {};

  static bool _imageExists(String path) =>
      _imageExistsCache.putIfAbsent(path, () {
        if (_imageExistsCache.length > 512) _imageExistsCache.clear();
        return File(path).existsSync();
      });

  /// 图片：最多 9 张，1 张大图、多张 3 列网格；缺失时只显示文字占位。
  /// 点击图片全屏预览。
  /// 解码尺寸按实际展示区域指定（cacheWidth/Height），避免原图全分辨率解码
  /// 造成大内存占用与滚动卡顿。
  Widget _images(BuildContext context) {
    final shown =
        moment.images.where(_imageExists).take(9).toList();
    if (shown.isEmpty) {
      return Text(
        '图片加载失败',
        style: TextStyle(
          fontSize: 12,
          color: context.textSecondaryColor,
        ),
      );
    }
    final screenWidth = MediaQuery.of(context).size.width;
    if (shown.length == 1) {
      // 单图：微信风格缩略图，按图片比例裁剪、不强制展示完整图片
      //（竖图 3:4、横图按原比例），点击进入全屏预览
      return _SingleImageThumb(
        path: shown.first,
        onTap: () => _previewImage(context, shown.first),
      );
    }
    // 多图：3 列网格，单格按卡片内可用宽度均分
    final cell = (screenWidth - 32 - 24 - 34 - 10 - 8) / 3;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final cellPx = (cell * dpr).round();
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: shown.map((p) {
        return GestureDetector(
          onTap: () => _previewImage(context, p),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: cell,
              height: cell,
              child: Image.file(
                File(p),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                cacheWidth: cellPx,
                cacheHeight: cellPx,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// 点赞 + 评论区：浅底块内先点赞昵称，再逐条评论（昵称蓝色）
  Widget _interactions(BuildContext context) {
    // 点赞去重：相同昵称只展示一个赞
    final likeNames = <String>[];
    for (final n in moment.likes) {
      if (!likeNames.contains(n)) likeNames.add(n);
    }
    final hasLikes = likeNames.isNotEmpty;
    final hasComments = moment.comments.isNotEmpty;
    if (!hasLikes && !hasComments) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: context.momentBlockColor,
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
                    likeNames.join('、'),
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
            ...moment.comments.asMap().entries.map(
              (entry) {
                final i = entry.key;
                final c = entry.value;
                // 自己的评论支持长按删除；管理模式下任意角色的评论也可长按删除/编辑
                final isMine = c.sender == _myName;
                final canCommentMenu = isMine || widget.manageMode;
                return GestureDetector(
                  onTap: () => _openCommentInput(replyToName: c.sender),
                  onLongPressStart: canCommentMenu
                      ? (details) =>
                          _showCommentMenu(details.globalPosition, i)
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: c.sender,
                            style: const TextStyle(color: Color(0xFF8FB8E8)),
                          ),
                          // 带回复评论：显示「A 回复了 B：内容」
                          if (c.replyTo.isNotEmpty) ...[
                            const TextSpan(text: ' 回复了 '),
                            TextSpan(
                              text: c.replyTo,
                              style: const TextStyle(
                                  color: Color(0xFF8FB8E8)),
                            ),
                          ],
                          const TextSpan(text: '：'),
                          TextSpan(text: c.content),
                        ],
                      ),
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: context.textPrimaryColor,
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  /// 全屏预览朋友圈图片：
  /// - 单击关闭；双击放大/缩小；双指缩放，放大后可自由拖动查看
  /// - 长按弹出【保存图片】到系统相册
  void _previewImage(BuildContext context, String path) {
    if (!File(path).existsSync()) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, __, ___) => _ImagePreviewPage(path: path),
      ),
    );
  }

  /// 时间显示：今天/昨天显示时分，同一年省略年份
  String _formatTime(DateTime? time) {
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
}

/// 评论输入栏：Overlay 悬浮在软键盘上方（底部随键盘上移），
/// 右侧圆形对号按钮确认发送，左侧下箭头收起键盘/关闭。
/// 输入栏上方不遮挡朋友圈内容，列表仍可滑动操作。
class _CommentInputBar extends StatefulWidget {
  final String? initialText;
  final String? replyToName;
  final VoidCallback onClose;
  final ValueChanged<String> onSend;

  const _CommentInputBar({
    required this.onClose,
    required this.onSend,
    this.initialText,
    this.replyToName,
  });

  @override
  State<_CommentInputBar> createState() => _CommentInputBarState();
}

class _CommentInputBarState extends State<_CommentInputBar> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    // 键盘弹出时 viewInsets.bottom 增大，输入栏随之悬浮到软键盘上方
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final canSend = _controller.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        padding: EdgeInsets.fromLTRB(
          6,
          8,
          12,
          8 + MediaQuery.of(context).padding.bottom,
        ),
        color: context.listBgColor,
        child: Row(
          children: [
            // 下箭头：收起键盘并关闭输入栏
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onClose,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  CupertinoIcons.chevron_down,
                  size: 18,
                  color: context.textSecondaryColor,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: CupertinoTextField(
                controller: _controller,
                autofocus: true,
                maxLength: 100,
                placeholder: widget.initialText != null
                    ? '编辑评论'
                    : (widget.replyToName != null
                        ? '回复 ${widget.replyToName}'
                        : '说点什么...'),
                placeholderStyle:
                    TextStyle(color: context.textSecondaryColor),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            // 对号按钮：确认发送
            GestureDetector(
              onTap: canSend ? _send : null,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: canSend
                      ? context.accentColor
                      : context.separatorColor,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  CupertinoIcons.checkmark_alt,
                  size: 18,
                  color: CupertinoColors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 朋友圈单图缩略图（微信风格）：
/// 不强制展示完整图片——竖图按 3:4 比例裁剪、横图按原比例，最大约 60%
/// 内容区宽度 / 220 高度。异步读取原图尺寸后计算展示尺寸，避免布局跳动。
class _SingleImageThumb extends StatefulWidget {
  final String path;
  final VoidCallback onTap;

  const _SingleImageThumb({required this.path, required this.onTap});

  @override
  State<_SingleImageThumb> createState() => _SingleImageThumbState();
}

class _SingleImageThumbState extends State<_SingleImageThumb> {
  /// 原图尺寸静态缓存：同一路径只异步读取一次。滚动中卡片 build/dispose
  /// 直接命中缓存，避免缩略图在「占位(3:4) ↔ 实际比例」间反复切换——
  /// 该高度反复变化会驱动列表内容 extent 振荡（→ 位置跳变 → ballistic
  /// 重启），即惯性滚动"抖动"的根因。
  static final Map<String, Size> _sizeCache = {};

  /// 原图尺寸（优先命中缓存；未知时按默认 3:4 占位）
  Size? _imgSize;

  @override
  void initState() {
    super.initState();
    _imgSize = _sizeCache[widget.path];
    if (_imgSize == null) _loadSize();
  }

  Future<void> _loadSize() async {
    try {
      // 仅解析图片头部元数据获取宽高，不整图解码，避免列表中出现大量
      // 单图缩略图时反复整图解码造成卡顿与内存峰值
      final bytes = await File(widget.path).readAsBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final size = Size(
        descriptor.width.toDouble(),
        descriptor.height.toDouble(),
      );
      descriptor.dispose();
      buffer.dispose();
      if (_sizeCache.length > 512) _sizeCache.clear();
      _sizeCache[widget.path] = size;
      if (mounted) setState(() => _imgSize = size);
    } catch (_) {
      // 尺寸读取失败时保持默认占位展示，不影响点开预览
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    // 卡片内容区可用宽度：屏宽 - 列表边距 16*2 - 卡片内边距 12*2 - 头像 34 - 间距 10
    final contentWidth = screenWidth - 32 - 24 - 34 - 10;
    final maxWidth = contentWidth * 0.6;
    const maxHeight = 220.0;

    double w;
    double h;
    final img = _imgSize;
    if (img == null) {
      // 未知尺寸：按 3:4 默认比例占位
      w = maxHeight * 0.75;
      h = maxHeight;
    } else {
      final aspect = img.width / img.height;
      if (aspect >= 1) {
        // 横图 / 方形：宽优先，高度按原比例，超出高度上限则按比例截断
        w = maxWidth;
        h = w / aspect;
        if (h > maxHeight) {
          h = maxHeight;
          w = h * aspect;
          if (w > maxWidth) w = maxWidth;
        }
      } else {
        // 竖图：微信风格 3:4 缩略图（cover 裁剪，不展示完整图片）
        w = maxHeight * 0.75;
        h = maxHeight;
        if (w > maxWidth) {
          w = maxWidth;
          h = w * 4 / 3;
        }
      }
    }

    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: w,
          height: h,
          child: Image.file(
            File(widget.path),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            cacheWidth: (w * dpr).round(),
            cacheHeight: (h * dpr).round(),
          ),
        ),
      ),
    );
  }
}

/// 朋友圈图片全屏预览页：
/// - 黑底全屏，图片按屏幕 contain 适配
/// - 双击放大 / 缩小；双指缩放；`constrained: false` 允许图片放大超出视口后自由拖动查看
/// - 长按弹出【保存图片】到系统相册
class _ImagePreviewPage extends StatefulWidget {
  final String path;

  const _ImagePreviewPage({required this.path});

  @override
  State<_ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<_ImagePreviewPage> {
  final TransformationController _transform = TransformationController();

  /// 图片适配屏幕后的展示尺寸（加载前为 null，此时用全屏占位）
  Size? _fittedSize;

  @override
  void initState() {
    super.initState();
    _loadImageSize();
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  /// 读取原图尺寸并按视口 contain 计算初始展示尺寸
  Future<void> _loadImageSize() async {
    Size img;
    try {
      // 仅解析头部元数据获取宽高（整图解码交给下方 Image.file 按需执行）
      final bytes = await File(widget.path).readAsBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      img = Size(
        descriptor.width.toDouble(),
        descriptor.height.toDouble(),
      );
      descriptor.dispose();
      buffer.dispose();
    } catch (_) {
      img = const Size(1, 1); // 解码失败时回退为全屏 contain
    }
    if (!mounted) return;
    final vp = MediaQuery.of(context).size;
    final scale = min(vp.width / img.width, vp.height / img.height);
    setState(() {
      _fittedSize = Size(img.width * scale, img.height * scale);
    });
  }

  /// 双击位置（onDoubleTapDown 记录，onDoubleTap 时使用）
  Offset _doubleTapPos = Offset.zero;

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

  Future<void> _saveImage() async {
    // gal 的 putImage 不会自行申请权限：Android 6–9（API 23–28）
    // 需要 WRITE_EXTERNAL_STORAGE 才能写入相册，先检查/申请权限再保存
    if (!await Gal.hasAccess()) {
      final granted = await Gal.requestAccess();
      if (!granted) {
        if (mounted) showAppToast('未获得相册权限，无法保存图片');
        return;
      }
    }
    try {
      await Gal.putImage(widget.path);
      if (mounted) showAppToast('已保存到系统相册');
    } on GalException catch (e) {
      if (!mounted) return;
      showAppToast(
        switch (e.type) {
          GalExceptionType.accessDenied => '未获得相册权限，无法保存图片',
          GalExceptionType.notEnoughSpace => '存储空间不足，保存失败',
          GalExceptionType.notSupportedFormat => '图片格式不支持保存',
          GalExceptionType.unexpected => '保存失败，请重试',
        },
      );
    } catch (_) {
      if (mounted) showAppToast('保存失败，请重试');
    }
  }

  /// 长按图片：弹出操作菜单（保存图片）
  void _showSaveSheet() {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('图片操作'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _saveImage();
            },
            child: const Text('保存图片'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.of(context).size;
    final fitted = _fittedSize;
    return ColoredBox(
      color: CupertinoColors.black,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 单击关闭；与双击共存时 Flutter 会等待双击判定，稍显延迟但可接受
        onTap: () => Navigator.of(context).pop(),
        onDoubleTapDown: (details) => _doubleTapPos = details.localPosition,
        onDoubleTap: _toggleZoom,
        onLongPress: _showSaveSheet,
        child: InteractiveViewer(
          transformationController: _transform,
          // 注意：constrained:false 时子组件锚定在视口左上角（不居中），
          // 因此子组件必须是整屏大小的盒子，图片在其内部居中，
          // 否则适配屏幕后的小图会偏移到屏幕顶部。
          constrained: false,
          boundaryMargin: const EdgeInsets.all(200),
          minScale: 1,
          maxScale: 6,
          child: SizedBox(
            width: viewport.width,
            height: viewport.height,
            child: fitted == null
                ? const Center(child: CupertinoActivityIndicator())
                : Center(
                    child: SizedBox(
                      width: fitted.width,
                      height: fitted.height,
                      child: Image.file(
                        File(widget.path),
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
