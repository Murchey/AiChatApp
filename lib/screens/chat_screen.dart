import 'dart:io';
import 'dart:math';
import 'dart:ui' show ImageFilter;
import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../providers/api_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_background_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/chat_settings_provider.dart';
import '../providers/character_provider.dart';
import '../providers/group_chat_provider.dart';
import '../providers/memory_point_provider.dart';
import '../services/chat_records_service.dart';
import '../services/llm_service.dart';
import '../services/memory_pool_builder.dart';
import '../utils/file_picker_helper.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/character_avatar.dart';
import '../widgets/message_input.dart';
import 'chat_detail_screen.dart';
import 'chat_settings_screen.dart';
import 'character_detail_screen.dart';
import 'forward_detail_screen.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String characterName;
  final String characterAvatar;
  // 从搜索结果进入时定位到该消息（null 表示默认显示最新消息）
  final String? initialMessageId;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.characterName,
    this.characterAvatar = '',
    this.initialMessageId,
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
  bool _selectingMemory = false; // 多选模式用途：true=保存为记忆点，false=转发
  ChatProvider? _chatProvider; // 生命周期内复用（dispose 中仍需访问）
  int _lastRenderedCount = -1; // 已渲染消息条数（用于新消息自动滚底）
  bool _keyboardVisible = false; // 软键盘是否弹出（用于键盘弹出时保持列表滚底）
  // 发送防重复：界面卡顿导致点击无视觉反馈时，用户常会连点"发送"，
  // 同一条消息会被插入多次。以时间窗节流，窗口内重复点击直接忽略。
  static const int _sendThrottleMs = 500;
  DateTime _lastSendAt = DateTime.fromMillisecondsSinceEpoch(0);
  // 搜索结果定位：待定位的消息 id（定位完成后置 null）
  String? _pendingScrollMessageId;
  int _locateRetries = 0; // 补跳次数（步长随次数指数增大）

  /// 按消息类型/长度估算条目高度（像素），用于定位的初始跳转。
  /// 取值刻意偏小（每行字符数偏多、行高偏小），保证初始跳转不会越过
  /// 目标——目标总在"更旧"方向，后续补跳单向递增即可收敛，避免双向回溯。
  double _estimateMessageHeight(Message m) {
    const lineHeight = 20.0; // fontSize 16 行高，取偏小值
    const perLineChars = 16.0; // 气泡内宽约 240px，中文约 17px/字，偏小估算
    const fixed = 40.0; // 气泡上下 padding + 可能的时间标签，取偏小值
    switch (m.type) {
      case MessageType.image:
        return 260;
      case MessageType.file:
        return 90;
      case MessageType.system:
        return 60;
      case MessageType.text:
        final lines = (m.content.length / perLineChars).ceil();
        return fixed + lines * lineHeight;
    }
  }

  /// 搜索结果进入时的定位流程：
  /// 1) 按消息类型/长度估算 offset，一次性跳近目标（估算偏小 → 目标偏旧方向）；
  /// 2) 目标未进入构建区时，以指数步长（1/2/4/8/16 屏）向更旧方向补跳，
  ///    步长递增使长距离偏差只需几次跳转，避免逐帧小步推进的连续布局开销；
  /// 3) 补跳接近最旧端时直接跳到底——目标必在构建区内，由 itemBuilder
  ///    捕获后 ensureVisible 精确对齐；目标已不存在则自然停止，无死循环。
  void _locatePendingMessage() {
    final targetId = _pendingScrollMessageId;
    if (targetId == null || !mounted || !_scrollController.hasClients) return;
    final messages =
        _chatProvider?.getMessages(widget.conversationId) ?? const <Message>[];
    final targetIndex = messages.indexWhere((m) => m.id == targetId);
    if (targetIndex == -1) {
      _pendingScrollMessageId = null;
      return;
    }
    // reverse 列表 offset 0 = 底部（最新消息）；目标 offset = 比它更新的
    // 消息高度之和（滚动到该处时目标正好进入视口）
    var offset = 0.0;
    for (var i = messages.length - 1; i > targetIndex; i--) {
      offset += _estimateMessageHeight(messages[i]);
    }
    final max = _scrollController.position.maxScrollExtent;
    _scrollController.jumpTo(offset.clamp(0.0, max));
    _locateRetries = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) => _refineLocate());
  }

  void _refineLocate() {
    final targetId = _pendingScrollMessageId;
    if (targetId == null || !mounted || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    // 指数步长：1/2/4/8/16 屏，长距离偏差只需几次跳转
    final step = position.viewportDimension * (1 << _locateRetries.clamp(0, 4));
    final next = position.pixels + step;
    if (next >= position.maxScrollExtent) {
      // 接近最旧端：直接跳到底，目标若存在必在构建区内；不存在则
      // itemBuilder 永不捕获，不再调度，定位自然结束
      position.jumpTo(position.maxScrollExtent);
      return;
    }
    _locateRetries++;
    position.jumpTo(next);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refineLocate());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 打开会话：清除未读并记录当前会话（此后角色新消息不再计入未读）
    _chatProvider = context.read<ChatProvider>();
    _chatProvider!.markConversationActive(widget.conversationId);
    // 预加载本会话聊天背景（懒加载完成后自动重建渲染）
    context.read<ChatBackgroundProvider>().getInfo(widget.conversationId);
    // 首次打开（会话无消息）且角色配置了 Greeting 时，角色主动发送问候语
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sendGreetingIfNeeded();
    });
    // 从搜索结果进入：定位到目标消息
    if (widget.initialMessageId != null) {
      _pendingScrollMessageId = widget.initialMessageId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _locatePendingMessage();
      });
    }
  }

  /// 首次打开会话（无任何消息）且角色配置了 Greeting 时，
  /// 角色主动发送问候语，让新会话从角色的主动问候开始。
  Future<void> _sendGreetingIfNeeded() async {
    final chatProvider = context.read<ChatProvider>();
    if (chatProvider.getMessages(widget.conversationId).isNotEmpty) return;
    final conversation = chatProvider.conversations
        .where((c) => c.id == widget.conversationId)
        .firstOrNull;
    if (conversation == null) return;
    final greeting = context
            .read<CharacterProvider>()
            .getCharacterById(conversation.characterId)
            ?.greeting
            .trim() ??
        '';
    if (greeting.isEmpty) return;
    // 稍作停顿模拟角色主动"打字"，随后一次性发出问候
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    // 等待期间用户已发消息/问候已入队则不再重复发送
    if (chatProvider.getMessages(widget.conversationId).isNotEmpty) return;
    chatProvider.addProactiveMessage(widget.conversationId, greeting);
    _scrollToBottom();
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
      // 删除角色消息：移除后不再作为后续对话的上下文
      items.add(
        _menuItem(
          icon: CupertinoIcons.delete,
          label: '删除',
          onTap: () {
            _closeMenu();
            context
                .read<ChatProvider>()
                .deleteMessage(widget.conversationId, message.id);
          },
        ),
      );
    }

    items.add(
      _menuItem(
        icon: CupertinoIcons.bookmark,
        label: '保存为记忆点',
        onTap: () {
          _closeMenu();
          _enterSelectMode(message, forMemory: true);
        },
      ),
    );

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
    // 防止长会话卡顿期间用户重复点击导致同一条消息被发送多次
    final now = DateTime.now();
    if (now.difference(_lastSendAt).inMilliseconds < _sendThrottleMs) {
      debugPrint('[ChatScreen] 发送过于频繁，忽略本次点击（${_sendThrottleMs}ms 内）');
      return;
    }
    _lastSendAt = now;
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

  /// 从长按菜单进入多选模式（默认选中当前长按的消息）。
  /// [forMemory] 为 true 时是「保存为记忆点」模式，否则为转发模式。
  void _enterSelectMode(Message message, {bool forMemory = false}) {
    setState(() {
      _selectMode = true;
      _selectingMemory = forMemory;
      _selectedIds.add(message.id);
    });
  }

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selectingMemory = false;
      _selectedIds.clear();
    });
  }

  /// 保存选中的消息为角色的持久化记忆点：
  /// 仅取文本类消息，内容带发送者标识（用户/角色名），便于模型理解语境。
  /// 单次选取的多条消息合并为**一条**记忆点（一个栏目），
  /// 在管理页作为整体编辑 / 删除。
  Future<void> _saveSelectedAsMemory() async {
    final chatProvider = context.read<ChatProvider>();
    final conversation = chatProvider.conversations
        .where((c) => c.id == widget.conversationId)
        .firstOrNull;
    if (conversation == null) {
      _exitSelectMode();
      return;
    }
    final character = context
        .read<CharacterProvider>()
        .getCharacterById(conversation.characterId);
    final characterName = character?.displayName ?? widget.characterName;
    final userName =
        context.read<AuthProvider>().user?.nickname ?? '用户';

    final messages = chatProvider
        .getMessages(widget.conversationId)
        .where((m) => _selectedIds.contains(m.id))
        .toList();
    // 仅文本消息可作记忆点（图片/文件内容是路径，无语义）
    final texts = messages
        .where((m) => m.type == MessageType.text && m.content.trim().isNotEmpty)
        .map((m) =>
            '${m.isFromUser ? userName : characterName}说："${m.content.trim()}"')
        .toList();
    if (texts.isEmpty) {
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('提示'),
          content: const Text('选中的消息中不包含可保存的文字内容'),
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
    // 多条消息合并为一条记忆点（换行分隔），作为整体存储
    final mergedContent = texts.join('\n');

    final memoryProvider = context.read<MemoryPointProvider>();
    // 弹窗确认要保存的内容
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('保存为记忆点'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '将以下 ${texts.length} 条消息保存为「$characterName」的一条记忆点：',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final t in texts)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(t,
                              style: const TextStyle(fontSize: 13)),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    await memoryProvider.addPoints(conversation.characterId, [mergedContent]);
    if (!mounted) return;
    _exitSelectMode();
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('已保存'),
        content: Text(
          '已将 ${texts.length} 条消息合并为一条记忆点保存，后续对话中「$characterName」会自动记住这些内容。可在聊天详情「提示词设置 → 记忆点管理」中查看或修改。',
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

  /// 多选模式底部操作栏：取消 + 已选数量 + 转发/存储记忆点操作
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
            if (_selectingMemory)
              CupertinoButton(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                onPressed: count > 0 ? _saveSelectedAsMemory : null,
                child: Text(
                  '存储记忆点',
                  style: TextStyle(
                    fontSize: 15,
                    color: count > 0
                        ? context.accentColor
                        : context.textSecondaryColor,
                  ),
                ),
              )
            else ...[
              CupertinoButton(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                onPressed:
                    count > 0 ? () => _forwardMessages(merge: false) : null,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                onPressed:
                    count > 0 ? () => _forwardMessages(merge: true) : null,
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

  /// 点击角色头像：进入对方的空间页（资料 + 朋友圈）
  void _openCharacterSpace() {
    final conversation = context
        .read<ChatProvider>()
        .conversations
        .where((c) => c.id == widget.conversationId)
        .firstOrNull;
    if (conversation == null) return;
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => CharacterDetailScreen(
          characterId: conversation.characterId,
        ),
      ),
    );
  }

  /// 点击"我"的头像：进入自己的空间页（资料 + 朋友圈）
  void _openSelfSpace() {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => const CharacterDetailScreen(
          characterId: CharacterProvider.selfCharacterId,
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
      _showNoModelDialog('进行功能检测');
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

  /// 未选择模型时的引导弹窗：告知「聊天设置」在输入框左下角的加号面板里，
  /// 并提供【去设置】按钮直达聊天设置页。
  void _showNoModelDialog(String action) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('未选择模型'),
        content: Text('无法$action。请点击输入框左下角的「+」按钮打开「聊天设置」，选择模型后再试。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              Navigator.pop(ctx);
              _openChatSettings();
            },
            child: const Text('去设置'),
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
      _showNoModelDialog('进行角色回复');
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

    // 用户持久化记忆点：拼入系统提示词，让角色在本次回复中记住这些长期信息
    final memoryPoints = conversation != null
        ? context
            .read<MemoryPointProvider>()
            .pointsFor(conversation.characterId)
            .map((p) => p.content)
            .toList()
        : const <String>[];

    // 角色记忆池：聚合朋友圈 / 近期群聊 / 资料卡等场景外记忆，拼入系统提示词，
    // 让角色在私聊中保持跨场景的记忆连贯。私聊历史已作为对话上下文传入，
    // 因此 includePrivateHistory 传 false，避免重复拼接
    final memoryPool = character != null
        ? MemoryPoolBuilder.build(
            character: character,
            chatProvider: chatProvider,
            groupChatProvider: context.read<GroupChatProvider>(),
            chatSettings: chatSettings,
            user: context.read<AuthProvider>().user,
            includePrivateHistory: false,
          )
        : '';

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
      activeStart: character?.activeStart ?? '',
      activeEnd: character?.activeEnd ?? '',
      memoryPoints: memoryPoints,
      extraSystemContext: memoryPool,
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
    // 实时显示名：优先使用角色资料中的备注/昵称。
    // 注意：ChatProvider 在 AI 逐条回复时会多次 notify，若顶层 watch 它，
    // 每次回复都会重建整个聊天页（导航栏+列表+输入框），是滚动/回复卡顿的主因。
    // 这里只做一次性 read；列表/输入框/标题分别用 Consumer/Selector 局部重建。
    final chatProvider = context.read<ChatProvider>();
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

    // 对号按钮可用性（上一条消息是用户发送时才可点）与最新消息：
    // 在下方输入框的 Consumer 内计算，随 ChatProvider 局部刷新

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        // 多选模式显示标题；否则角色回复生成/渲染期间标题变为"对方正在输入……"
        // 多选模式显示标题；否则角色回复生成/渲染期间标题变为"对方正在输入……"。
        // 用 Selector 只订阅本会话的回复状态，ChatProvider 其他变化不重建标题
        middle: _selectMode
            ? Text(_selectingMemory ? '选择记忆点' : '选择消息')
            : Selector<ChatProvider, bool>(
                selector: (_, p) => p.isReplying(widget.conversationId),
                builder: (context, replying, _) => Text(
                  replying ? '对方正在输入……' : displayName,
                ),
              ),
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
      child: Consumer<ChatBackgroundProvider>(
        builder: (context, bgProvider, _) {
          final bgInfo = bgProvider.getInfoSync(widget.conversationId);
          // 是否渲染背景图：有图且文件存在时，消息列表用半透明遮罩保护文字可读性
          final hasBg = bgInfo != null && bgInfo.hasImage && bgInfo.fileExists;
          return Stack(
            children: [
              // 背景层（已持久化图片 + 高斯模糊）。
              // RepaintBoundary：滚动消息列表时复用已光栅化结果，避免每帧重跑高斯模糊
              if (hasBg)
                RepaintBoundary(
                  child: Builder(
                    builder: (ctx) {
                      final bgSize = MediaQuery.of(ctx).size;
                      final blur = bgInfo.blur > 0 ? bgInfo.blur : 0.1;
                      // 按屏幕物理像素限制解码尺寸：模糊背景无需全分辨率，显著降低
                      // 大图解码内存与每帧模糊计算量
                      final decodeWidth =
                          (bgSize.width * MediaQuery.devicePixelRatioOf(ctx))
                              .ceil();
                      return ImageFiltered(
                        imageFilter:
                            ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                        child: Image.file(
                          File(bgInfo.imagePath),
                          fit: BoxFit.cover,
                          width: bgSize.width,
                          height: bgSize.height,
                          cacheWidth: decodeWidth,
                          cacheHeight: decodeWidth,
                        ),
                      );
                    },
                  ),
                ),
              // 消息内容层
              Column(
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
                    color: hasBg
                        ? context.chatBgColor.withValues(alpha: 0.86)
                        : context.chatBgColor,
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
                  color: hasBg
                      ? context.chatBgColor.withValues(alpha: 0.86)
                      : context.chatBgColor,
                  child: ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    // 增大构建缓存区：搜索结果定位时，目标消息更容易被构建到
                    // 从而通过 ensureVisible 精确对齐（见 _locatePendingMessage）
                    scrollCacheExtent: const ScrollCacheExtent.pixels(600),
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
                      // 搜索结果定位：目标消息被构建到后精确滚动对齐（只需一次）
                      final pendingId = _pendingScrollMessageId;
                      if (pendingId != null && msg.id == pendingId) {
                        _pendingScrollMessageId = null;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          Scrollable.ensureVisible(
                            context,
                            alignment: 0.35,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        });
                      }
                      // RepaintBoundary：气泡独立绘制层，列表滚动/重建时
                      // 只有变化的条目重绘，其余复用已光栅化内容
                      return RepaintBoundary(
                        key: ValueKey(msg.id),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (showTime) _buildTimeLabel(msg.createdAt),
                            ChatBubble(
                            message: msg,
                            userAvatar: userAvatar,
                            characterAvatar: characterAvatar,
                            selectMode: _selectMode,
                            selected: _selectedIds.contains(msg.id),
                            // 点击头像进入对应空间页（多选模式下禁用，避免误触）
                            onUserAvatarTap: _selectMode
                                ? null
                                : _openSelfSpace,
                            onCharacterAvatarTap: _selectMode
                                ? null
                                : _openCharacterSpace,
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
                      ),
                    );
                    },
                  ),
                );
              },
            ),
          ),
          // 多选模式：显示选择操作栏；否则显示错误条/引用条/输入框。
          // 输入区用单个 Consumer 订阅 ChatProvider：AI 逐条回复时，
          // 只有这里与消息列表局部重建，导航栏/页面骨架不再全量重建
          if (_selectMode)
            _buildSelectBar(context)
          else
            Consumer<ChatProvider>(
              builder: (context, chatProvider, _) {
                // 当前模型是否已检测为视觉模型（检测过一次即记住）。
                // 模型/设置变更极低频，只在此局部订阅，不重建页面骨架
                final visionReady = context
                        .watch<ApiProvider>()
                        .isVisionSupported(context
                            .watch<ChatSettingsProvider>()
                            .selectedModelId) ==
                    true;
                // 对号按钮可用性：上一条消息是用户发送时才可点（角色还没回复）
                final lastMessage =
                    chatProvider.getMessages(widget.conversationId).lastOrNull;
                final replyEnabled =
                    lastMessage != null && lastMessage.isFromUser;
                final error = chatProvider.lastError;
                return Column(
                  children: [
                    // AI 请求失败错误提示条（可点击关闭）
                    if (error != null && error.isNotEmpty)
                      Container(
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
                      ),
                    // 引用条（设置了引用时显示在输入框上方）
                    if (_quoteMessage != null)
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        color: context.navBarColor,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
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
                        _triggerProactiveMessages(
                            imagePath: imagePath, replyToUser: true);
                      },
                      replyEnabled: replyEnabled,
                      imageReady: visionReady,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
            ],
          );
        },
      ),
    );
  }
}
