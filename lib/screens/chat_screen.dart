import 'dart:io';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/message.dart';
import '../providers/api_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/chat_settings_provider.dart';
import '../providers/character_provider.dart';
import '../services/llm_service.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/message_input.dart';
import 'chat_detail_screen.dart';
import 'chat_settings_screen.dart';

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

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<MessageInputState> _inputKey = GlobalKey<MessageInputState>();
  Message? _quoteMessage;
  OverlayEntry? _menuOverlay;
  bool _proactiveTyping = false; // 主动消息逐条渲染中的"对方正在输入"
  bool _isProactiveRunning = false; // 防止重复触发主动消息
  bool _initialScrollDone = false; // 首次进入会话是否已完成定位（避免进入时动画滑动）

  @override
  void dispose() {
    _menuOverlay?.remove();
    _scrollController.dispose();
    super.dispose();
  }

  /// 滚动到底部。[animate] 为 false 时瞬间定位（首次进入会话用，避免整屏滑动动画）。
  void _scrollToBottom({bool animate = true}) {
    if (_scrollController.hasClients) {
      if (animate) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (!_scrollController.hasClients) return;
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        });
      } else {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    }
  }

  /// 打开聊天设置（模型/上下文条数）
  void _openChatSettings() {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => const ChatSettingsScreen(),
      ),
    );
  }

  /// 导出当前聊天记录为 Markdown 文件保存到手机
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

    // 生成 Markdown 内容
    final sb = StringBuffer();
    sb.writeln('# 与 ${widget.characterName} 的聊天记录');
    sb.writeln();
    sb.writeln('> 导出时间: ${_formatDateTime(DateTime.now())}');
    sb.writeln();
    for (final message in messages) {
      final who = message.isFromUser ? '我' : widget.characterName;
      sb.writeln('## ${_formatDateTime(message.createdAt)} - $who');
      sb.writeln();
      sb.writeln(message.content);
      sb.writeln();
    }

    // 保存文件到手机下载目录
    String savePath;
    try {
      final dir = await getDownloadsDirectory();
      if (dir == null) {
        final docDir = await getApplicationDocumentsDirectory();
        savePath = '${docDir.path}/AiChat导出';
      } else {
        savePath = dir.path;
      }
    } catch (_) {
      final docDir = await getApplicationDocumentsDirectory();
      savePath = '${docDir.path}/AiChat导出';
    }

    try {
      final now = DateTime.now();
      final fileName =
          '${widget.characterName}_聊天记录_${now.month}${now.day}_${now.hour}${now.minute}${now.second}.md';
      final file = File('$savePath/$fileName');
      await file.writeAsString(sb.toString());

      if (!mounted) return;
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('导出成功'),
          content: Text(
            '已将 ${messages.length} 条聊天记录保存为 Markdown 文件：\n\n${file.path}',
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
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('导出失败'),
          content: Text('保存文件时出错：$e'),
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

  String _formatDateTime(DateTime time) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final isToday = time.year == now.year &&
        time.month == now.month &&
        time.day == now.day;
    final timeStr = '${two(time.hour)}:${two(time.minute)}';
    if (isToday) return '今天 $timeStr';
    return '${time.month}月${time.day}日 $timeStr';
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
    const double menuHeight = 64;

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

  /// 触发"角色主动发消息/回复"：组装 Prompt（携带最近对话历史）→ 调用 LLM 生成消息数组 → 顺序渲染
  ///
  /// [replyToUser] 为 true 时（输入框对号按钮触发）模型针对用户最近的消息分条回复。
  Future<void> _triggerProactiveMessages({bool replyToUser = false}) async {
    if (_isProactiveRunning) return;

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

    setState(() {
      _isProactiveRunning = true;
      _proactiveTyping = true; // 点击后立即显示"对方正在输入……"（等待 API + 逐条渲染期间）
    });
    try {
      final messages = await chatProvider.generateProactiveMessages(
        conversationId: widget.conversationId,
        model: model,
        characterName: characterName,
        characterSystemPrompt: character?.systemPrompt ?? '',
        customPersona: character?.customPersona ?? '',
        userRelationship: character?.userRelationship ?? '',
        userNickname:
            context.read<AuthProvider>().user?.nickname ?? '用户',
        replyToUser: replyToUser,
        contextCount: chatSettings.contextCount,
      );
      if (!mounted) return;
      if (messages.isEmpty) {
        // API 失败时错误条已展示；模型主动返回空数组（如时间不合理）时给出轻提示
        if (chatProvider.lastError == null) {
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
        return;
      }
      await _renderMessagesSequentially(messages);
    } finally {
      if (mounted) {
        setState(() {
          _isProactiveRunning = false;
          _proactiveTyping = false;
        });
      }
    }
  }

  /// 顺序渲染消息队列（微信拟真感）：
  /// 每条先显示"对方正在输入..."，按长度计算延迟，结束后推入气泡并触发震动。
  Future<void> _renderMessagesSequentially(List<String> messages) async {
    final random = Random();
    final chatProvider = context.read<ChatProvider>();
    for (final content in messages) {
      if (!mounted) return;
      setState(() => _proactiveTyping = true);
      _scrollToBottom();

      // 延迟 = 随机 0~1s + 消息长度 * 50ms（模拟打字耗时）
      final delay = random.nextDouble() * 1000 + content.length * 50;
      await Future.delayed(Duration(milliseconds: delay.round()));
      if (!mounted) return;

      setState(() => _proactiveTyping = false);
      chatProvider.addProactiveMessage(widget.conversationId, content);
      _scrollToBottom();
      HapticFeedback.lightImpact(); // 消息提示震动
      await Future.delayed(const Duration(milliseconds: 600)); // 消息间隔
    }
    if (mounted) setState(() => _proactiveTyping = false);
  }

  /// 选择图片后发送图片消息
  void _handlePickImage(String imagePath) {
    final chatSettings = context.read<ChatSettingsProvider>();
    context.read<ChatProvider>().sendImageMessage(
          conversationId: widget.conversationId,
          imagePath: imagePath,
          characterName: widget.characterName,
          contextCount: chatSettings.contextCount,
        );
  }

  /// 选择文件后发送文件消息
  void _handlePickFile(String filePath, String fileName) {
    context.read<ChatProvider>().sendFileMessage(
          conversationId: widget.conversationId,
          filePath: filePath,
          fileName: fileName,
        );
  }

  @override
  Widget build(BuildContext context) {
    // 实时显示名：优先使用角色资料中的备注/昵称
    final chatProvider = context.watch<ChatProvider>();
    final conversation = chatProvider.conversations
        .where((c) => c.id == widget.conversationId)
        .firstOrNull;
    final character = conversation != null
        ? context
            .watch<CharacterProvider>()
            .getCharacterById(conversation.characterId)
        : null;
    final displayName = character?.displayName ?? widget.characterName;

    // 对号按钮可用性：上一条消息是用户发送时才可点（角色还没回复）
    final lastMessage = chatProvider.getMessages(widget.conversationId).lastOrNull;
    final replyEnabled = lastMessage != null && lastMessage.isFromUser;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        // 角色回复逐条渲染中，标题变为"对方正在输入……"，结束后恢复角色备注/昵称
        middle: Text(_proactiveTyping ? '对方正在输入……' : displayName),
        trailing: CupertinoButton(
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

                // 首次进入会话：瞬间定位到底部（不带动画，避免整屏滑动）；
                // 之后的滚动交给消息渲染逻辑（动画滚动），此处不再重复触发。
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!_initialScrollDone) {
                    _initialScrollDone = true;
                    _scrollToBottom(animate: false);
                  }
                });

                return Container(
                  color: context.chatBgColor,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      return ChatBubble(
                        message: messages[index],
                        userAvatar: userAvatar,
                        characterAvatar: characterAvatar,
                        onLongPress: (message, bubbleKey) =>
                            _showBubbleMenu(message, bubbleKey),
                      );
                    },
                  ),
                );
              },
            ),
          ),
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
            onFeatureDetect: _runFeatureDetect,
            onRequestReply: () => _triggerProactiveMessages(replyToUser: true),
            replyEnabled: replyEnabled,
          ),
        ],
      ),
    );
  }
}
