import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/motion.dart';
import '../config/theme.dart';
import 'moments/moment_media_widgets.dart';
import 'moments/moment_interactions.dart';
import '../models/character.dart';
import '../models/moment.dart';
import '../providers/auth_provider.dart';
import '../providers/character_provider.dart';
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

  /// 详情页模式：正文始终展开，评论显示全部。
  final bool detailMode;

  /// 一级列表中的“全文/查看全部评论”入口回调。
  final VoidCallback? onOpenDetail;

  /// 详情页固定评论栏使用的回复回调；为空时沿用卡片内 Overlay 输入栏。
  final ValueChanged<String?>? onReplyRequested;

  const MomentCard({
    super.key,
    required this.character,
    required this.moment,
    this.manageMode = false,
    this.detailMode = false,
    this.onOpenDetail,
    this.onReplyRequested,
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

  /// 长文是否已展开（折叠态默认最多 6 行，避免长文反复 layout 拖慢滚动）
  bool _expanded = false;
  final Map<Object, bool> _textMeasureCache = <Object, bool>{};

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
                      _content(context),
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
              if (widget.onReplyRequested != null) {
                widget.onReplyRequested!(null);
              } else {
                _openCommentInput();
              }
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
            Icon(icon, size: 18, color: color ?? context.textSecondaryColor),
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
    await updateMomentData(
      context,
      character: character,
      moment: moment,
      likes: likes,
      comments: comments,
      replaced: replaced,
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
            child: CommentInputBar(
              initialText: editIndex != null &&
                      editIndex >= 0 &&
                      editIndex < moment.comments.length
                  ? moment.comments[editIndex].content
                  : null,
              replyToName: replyToName,
              onClose: _closeCommentInput,
              onSend: (text) => _submitComment(text,
                  editIndex: editIndex, replyTo: replyToName),
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
    submitMomentComment(
      context,
      character: character,
      moment: moment,
      text: text,
      replyTo: replyTo,
      editIndex: editIndex,
      manageMode: widget.manageMode,
    );
  }

  /// 长按可管理的评论：在长按位置弹出悬浮菜单。
  /// 自己的评论可【编辑】【删除】；回复自己的 / 自己贴文下的评论仅【删除】。
  void _showCommentMenu(Offset globalPos, int index, {required bool canEdit}) {
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
                  if (canEdit) ...[
                    _menuItem(
                      icon: CupertinoIcons.pencil,
                      label: '编辑评论',
                      onTap: () {
                        _dismissMenu();
                        _openCommentInput(editIndex: index);
                      },
                    ),
                    _menuDivider(),
                  ],
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

  /// 动态正文：超过 6 行默认折叠为「全文」（微信风格）。
  /// 折叠态只渲染 6 行，长文的换行排版成本被限制，滚动时帧率更稳。
  Widget _content(BuildContext context) {
    if (widget.detailMode) {
      return Text(
        moment.content,
        style: TextStyle(
          fontSize: 15,
          height: 1.4,
          color: context.textPrimaryColor,
        ),
      );
    }
    const maxLines = 6;
    final style = TextStyle(
      fontSize: 15,
      height: 1.4,
      color: context.textPrimaryColor,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final needFold = !_expanded &&
            (moment.content.runes.length > 150 ||
                _textExceeds(context, moment.content, style, maxLines,
                    constraints.maxWidth));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              moment.content,
              maxLines: _expanded ? null : maxLines,
              overflow: _expanded ? null : TextOverflow.ellipsis,
              style: style,
            ),
            if (needFold)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _openDetailOrExpand,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '全文',
                    style: TextStyle(fontSize: 14, color: context.accentColor),
                  ),
                ),
              ),
            if (_expanded)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _expanded = false),
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '收起',
                    style: TextStyle(fontSize: 14, color: context.accentColor),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// 用 TextPainter 测量正文是否超过 [maxLines] 行。
  /// 仅折叠态且每张卡片一次 build 测量一次，成本与渲染该文本相当。
  bool _textExceeds(
    BuildContext context,
    String text,
    TextStyle style,
    int maxLines,
    double maxWidth,
  ) {
    final textScaler = MediaQuery.textScalerOf(context);
    final cacheKey = Object.hash(
      moment.id,
      text.hashCode,
      maxLines,
      maxWidth.round(),
      textScaler.scale(1).toStringAsFixed(3),
    );
    final cached = _textMeasureCache[cacheKey];
    if (cached != null) return cached;
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: maxLines,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: maxWidth);
    final exceeds = tp.didExceedMaxLines;
    if (_textMeasureCache.length >= 64) _textMeasureCache.clear();
    _textMeasureCache[cacheKey] = exceeds;
    return exceeds;
  }

  void _openDetailOrExpand() {
    final callback = widget.onOpenDetail;
    if (callback != null) {
      callback();
    } else {
      setState(() => _expanded = true);
    }
  }

  /// 图片：最多 9 张，1 张大图、多张 3 列网格；缺失时只显示文字占位。
  /// 点击图片全屏预览。
  /// 解码按 cover 所需像素等比缩放（禁止同时写死宽高硬拉伸），
  /// 避免原图全分辨率解码造成大内存占用与滚动卡顿。
  Widget _images(BuildContext context) {
    // 不在 build 中同步检查文件存在性；Image.file 的 errorBuilder 会为
    // 缺失/损坏文件提供同样的占位，避免滚动时阻塞 UI isolate。
    final shown = moment.images.take(9).toList();
    final screenWidth = MediaQuery.of(context).size.width;
    if (shown.length == 1) {
      // 单图：微信风格缩略图，按图片比例裁剪、不强制展示完整图片
      //（竖图 3:4、横图按原比例），点击进入全屏预览
      return SingleImageThumb(
        path: shown.first,
        onTap: () => _previewImage(context, shown.first),
      );
    }
    // 多图：3 列网格，单格按卡片内可用宽度均分
    final cell = (screenWidth - 32 - 24 - 34 - 10 - 8) / 3;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    // 只约束解码宽度：同时写 cacheWidth/Height 会按盒子尺寸硬拉伸，长图变矮胖
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
                // 顶部对齐：长图/竖图先露出内容开头，避免居中裁成一条细缝
                alignment: Alignment.topCenter,
                gaplessPlayback: true,
                cacheWidth: cellPx,
                // 缩略图尺寸小，低过滤质量视觉无差别，滚动光栅化更快
                filterQuality: FilterQuality.low,
                errorBuilder: (_, __, ___) => imagePlaceholder(context),
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
    final showCommentLimit = !widget.detailMode && moment.comments.length > 10;
    final visibleComments =
        showCommentLimit ? moment.comments.take(3).toList() : moment.comments;
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
            ...visibleComments.asMap().entries.map(
              (entry) {
                final i = entry.key;
                final c = entry.value;
                // 长按评论可管理的情形：
                // - 评论是"我"发的（可编辑/删除）
                // - 评论回复了"我"（回复自己的，可删除）
                // - 这条贴文是"我"发布的（自己贴文下的评论，可删除）
                // - 管理模式下任意评论（可编辑/删除）
                final isMine = c.sender == _myName;
                final repliedToMe = c.replyTo.isNotEmpty &&
                    (c.replyTo == _myName || c.replyTo == '我');
                final canDelete =
                    isMine || repliedToMe || _isSelf || widget.manageMode;
                final canEdit = isMine || widget.manageMode;
                return GestureDetector(
                  onTap: widget.onReplyRequested != null
                      ? () => widget.onReplyRequested!(c.sender)
                      : () => _openCommentInput(replyToName: c.sender),
                  onLongPressStart: canDelete
                      ? (details) => _showCommentMenu(
                            details.globalPosition,
                            i,
                            canEdit: canEdit,
                          )
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
                              style: const TextStyle(color: Color(0xFF8FB8E8)),
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
          if (showCommentLimit)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onOpenDetail,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '查看全部 ${moment.comments.length} 条评论',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.accentColor,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 全屏预览朋友圈图片：
  /// - 单击关闭；双击放大/缩小；双指缩放，放大后可自由拖动查看
  /// - 长按弹出【保存图片】到系统相册
  Future<void> _previewImage(BuildContext context, String path) async {
    // 点击行为不是滚动热路径，异步检查文件避免同步 I/O 阻塞首帧。
    if (!await File(path).exists() || !context.mounted) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: AppMotion.base,
        reverseTransitionDuration: AppMotion.quick,
        pageBuilder: (_, __, ___) => ImagePreviewPage(path: path),
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

/// 图片解码失败占位：文件损坏等异常时不白屏，显示灰色相机占位

/// 按 BoxFit.cover 所需像素等比计算解码目标尺寸。
/// Flutter 在 cacheWidth/Height 同时非空时会忽略原图比例硬缩放，
/// 必须用原图宽高换算，否则长图会被压成矮胖。
/// [image] 为空时只约束宽度，高度不传（跟随原图比例）。
