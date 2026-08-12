import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../providers/api_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/chat_settings_provider.dart';
import '../providers/character_provider.dart';
import '../services/chat_records_service.dart';
import '../services/llm_service.dart';
import '../utils/file_picker_helper.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/character_avatar.dart';
import '../widgets/message_input.dart';
import 'chat_detail_screen.dart';
import 'chat_settings_screen.dart';
import 'forward_detail_screen.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String characterName;
  final String characterAvatar;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.characterName,
    this.characterAvatar = '',
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<MessageInputState> _inputKey = GlobalKey<MessageInputState>();
  // 时间标签用的 DateFormat 只创建一次（DateFormat 构造开销较大，长会话频繁重建时明显）
  static final DateFormat _timeFmt = DateFormat('HH:mm');
  static final DateFormat _dateFmt = DateFormat('M月d日 HH:mm');
  static final DateFormat _fullFmt = DateFormat('yyyy年M月d日 HH:mm');
  Message? _quoteMessage;
  OverlayEntry? _menuOverlay;
  String? _pendingImagePath; // 最近发送的图片：对号按钮按下时随回复传给模型
  bool _selectMode = false; // 多选转发模式
  final Set<String> _selectedIds = {}; // 多选模式下选中的消息 id
  ChatProvider? _chatProvider; // 生命周期内复用（dispose 中仍需访问）
  int _lastRenderedCount = -1; // 已渲染消息条数（用于新消息自动滚底）
  bool _keyboardVisible = false; // 软键盘是否弹出（用于键盘弹出时保持列表滚底）

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 打开会话：清除未读并记录当前会话（此后角色新消息不再计入未读）
    _chatProvider = context.read<ChatProvider>();
    _chatProvider!.markConversationActive(widget.conversationId);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 退到后台/切到其他应用（未 pop 路由、dispose 不会触发）：
    // 视为"离开聊天界面"，此后角色新消息计入未读；回到前台重新进入会话时清除未读
    if (_chatProvider == null) return;
    switch (state) {
      case AppLifecycleState.resumed:
        debugPrint(
            '[ChatScreen] resumed → markConversationActive ${widget.conversationId}');
        _chatProvider!.markConversationActive(widget.conversationId);
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        debugPrint(
            '[ChatScreen] $state → markConversationInactive ${widget.conversationId}');
        _chatProvider!.markConversationInactive(widget.conversationId);
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break; // 短暂遮挡（来电/系统弹层等）不改变未读状态
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 退出会话：恢复未读计数（若 AI 仍在后台回复，新消息将记未读并点亮主页红点）
    _chatProvider?.markConversationInactive(widget.conversationId);
    _menuOverlay?.remove();
    _scrollController.dispose();
    super.dispose();
  }

  /// 列表是否已停在底部（reverse 列表 offset 0 即视觉底部）。
  /// 新消息在 reverse 列表下直接追加到视觉底部，已贴底时无需再滚动。
  bool _isAtBottom() {
    if (!_scrollController.hasClients) return true;
    return _scrollController.position.pixels <= 1;
  }

  /// 滚动到底部。列表为 reverse: true，offset 0 即视觉底部。
  void _scrollToBottom({bool animate = true}) {
    if (_scrollController.hasClients) {
      if (animate) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (!_scrollController.hasClients) return;
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        });
      } else {
        _scrollController.jumpTo(0);
      }
    }
  }

  /// 键盘弹出动画期间视口持续缩小：分几次跟随滚动到底部，
  /// 确保键盘动画结束后列表仍停留在新的最底部
  void _scrollToBottomWhileKeyboardShows() {
    void follow() {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(0);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => follow());
    Future.delayed(const Duration(milliseconds: 120), follow);
    Future.delayed(const Duration(milliseconds: 300), follow);
  }

  /// 打开聊天设置（模型/上下文条数）
  void _openChatSettings() {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) =>
            ChatSettingsScreen(conversationId: widget.conversationId),
      ),
    );
  }

  /// 导出当前聊天记录为 zip 包（chat.json + 聊天中的图片/文件），
  /// 通过系统"保存文件"选择器由用户自选保存位置。
  Future<void> _exportChat() async {
    final messages =
        context.read<ChatProvider>().getMessages(widget.conversationId);
    if (messages.isEmpty) {
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('提示'),
          content: const Text('暂无聊天记录可导出'),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('确定'),
            ),
          ],
        ),
      );
      return;
    }

    try {
      final bytes = await ChatRecordsService.buildExportZip(
        characterName: widget.characterName,
        messages: messages,
      );
      if (!mounted) return;

      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final fileName = '${widget.characterName}_聊天记录_'
          '${now.year}${two(now.month)}${two(now.day)}_'
          '${two(now.hour)}${two(now.minute)}${two(now.second)}.zip';
      final savedName = await FilePickerHelper.saveFile(
        suggestedName: fileName,
        mimeType: 'application/zip',
        bytes: bytes,
      );
      if (!mounted) return;
      if (savedName == null) return; // 用户取消保存

      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('导出成功'),
          content: Text(
            '已将 ${messages.length} 条聊天记录（含聊天中的图片/文件）保存为 zip 文件：$savedName',
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showImportExportError('导出失败', '打包聊天记录时出错：$e');
    }
  }

  /// 导入聊天记录 zip：选择 zip → 解析 → 提取图片/文件 → 追加到当前会话
  Future<void> _importChat() async {
    try {
      final picked = await FilePickerHelper.pickFile();
      if (picked == null || !mounted) return; // 用户取消选择
      if (!picked.name.toLowerCase().endsWith('.zip')) {
        _showImportExportError('导入失败', '请选择聊天记录 zip 文件');
        return;
      }

      final chatProvider = context.read<ChatProvider>();
      final messages = await ChatRecordsService.importZip(
        zipPath: picked.path,
        conversationId: widget.conversationId,
      );
      if (messages.isEmpty) {
        _showImportExportError('导入失败', '压缩包中没有可导入的消息');
        return;
      }
      await chatProvider.importMessages(
        conversationId: widget.conversationId,
        messages: messages,
      );
      if (!mounted) return;
      _scrollToBottom();
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('导入成功'),
          content: Text(
            '已将 ${messages.length} 条聊天记录导入到当前会话（${picked.name}）',
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showImportExportError('导入失败', '$e');
    }
  }

  void _showImportExportError(String title, String message) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  // ─── 长按气泡菜单 ───────────────────────────────────────────

  /// 长按气泡：在气泡旁弹出灰色面板
  void _showBubbleMenu(Message message, GlobalKey bubbleKey) {
    _menuOverlay?.remove();

    // 先构建菜单项列表，用于计算菜单宽度
    final items = _buildMenuItems(message);

    // 获取气泡在屏幕上的位置
    final RenderBox? renderBox =
        bubbleKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final bubblePosition = renderBox.localToGlobal(Offset.zero);
    final bubbleSize = renderBox.size;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // 菜单宽度（3项至少260，2项至少190）
    final double menuWidth = items.length > 2 ? 260 : 190;
    // 菜单高度：5 项以上会换行成两行（64 → 128）
    final double menuHeight = items.length > 4 ? 128 : 64;

    // 计算 X：我方气泡在右侧，菜单靠左；对方气泡在左侧，菜单靠右
    double left;
    if (message.isFromUser) {
      left = bubblePosition.dx - menuWidth - 8;
      if (left < 8) left = 8;
    } else {
      left = bubblePosition.dx + bubbleSize.width + 8;
      if (left + menuWidth > screenWidth - 8) {
        left = screenWidth - menuWidth - 8;
      }
    }

    // 计算 Y：垂直居中于气泡，但不能超出屏幕顶部和底部
    double top = bubblePosition.dy + (bubbleSize.height - menuHeight) / 2;
    if (top < 80) top = 80; // 导航栏下方
    if (top + menuHeight > screenHeight - 80) {
      top = screenHeight - menuHeight - 80; // 底部输入栏上方
    }

    _menuOverlay = OverlayEntry(
      builder: (_) => Stack(
        children: [
          // 半透明遮罩（点击关闭菜单）
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _closeMenu,
            ),
          ),
          // 菜单面板
          Positioned(
            left: left,
            top: top,
            width: menuWidth,
            child: _buildMenuPanel(message, items),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_menuOverlay!);
  }

  void _closeMenu() {
    _menuOverlay?.remove();
    _menuOverlay = null;
  }

  /// 构建菜单项列表
  List<Widget> _buildMenuItems(Message message) {
    final isUser = message.isFromUser;
    final items = <Widget>[
      _menuItem(
        icon: CupertinoIcons.doc_on_doc,
        label: '复制',
        onTap: () {
          _closeMenu();
          Clipboard.setData(ClipboardData(text: message.content));
        },
      ),
      _menuItem(
        icon: CupertinoIcons.text_badge_checkmark,
        label: '选择文本',
        onTap: () {
          _closeMenu();
          _showTextSelection(message);
        },
      ),
      _menuItem(
        icon: CupertinoIcons.quote_bubble,
        label: '引用',
        onTap: () {
          _closeMenu();
          setState(() {
            _quoteMessage = message;
          });
        },
      ),
    ];

    if (isUser) {
      items.add(
        _menuItem(
          icon: CupertinoIcons.xmark_circle,
          label: '撤回',
          onTap: () {
            _closeMenu();
            _withdrawMessage(message);
          },
        ),
      );
    } else {
      items.add(
        _menuItem(
          icon: CupertinoIcons.refresh,
          label: '重新回复',
          onTap: () {
            _closeMenu();
            _rerollReply(message);
          },
        ),
      );
    }

    items.add(
      _menuItem(
        icon: CupertinoIcons.square_stack,
        label: '多选',
        onTap: () {
          _closeMenu();
          _enterSelectMode(message);
        },
      ),
    );

    return items;
  }

  /// 选择文本：弹窗显示消息文本，用户可长按选择复制
  void _showTextSelection(Message message) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('选择文本'),
        content: CupertinoTextField(
          controller: TextEditingController(text: message.content),
          maxLines: null,
          readOnly: true,
          style: TextStyle(
            fontSize: 15,
            color: context.textPrimaryColor,
          ),
          decoration: const BoxDecoration(
            color: CupertinoColors.transparent,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('关闭'),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuPanel(Message message, List<Widget> items) {

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey6.resolveFrom(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: CupertinoColors.systemGrey4.resolveFrom(context),
          width: 0.5,
        ),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: items,
      ),
    );
  }

  Widget _menuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: context.textPrimaryColor),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: context.textPrimaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 撤回消息（我方）：终止 AI 思考，删除消息，内容放入输入框供重新编辑
  void _withdrawMessage(Message message) {
    context
        .read<ChatProvider>()
        .withdrawMessage(widget.conversationId, message.id);
    // 撤回后将消息内容放入输入框
    _inputKey.currentState?.setText(message.content);
    _inputKey.currentState?.focus();
    // 若撤回的是被引用消息，清空引用
    if (_quoteMessage?.id == message.id) {
      setState(() {
        _quoteMessage = null;
      });
    }
  }

  /// 重新回复：删除当前 AI 回复，重新发送上一条用户消息
  void _rerollReply(Message aiMessage) {
    final chatProvider = context.read<ChatProvider>();
    final messages = chatProvider.getMessages(widget.conversationId);
    // 找到该 AI 消息前面的最后一条用户消息
    Message? lastUserMessage;
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].id == aiMessage.id) continue;
      if (messages[i].isFromUser) {
        lastUserMessage = messages[i];
        break;
      }
    }
    if (lastUserMessage == null) return;

    // 删除该 AI 回复和之前的用户消息
    chatProvider.deleteMessage(widget.conversationId, aiMessage.id);
    chatProvider.deleteMessage(widget.conversationId, lastUserMessage.id);

    // 重新发送（带上原消息内容）
    _handleSend(lastUserMessage.content);
  }

  /// 发送消息（携带引用）：只发送用户消息，不自动触发模型回复，
  /// 由用户点击输入框右侧的"对号"按钮手动触发角色回复。
  void _handleSend(String content) {
    final quote = _quoteMessage;
    context.read<ChatProvider>().sendMessage(
          conversationId: widget.conversationId,
          content: content,
          quoteContent: quote?.content ?? '',
          quoteSender: quote == null
              ? ''
              : (quote.isFromUser ? '我' : widget.characterName),
        );
    // 发送后清空引用
    if (_quoteMessage != null) {
      setState(() {
        _quoteMessage = null;
      });
    }
  }

  /// 取消引用
  void _clearQuote() {
    setState(() {
      _quoteMessage = null;
    });
  }

  // ─── 多选转发 ─────────────────────────────────────────────

  /// 从长按菜单进入多选模式（默认选中当前长按的消息）
  void _enterSelectMode(Message message) {
    setState(() {
      _selectMode = true;
      _selectedIds.add(message.id);
    });
  }

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selectedIds.clear();
    });
  }

  /// 多选模式下点击气泡切换选中状态
  void _toggleSelect(Message message) {
    setState(() {
      if (!_selectedIds.remove(message.id)) {
        _selectedIds.add(message.id);
      }
    });
  }

  /// 转发选中的消息到其他会话；merge=true 合并转发，否则逐条转发
  Future<void> _forwardMessages({required bool merge}) async {
    final chatProvider = context.read<ChatProvider>();
    final messages = chatProvider
        .getMessages(widget.conversationId)
        .where((m) => _selectedIds.contains(m.id))
        .toList();
    if (messages.isEmpty) return;

    final target = await _pickTargetConversation();
    if (target == null || !mounted) return;

    final conversation = chatProvider.conversations
        .where((c) => c.id == widget.conversationId)
        .firstOrNull;
    final character = conversation != null
        ? context
            .read<CharacterProvider>()
            .getCharacterById(conversation.characterId)
        : null;
    final sourceName = character?.displayName ?? widget.characterName;
    final sourceAvatar = character?.avatar ?? '';

    if (merge) {
      await chatProvider.forwardMerged(
        conversationId: target.id,
        sourceName: sourceName,
        sourceAvatar: sourceAvatar,
        messages: messages,
      );
    } else {
      await chatProvider.forwardIndividually(
        conversationId: target.id,
        messages: messages,
      );
    }
    if (!mounted) return;
    _exitSelectMode();
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('转发成功'),
        content: Text(
          '已将 ${messages.length} 条消息${merge ? '（合并）' : ''}转发到「${target.characterName}」',
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 弹出目标会话选择器（排除当前会话）
  Future<Conversation?> _pickTargetConversation() async {
    final chatProvider = context.read<ChatProvider>();
    final candidates = chatProvider.conversations
        .where((c) => c.id != widget.conversationId)
        .toList();
    if (candidates.isEmpty) {
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('提示'),
          content: const Text('暂无可转发的聊天，请先创建其他聊天'),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('确定'),
            ),
          ],
        ),
      );
      return null;
    }
    return showCupertinoModalPopup<Conversation>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(8),
          height: min(360.0, candidates.length * 56.0 + 96.0),
          decoration: BoxDecoration(
            color: context.listBgColor,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '转发到',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimaryColor,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                height: 0.5,
                color: context.separatorColor,
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: candidates.length,
                  itemBuilder: (context, index) {
                    final c = candidates[index];
                    return CupertinoListTile(
                      leading: _buildConvAvatar(c),
                      title: Text(
                        c.characterName,
                        style: TextStyle(
                          fontSize: 16,
                          color: context.textPrimaryColor,
                        ),
                      ),
                      onTap: () => Navigator.pop(ctx, c),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 消息时间标签：居中显示在聊天气泡间隙上，
  /// 仅在会话首条或与上一条消息间隔超过 10 分钟时展示
  Widget _buildTimeLabel(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(time.year, time.month, time.day);
    String text;
    if (day == today) {
      text = _timeFmt.format(time);
    } else if (day.year == now.year) {
      text = _dateFmt.format(time);
    } else {
      text = _fullFmt.format(time);
    }
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: context.textSecondaryColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: context.textSecondaryColor,
          ),
        ),
      ),
    );
  }

  Widget _buildConvAvatar(Conversation c) {
    // 头像框样式跟随全局设置（方形 / 仿 QQ 圆形）
    return CharacterAvatar(
      base64: c.characterAvatar,
      size: 40,
      borderRadius: BorderRadius.circular(6),
    );
  }

  /// 多选模式底部操作栏：取消 + 已选数量 + 逐条/合并转发
  Widget _buildSelectBar(BuildContext context) {
    final count = _selectedIds.length;
    return Container(
      color: context.navBarColor,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              onPressed: _exitSelectMode,
              child: Text(
                '取消',
                style: TextStyle(
                  fontSize: 15,
                  color: context.textSecondaryColor,
                ),
              ),
            ),
            Expanded(
              child: Text(
                '已选 $count 条',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: context.textPrimaryColor,
                ),
              ),
            ),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              onPressed: count > 0 ? () => _forwardMessages(merge: false) : null,
              child: Text(
                '逐条转发',
                style: TextStyle(
                  fontSize: 15,
                  color: count > 0
                      ? context.accentColor
                      : context.textSecondaryColor,
                ),
              ),
            ),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              onPressed: count > 0 ? () => _forwardMessages(merge: true) : null,
              child: Text(
                '合并转发',
                style: TextStyle(
                  fontSize: 15,
                  color: count > 0
                      ? context.accentColor
                      : context.textSecondaryColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 点击"聊天记录"卡片进入合并转发详情页
  void _openForwardDetail(
    Message message, {
    required String userAvatar,
    required String characterAvatar,
  }) {
    if (message.forwardedItems.isEmpty) return;
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => ForwardDetailScreen(
          items: message.forwardedItems,
          userAvatar: userAvatar,
          characterAvatar: characterAvatar,
        ),
      ),
    );
  }

  // ─── 功能检测（模型是否支持图片发送） ─────────────────────

  /// 【功能检测】测试当前选中的模型是否支持图片发送；
  /// 支持则返回 true（面板据此开启【相册】【拍照】）。
  Future<bool> _runFeatureDetect() async {
    final chatSettings = context.read<ChatSettingsProvider>();
    final model = context
        .read<ApiProvider>()
        .getModelById(chatSettings.selectedModelId);
    if (model == null) {
      _showFeatureResult('请先在「聊天设置」中选择一个模型，再进行功能检测。', false);
      return false;
    }
    try {
      final supported = await LLMService.testImageSupport(model);
      if (!mounted) return supported;
      // 记住检测结果：视觉模型检测过一次后，聊天页直接放开图片发送
      await context.read<ApiProvider>().setVisionSupported(model.id, supported);
      _showFeatureResult(
        supported
            ? '「${model.displayName}」支持图片发送，【相册】【拍照】已开启。'
            : '「${model.displayName}」不支持图片发送，【相册】【拍照】保持禁用。',
        supported,
      );
      return supported;
    } catch (e) {
      if (!mounted) return false;
      _showFeatureResult('功能检测失败：${LLMService.describeException(e)}', false);
      return false;
    }
  }

  void _showFeatureResult(String message, bool supported) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(supported ? '检测成功' : '检测结果'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  // ─── 角色主动发消息 ───────────────────────────────────────

  /// 触发"角色主动发消息/回复"：组装参数后交给 [ChatProvider.runProactiveReply]
  /// 在应用级单例中执行——即使此时退出聊天界面，AI 回复也会继续生成并完整入库。
  ///
  /// [replyToUser] 为 true 时（输入框对号按钮触发）模型针对用户最近的消息分条回复。
  /// [imagePath] 非空时表示"发送图片"：图片会以视觉消息传给模型，让角色看到图片后回复。
  Future<void> _triggerProactiveMessages({
    bool replyToUser = false,
    String? imagePath,
  }) async {
    debugPrint('[ChatScreen] _triggerProactiveMessages: replyToUser=$replyToUser imagePath=$imagePath');
    final chatSettings = context.read<ChatSettingsProvider>();
    final model = context
        .read<ApiProvider>()
        .getModelById(chatSettings.selectedModelId);
    if (model == null) {
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('提示'),
          content: const Text('请先在「聊天设置」中选择一个模型，再进行角色回复'),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('确定'),
            ),
          ],
        ),
      );
      return;
    }

    final chatProvider = context.read<ChatProvider>();
    final conversation = chatProvider.conversations
        .where((c) => c.id == widget.conversationId)
        .firstOrNull;
    final character = conversation != null
        ? context
            .read<CharacterProvider>()
            .getCharacterById(conversation.characterId)
        : null;
    final characterName = character?.displayName ?? widget.characterName;

    // 会话压缩：压缩模型默认跟随聊天模型，可在「API 设置 → 会话压缩」中单独指定
    final api = context.read<ApiProvider>();
    final compressModel =
        api.getModelById(api.compressionModelId) ?? model;

    final messages = await chatProvider.runProactiveReply(
      conversationId: widget.conversationId,
      model: model,
      characterName: characterName,
      characterSystemPrompt: character?.systemPrompt ?? '',
      userRelationship: character?.userRelationship ?? '',
      userNickname:
          context.read<AuthProvider>().user?.nickname ?? '用户',
      replyToUser: replyToUser,
      contextCount: chatSettings.contextCount,
      enableCompression: chatSettings.enableCompression,
      compressModel: compressModel,
      contextLength: model.contextLength,
      compressThreshold: chatSettings.compressThreshold,
      imagePath: imagePath,
    );
    debugPrint('[ChatScreen] runProactiveReply 完成: ${messages.length} 条, lastError=${chatProvider.lastError}, mounted=$mounted');
    if (!mounted) return;
    if (messages.isEmpty && chatProvider.lastError == null) {
      // 模型主动返回空数组（如时间不合理）时给出轻提示
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('提示'),
          content: const Text('角色暂时没有想说的话'),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    }
  }

  /// 选择图片后发送图片消息：先本地插入图片气泡；与文本消息一致，
  /// 不立即触发回复，等待输入框右侧对号按钮按下后把图片随回复传给模型
  Future<void> _handlePickImage(String imagePath) async {
    final chatSettings = context.read<ChatSettingsProvider>();
    await context.read<ChatProvider>().sendImageMessage(
          conversationId: widget.conversationId,
          imagePath: imagePath,
          characterName: widget.characterName,
          contextCount: chatSettings.contextCount,
        );
    if (!mounted) return;
    _scrollToBottom();
    _pendingImagePath = imagePath;
  }

  /// 选择文件后发送文件消息
  void _handlePickFile(String filePath, String fileName) {
    context.read<ChatProvider>().sendFileMessage(
          conversationId: widget.conversationId,
          filePath: filePath,
          fileName: fileName,
        );
  }

  /// 点击文件消息：调用系统"打开方式"打开本地文件，失败时弹提示
  Future<void> _openFileMessage(String filePath) async {
    final error = await FilePickerHelper.openFile(filePath);
    if (!mounted || error == null) return;
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('无法打开文件'),
        content: Text(error),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 实时显示名：优先使用角色资料中的备注/昵称
    final chatProvider = context.watch<ChatProvider>();
    // 当前模型是否已检测为视觉模型（检测过一次即记住）：
    // 命中缓存则直接放开聊天页的图片发送，无需重复检测
    final api = context.watch<ApiProvider>();
    final chatSettings = context.watch<ChatSettingsProvider>();
    final visionReady =
        api.isVisionSupported(chatSettings.selectedModelId) == true;
    final conversation = chatProvider.conversations
        .where((c) => c.id == widget.conversationId)
        .firstOrNull;
    final character = conversation != null
        ? context
            .watch<CharacterProvider>()
            .getCharacterById(conversation.characterId)
        : null;
    final displayName = character?.displayName ?? widget.characterName;

    // 软键盘弹出瞬间：若此前列表已在最底部，则跟随键盘动画持续滚底，
    // 避免最新消息被键盘遮挡（若用户已上滑阅读旧消息则不打扰）
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    if (keyboardVisible && !_keyboardVisible) {
      _keyboardVisible = true;
      if (_scrollController.hasClients) {
        final position = _scrollController.position;
        if (position.pixels <= 1) {
          _scrollToBottomWhileKeyboardShows();
        }
      }
    } else if (!keyboardVisible && _keyboardVisible) {
      _keyboardVisible = false;
    }

    // 对号按钮可用性：上一条消息是用户发送时才可点（角色还没回复）
    final lastMessage = chatProvider.getMessages(widget.conversationId).lastOrNull;
    final replyEnabled = lastMessage != null && lastMessage.isFromUser;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        // 多选模式显示标题；否则角色回复生成/渲染期间标题变为"对方正在输入……"
        middle: Text(_selectMode
            ? '选择消息'
            : (chatProvider.isReplying(widget.conversationId)
                ? '对方正在输入……'
                : displayName)),
        trailing: _selectMode
            ? null
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () {
                  // 三条横线：进入角色与设置二级界面
                  Navigator.push(
                    context,
                    CupertinoPageRoute(
                      builder: (_) => ChatDetailScreen(
                        conversationId: widget.conversationId,
                        characterName: displayName,
                      ),
                    ),
                  );
                },
                child: const Icon(CupertinoIcons.line_horizontal_3),
              ),
      ),
      child: Column(
        children: [
          Expanded(
            child: Consumer<ChatProvider>(
              builder: (context, chatProvider, _) {
                final messages =
                    chatProvider.getMessages(widget.conversationId);

                // 消息条数增加（AI 逐条回复等）且界面可见时自动滚动到底部；
                // 首次进入 reverse 列表初始即在底部，不触发滚动；
                // 已贴底时新消息直接可见，无需再调度滚动
                if (messages.length != _lastRenderedCount) {
                  final added = _lastRenderedCount >= 0 &&
                      messages.length > _lastRenderedCount;
                  _lastRenderedCount = messages.length;
                  if (added && !_isAtBottom()) _scrollToBottom();
                }

                // 双方头像（base64）
                final userAvatar =
                    context.read<AuthProvider>().user?.avatar ?? '';
                String characterAvatar = widget.characterAvatar;
                final conversation = chatProvider.conversations
                    .where((c) => c.id == widget.conversationId)
                    .firstOrNull;
                if (conversation != null) {
                  final character = context
                      .read<CharacterProvider>()
                      .getCharacterById(conversation.characterId);
                  if (character != null && character.avatar.isNotEmpty) {
                    characterAvatar = character.avatar;
                  }
                }

                if (messages.isEmpty) {
                  return ColoredBox(
                    color: context.chatBgColor,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            CupertinoIcons.person_2_fill,
                            size: 48,
                            color: context.textSecondaryColor,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '和 $displayName 开始聊天吧',
                            style: TextStyle(
                              fontSize: 16,
                              color: context.textSecondaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // 列表使用 reverse: true，首帧即停在底部（最新消息），
                // 不会出现"从顶部滑到底部"的视觉。
                return Container(
                  color: context.chatBgColor,
                  child: ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      // 反向列表：index 0 对应最新一条消息
                      final msg = messages[messages.length - 1 - index];
                      final prev = index < messages.length - 1
                          ? messages[messages.length - 2 - index]
                          : null;
                      // 与上一条消息间隔超过 10 分钟才显示时间（第一条总是显示）
                      final showTime = prev == null ||
                          msg.createdAt
                                  .difference(prev.createdAt)
                                  .inMinutes >=
                              10;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (showTime) _buildTimeLabel(msg.createdAt),
                          ChatBubble(
                            message: msg,
                            userAvatar: userAvatar,
                            characterAvatar: characterAvatar,
                            selectMode: _selectMode,
                            selected: _selectedIds.contains(msg.id),
                            onTap: _selectMode
                                ? () => _toggleSelect(msg)
                                : null,
                            onForwardTap: () => _openForwardDetail(
                              msg,
                              userAvatar: userAvatar,
                              characterAvatar: characterAvatar,
                            ),
                            onFileTap: _selectMode ? null : _openFileMessage,
                            onLongPress: (message, bubbleKey) =>
                                _showBubbleMenu(message, bubbleKey),
                          ),
                        ],
                      );
                    },
                  ),
                );
              },
            ),
          ),
          // 多选模式：显示选择操作栏；否则显示错误条/引用条/输入框
          if (_selectMode)
            _buildSelectBar(context)
          else ...[
            // AI 请求失败错误提示条（可点击关闭）
            Consumer<ChatProvider>(
              builder: (context, chatProvider, _) {
                final error = chatProvider.lastError;
              if (error == null || error.isEmpty) {
                return const SizedBox.shrink();
              }
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                color: context.navBarColor,
                child: Row(
                  children: [
                    const Icon(
                      CupertinoIcons.exclamationmark_triangle_fill,
                      size: 15,
                      color: CupertinoColors.systemRed,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        error,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.systemRed,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: chatProvider.clearError,
                      child: Icon(
                        CupertinoIcons.xmark_circle_fill,
                        size: 16,
                        color: context.textSecondaryColor,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          // 引用条（设置了引用时显示在输入框上方）
          if (_quoteMessage != null)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              color: context.navBarColor,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: context.listBgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _quoteMessage!.isFromUser
                                ? '引用 我'
                                : '引用 $displayName',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: context.accentColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _quoteMessage!.content,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: context.textSecondaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: _clearQuote,
                      child: Icon(
                        CupertinoIcons.xmark_circle_fill,
                        size: 18,
                        color: context.textSecondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          MessageInput(
            key: _inputKey,
            onSend: _handleSend,
            onPickImage: _handlePickImage,
            onPickFile: _handlePickFile,
            onSettings: _openChatSettings,
            onExport: _exportChat,
            onImport: _importChat,
            onFeatureDetect: _runFeatureDetect,
            onRequestReply: () {
              // 对号按钮：触发角色回复。若最近发送的是图片，把该图片随回复传给模型
              final imagePath = _pendingImagePath;
              _pendingImagePath = null;
              _triggerProactiveMessages(imagePath: imagePath, replyToUser: true);
            },
            replyEnabled: replyEnabled,
            imageReady: visionReady,
          ),
          ],
        ],
      ),
    );
  }
}
