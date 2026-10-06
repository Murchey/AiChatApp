import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/motion.dart';
import '../config/theme.dart';
import '../models/message.dart';
import '../providers/api_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_background_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/chat_settings_provider.dart';
import '../providers/character_provider.dart';
import '../providers/settings_provider.dart';
import 'sticker_picker_screen.dart';
import '../services/llm_service.dart';
import '../services/tts_playback_controller.dart';
import '../utils/file_picker_helper.dart';
import '../utils/app_toast.dart';
import '../widgets/chat/chat_background_layer.dart';
import '../widgets/chat/chat_bubble_menu.dart';
import '../widgets/chat/chat_select_bar.dart';
import '../widgets/chat/chat_message_chrome.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chat_title_bar.dart';
import '../widgets/message_input.dart';
import 'chat/chat_import_export.dart';
import 'chat/chat_message_actions.dart';
import 'chat/chat_plot_suggestion.dart';
import 'chat/chat_proactive_reply.dart';
import 'chat/chat_select_forward.dart';
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

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<MessageInputState> _inputKey = GlobalKey<MessageInputState>();
  // 时间标签用的 DateFormat 只创建一次（DateFormat 构造开销较大，长会话频繁重建时明显）
  Message? _quoteMessage;
  OverlayEntry? _menuOverlay;
  String? _pendingImagePath; // 最近发送的图片：对号按钮按下时随回复传给模型
  String? _pendingStickerPath;
  String? _pendingStickerLabel;
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
      case MessageType.sticker:
        return 260;
      case MessageType.file:
        return 90;
      case MessageType.system:
      case MessageType.narration:
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
            duration: AppMotion.base,
            curve: AppMotion.out,
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

  /// 导出当前聊天记录为 zip 包
  Future<void> _exportChat() => ChatImportExport.exportChat(
        context,
        conversationId: widget.conversationId,
        characterName: widget.characterName,
      );

  /// 导入聊天记录 zip 到当前会话
  Future<void> _importChat() => ChatImportExport.importChat(
        context,
        conversationId: widget.conversationId,
        onImported: () {
          if (mounted) _scrollToBottom();
        },
      );

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

    // 菜单尺寸：按等宽等高按钮网格推算（见 _menuPanelWidth / _menuPanelHeight）
    final double menuWidth = ChatBubbleMenuPanel.panelWidth(items.length);
    final double menuHeight = ChatBubbleMenuPanel.panelHeight(items.length);

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
            child: ChatBubbleMenuPanel(items: items),
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

  /// 查看 AI 思考过程
  void _showReasoningContent(Message message) =>
      ChatMessageActions.showReasoning(context, message);

  /// 角色气泡下方的思考时长标签
  List<Widget> _buildMenuItems(Message message) {
    return ChatBubbleMenuItems(
      message: message,
      onClose: _closeMenu,
      onCopy: () => Clipboard.setData(ClipboardData(text: message.content)),
      onSelectText: () => _showTextSelection(message),
      onQuote: () => setState(() => _quoteMessage = message),
      onWithdraw: message.isFromUser ? () => _withdrawMessage(message) : null,
      onEdit: (message.isFromUser && message.type != MessageType.narration)
          ? null
          : () => _editMessage(message),
      onShowReasoning:
          message.hasReasoning ? () => _showReasoningContent(message) : null,
      onReroll: () => _rerollReply(message),
      onDelete: message.isFromUser
          ? null
          : () => context
              .read<ChatProvider>()
              .deleteMessage(widget.conversationId, message.id),
      onSaveMemory: () => _enterSelectMode(message, forMemory: true),
      onMultiSelect: () => _enterSelectMode(message),
      onBranch: () => _branchConversation(message),
    ).build();
  }

  /// 分支对话
  Future<void> _branchConversation(Message message) =>
      ChatMessageActions.branchConversation(
        context,
        conversationId: widget.conversationId,
        message: message,
      );

  /// 选择文本
  void _showTextSelection(Message message) =>
      ChatMessageActions.showTextSelection(context, message);

  /// 编辑消息
  Future<void> _editMessage(Message message) => ChatMessageActions.editMessage(
        context,
        conversationId: widget.conversationId,
        message: message,
      );

  /// 添加剧情行动
  Future<void> _addRoleplayNarration() async {
    final controller = TextEditingController();
    final content = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('添加剧情行动'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            autofocus: true,
            maxLines: 8,
            minLines: 3,
            placeholder: '描述你的行动或故事发展，例如：\n（我推开门，走进客栈）',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || content == null || content.trim().isEmpty) return;
    await context.read<ChatProvider>().addRoleplayNarration(
          conversationId: widget.conversationId,
          content: content,
        );
    if (mounted) _scrollToBottom();
  }

  /// 剧情建议
  Future<void> _plotSuggestion() => ChatPlotSuggestion.run(
        context,
        conversationId: widget.conversationId,
        fallbackName: widget.characterName,
        fillInput: (t) => _inputKey.currentState?.setText(t),
        onNeedModel: () => _showNoModelDialog('生成剧情建议'),
      );

  /// 撤回消息
  void _withdrawMessage(Message message) {
    ChatMessageActions.withdraw(
      context,
      conversationId: widget.conversationId,
      message: message,
      setTextInput: (t) => _inputKey.currentState?.setText(t),
      focusInput: () => _inputKey.currentState?.focus(),
      currentQuote: () => _quoteMessage,
      clearQuote: () {
        if (mounted) setState(() => _quoteMessage = null);
      },
    );
  }

  /// 重新回复
  void _rerollReply(Message aiMessage) {
    ChatMessageActions.reroll(
      context: context,
      conversationId: widget.conversationId,
      aiMessage: aiMessage,
      resend: _handleSend,
    );
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

  /// 保存选中的消息为角色记忆点
  Future<void> _saveSelectedAsMemory() =>
      ChatSelectForward.saveSelectedAsMemory(
        context,
        conversationId: widget.conversationId,
        fallbackCharacterName: widget.characterName,
        selectedIds: _selectedIds,
        onSaved: () {
          if (mounted) _exitSelectMode();
        },
      );

  /// 多选模式下点击气泡切换选中状态
  void _toggleSelect(Message message) {
    setState(() {
      if (!_selectedIds.remove(message.id)) {
        _selectedIds.add(message.id);
      }
    });
  }

  /// 转发选中的消息到其他会话
  Future<void> _forwardMessages({required bool merge}) =>
      ChatSelectForward.forwardMessages(
        context,
        conversationId: widget.conversationId,
        fallbackCharacterName: widget.characterName,
        selectedIds: _selectedIds,
        merge: merge,
        onDone: () {
          if (mounted) _exitSelectMode();
        },
      );

  Widget _buildTimeLabel(DateTime time) => ChatTimeLabel(time: time);

  Widget _buildSelectBar(BuildContext context) {
    return ChatSelectBar(
      count: _selectedIds.length,
      selectingMemory: _selectingMemory,
      onCancel: _exitSelectMode,
      onSaveMemory: _saveSelectedAsMemory,
      onForwardSingle: () => _forwardMessages(merge: false),
      onForwardMerge: () => _forwardMessages(merge: true),
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
  /// 检测结果用于提示（相册/拍照始终可用，不因检测结果禁用）。
  Future<bool> _runFeatureDetect() async {
    final chatSettings = context.read<ChatSettingsProvider>();
    final model =
        context.read<ApiProvider>().getModelById(chatSettings.selectedModelId);
    if (model == null) {
      _showNoModelDialog('进行功能检测');
      return false;
    }
    try {
      final supported = await LLMService.testImageSupport(model);
      if (!mounted) return supported;
      // 记住检测结果：供朋友圈图文提示等场景参考
      await context.read<ApiProvider>().setVisionSupported(model.id, supported);
      _showFeatureResult(
        supported
            ? '「${model.displayName}」支持图片发送，发送的图片会被模型识别。'
            : '「${model.displayName}」未识别为支持图片的模型，发送图片可能无法被识别。',
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

  Future<void> _speakMessage(Message message) async {
    if (message.isFromUser || message.content.trim().isEmpty) return;
    final api = context.read<ApiProvider>();
    final model = api.getModelById(api.ttsModelId);
    if (model == null) {
      if (mounted) showAppToast('请先在「API 设置」中选择语音模型');
      return;
    }
    final conversation = context
        .read<ChatProvider>()
        .conversations
        .where((c) => c.id == widget.conversationId)
        .firstOrNull;
    final character = conversation == null
        ? null
        : context
            .read<CharacterProvider>()
            .getCharacterById(conversation.characterId);

    // 连续播放：从点击的消息开始，只播本轮（到下一条用户消息为止）的 AI 回复。
    if (conversation?.continuousRead == true) {
      final all = context
          .read<ChatProvider>()
          .getMessages(widget.conversationId)
          .toList();
      final startIndex = all.indexWhere((m) => m.id == message.id);
      if (startIndex < 0) {
        TtsPlaybackController.instance.enqueue(TtsPlaybackEntry(
          messageId: message.id,
          model: model,
          text: message.content,
          voice: character?.voiceId ?? '',
          instructions: character?.voiceInstructions ?? '',
        ));
        return;
      }
      // 找到本轮边界：startIndex 之后第一条用户消息之前
      var endIndex = all.length;
      for (var i = startIndex + 1; i < all.length; i++) {
        if (all[i].isFromUser) {
          endIndex = i;
          break;
        }
      }
      final entries = all
          .sublist(startIndex, endIndex)
          .where((m) => !m.isFromUser && m.content.trim().isNotEmpty)
          .map((m) => TtsPlaybackEntry(
                messageId: m.id,
                model: model,
                text: m.content,
                voice: character?.voiceId ?? '',
                instructions: character?.voiceInstructions ?? '',
              ))
          .toList();
      if (entries.isNotEmpty) {
        TtsPlaybackController.instance.playSequence(entries);
      }
      return;
    }

    TtsPlaybackController.instance.enqueue(TtsPlaybackEntry(
      messageId: message.id,
      model: model,
      text: message.content,
      voice: character?.voiceId ?? '',
      instructions: character?.voiceInstructions ?? '',
    ));
  }

  /// 触发角色回复：委托 ChatProactiveReply。
  Future<void> _triggerProactiveMessages({
    bool replyToUser = false,
    String? imagePath,
    String? stickerLabel,
  }) async {
    final messages = await ChatProactiveReply.trigger(
      context: context,
      conversationId: widget.conversationId,
      fallbackName: widget.characterName,
      replyToUser: replyToUser,
      imagePath: imagePath,
      stickerLabel: stickerLabel,
      onNeedModel: () => _showNoModelDialog('进行角色回复'),
    );
    if (!mounted) return;
    if (messages.isEmpty && context.read<ChatProvider>().lastError == null) {
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

  Future<void> _handleStickerSelection(StickerSelection selection) async {
    if (!mounted) return;
    final chatSettings = context.read<ChatSettingsProvider>();
    final model =
        context.read<ApiProvider>().getModelById(chatSettings.selectedModelId);
    final label = selection.label?.trim() ?? '';
    if (model != null &&
        context.read<ApiProvider>().isVisionSupported(model.id) == false &&
        label.isEmpty) {
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('需要填写备注'),
          content: const Text('当前模型不支持图片识别，请填写表情包备注后再发送。'),
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
    await context.read<ChatProvider>().sendStickerMessage(
          conversationId: widget.conversationId,
          stickerPath: selection.imagePath,
          label: label,
        );
    if (!mounted) return;
    _pendingStickerPath = selection.imagePath;
    _pendingStickerLabel = label;
    _scrollToBottom();
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
        backgroundColor: context.navBarColor.withValues(alpha: 0.78),
        border: Border(
          bottom: BorderSide(
            color: context.separatorColor.withValues(alpha: 0.62),
            width: 0.5,
          ),
        ),
        // 多选模式显示标题；否则角色回复生成/渲染期间标题变为"对方正在输入……"
        // 多选模式显示标题；否则角色回复生成/渲染期间标题变为"对方正在输入……"。
        // 用 Selector 只订阅本会话的回复状态，ChatProvider 其他变化不重建标题
        middle: _selectMode
            ? Text(_selectingMemory ? '选择记忆点' : '选择消息')
            : Selector<ChatProvider, bool>(
                selector: (_, p) => p.isReplying(widget.conversationId),
                builder: (context, replying, _) {
                  // 终末地样式保持修改前的左对齐标题、个性签名和在线状态。
                  if (context.uiStyle == UiStyle.zmd) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: ChatTitleBar(
                        name: displayName,
                        signature: character?.signature ?? '',
                        activeStart: character?.activeStart ?? '',
                        activeEnd: character?.activeEnd ?? '',
                        inputStatus: replying ? '输入中' : null,
                      ),
                    );
                  }
                  return Text(
                    replying ? '对方正在输入……' : displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  );
                },
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
                ChatBackgroundLayer(
                  imagePath: bgInfo.imagePath,
                  blur: bgInfo.blur,
                ),
              // 消息内容层
              Column(
                children: [
                  Expanded(
                    child: Selector<ChatProvider, int>(
                      // The list structure only changes when a message is
                      // inserted or removed. Content replacements during an
                      // SSE stream are handled by the keyed row below.
                      selector: (_, provider) =>
                          provider.getMessages(widget.conversationId).length,
                      builder: (context, _, __) {
                        final chatProvider = context.read<ChatProvider>();
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
                        final showSpeakerIcon =
                            conversation?.showSpeakerIcon ?? false;
                        if (conversation != null) {
                          final character = context
                              .read<CharacterProvider>()
                              .getCharacterById(conversation.characterId);
                          if (character != null &&
                              character.avatar.isNotEmpty) {
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
                            scrollCacheExtent:
                                const ScrollCacheExtent.pixels(600),
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
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
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
                                    if (showTime)
                                      _buildTimeLabel(msg.createdAt),
                                    _ChatMessageTile(
                                      conversationId: widget.conversationId,
                                      message: msg,
                                      userAvatar: userAvatar,
                                      characterAvatar: characterAvatar,
                                      selectMode: _selectMode,
                                      selected: _selectedIds.contains(msg.id),
                                      showSpeakerIcon: showSpeakerIcon,
                                      onCancelPlayback: (messageId) =>
                                          TtsPlaybackController.instance
                                              .cancelMessage(messageId),
                                      onUserAvatarTap:
                                          _selectMode ? null : _openSelfSpace,
                                      onCharacterAvatarTap: _selectMode
                                          ? null
                                          : _openCharacterSpace,
                                      onTap: _selectMode ? _toggleSelect : null,
                                      onForwardTap: (message) =>
                                          _openForwardDetail(
                                        message,
                                        userAvatar: userAvatar,
                                        characterAvatar: characterAvatar,
                                      ),
                                      onFileTap:
                                          _selectMode ? null : _openFileMessage,
                                      onSpeak: (_selectMode || !showSpeakerIcon)
                                          ? null
                                          : _speakMessage,
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
                        // 对号按钮可用性：上一条消息是用户发送时才可点（角色还没回复）
                        final lastMessage = chatProvider
                            .getMessages(widget.conversationId)
                            .lastOrNull;
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
                                      CupertinoIcons
                                          .exclamationmark_triangle_fill,
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
                                padding:
                                    const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
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
                                                color:
                                                    context.textSecondaryColor,
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
                              onStickerSelected: _handleStickerSelection,
                              onRoleplayNarration: context
                                      .read<ChatSettingsProvider>()
                                      .isRoleplayMode
                                  ? _addRoleplayNarration
                                  : null,
                              isRoleplayMode: context
                                  .watch<ChatSettingsProvider>()
                                  .isRoleplayMode,
                              roleplayChoices: context
                                      .watch<ChatSettingsProvider>()
                                      .enableRoleplayChoices
                                  ? chatProvider.roleplayChoicesFor(
                                      widget.conversationId,
                                    )
                                  : const [],
                              onRoleplayChoice: (text) =>
                                  _inputKey.currentState?.setText(text),
                              onPickFile: _handlePickFile,
                              onSettings: _openChatSettings,
                              onExport: _exportChat,
                              onImport: _importChat,
                              onFeatureDetect: _runFeatureDetect,
                              onPlotSuggestion: _plotSuggestion,
                              showStickerButton: context
                                  .watch<ChatSettingsProvider>()
                                  .showStickerButton,
                              onRequestReply: () {
                                // 对号按钮：触发角色回复。若最近发送的是图片，把该图片随回复传给模型
                                final imagePath =
                                    _pendingImagePath ?? _pendingStickerPath;
                                final stickerLabel = _pendingStickerPath == null
                                    ? null
                                    : _pendingStickerLabel;
                                _pendingImagePath = null;
                                _pendingStickerPath = null;
                                _pendingStickerLabel = null;
                                _triggerProactiveMessages(
                                    imagePath: imagePath,
                                    stickerLabel: stickerLabel,
                                    replyToUser: true);
                              },
                              replyEnabled: replyEnabled,
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

/// A row-level subscription for chat messages. Provider notifications are
/// frequent while an SSE reply is streaming, so the row checks its own
/// revision before rebuilding the protected bubble subtree.
class _ChatMessageTile extends StatefulWidget {
  final String conversationId;
  final Message message;
  final String userAvatar;
  final String characterAvatar;
  final bool selectMode;
  final bool selected;
  final bool showSpeakerIcon;
  final void Function(String messageId) onCancelPlayback;
  final VoidCallback? onUserAvatarTap;
  final VoidCallback? onCharacterAvatarTap;
  final ValueChanged<Message>? onTap;
  final ValueChanged<Message>? onForwardTap;
  final Future<void> Function(String filePath)? onFileTap;
  final ValueChanged<Message>? onSpeak;
  final void Function(Message message, GlobalKey bubbleKey)? onLongPress;

  const _ChatMessageTile({
    required this.conversationId,
    required this.message,
    required this.userAvatar,
    required this.characterAvatar,
    required this.selectMode,
    required this.selected,
    required this.showSpeakerIcon,
    required this.onCancelPlayback,
    this.onUserAvatarTap,
    this.onCharacterAvatarTap,
    this.onTap,
    this.onForwardTap,
    this.onFileTap,
    this.onSpeak,
    this.onLongPress,
  });

  @override
  State<_ChatMessageTile> createState() => _ChatMessageTileState();
}

class _ChatMessageTileState extends State<_ChatMessageTile> {
  late final ChatProvider _chatProvider;
  final TtsPlaybackController _playback = TtsPlaybackController.instance;
  late int _messageRevision;
  late (TtsPlaybackPhase, int) _playbackState;

  @override
  void initState() {
    super.initState();
    _chatProvider = context.read<ChatProvider>();
    _messageRevision = _chatProvider.messageRevisionFor(
      widget.conversationId,
      widget.message.id,
    );
    _playbackState = _readPlaybackState();
    _chatProvider.addListener(_handleChatProviderChanged);
    _playback.addListener(_handlePlaybackChanged);
  }

  @override
  void didUpdateWidget(covariant _ChatMessageTile oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  (TtsPlaybackPhase, int) _readPlaybackState() => (
        _playback.phaseFor(widget.message.id),
        _playback.queuedCountFor(widget.message.id),
      );

  void _handleChatProviderChanged() {
    if (!mounted) return;
    final next = _chatProvider.messageRevisionFor(
      widget.conversationId,
      widget.message.id,
    );
    if (next == _messageRevision) return;
    _messageRevision = next;
    setState(() {});
  }

  void _handlePlaybackChanged() {
    if (!mounted) return;
    final next = _readPlaybackState();
    if (next == _playbackState) return;
    _playbackState = next;
    setState(() {});
  }

  @override
  void dispose() {
    _chatProvider.removeListener(_handleChatProviderChanged);
    _playback.removeListener(_handlePlaybackChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = _chatProvider.messageFor(
          widget.conversationId,
          widget.message.id,
        ) ??
        widget.message;
    final (phase, queuedCount) = _playbackState;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ChatBubble(
          message: message,
          userAvatar: widget.userAvatar,
          characterAvatar: widget.characterAvatar,
          selectMode: widget.selectMode,
          selected: widget.selected,
          playbackPhase: phase,
          playbackQueuedCount: queuedCount,
          onCancelPlayback: () => widget.onCancelPlayback(message.id),
          onUserAvatarTap: widget.onUserAvatarTap,
          onCharacterAvatarTap: widget.onCharacterAvatarTap,
          onTap: widget.selectMode ? () => widget.onTap?.call(message) : null,
          onForwardTap: widget.selectMode
              ? null
              : () => widget.onForwardTap?.call(message),
          onFileTap: widget.selectMode ? null : widget.onFileTap,
          onSpeak: widget.selectMode || !widget.showSpeakerIcon
              ? null
              : () => widget.onSpeak?.call(message),
          onLongPress: widget.onLongPress,
        ),
        if (!message.isFromUser) ThinkingDurationLabel(message: message),
      ],
    );
  }
}
