import 'dart:io';
import 'dart:ui' show ImageFilter;
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/routes.dart';
import '../config/theme.dart';
import '../widgets/chat/group_message_input.dart';
import '../models/character.dart';
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
import '../providers/settings_provider.dart';
import '../providers/sticker_provider.dart';
import '../providers/token_usage_provider.dart';
import '../services/chat_records_service.dart';
import '../services/llm_service.dart';
import '../services/memory_pool_builder.dart';
import '../utils/file_picker_helper.dart';
import '../widgets/chat/chat_bubble_menu.dart';
import '../widgets/chat/chat_message_chrome.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chat_title_bar.dart';
import '../widgets/character_avatar.dart';
import 'group_chat_detail_screen.dart';
import 'group_chat_settings_screen.dart';

/// 群聊会话页：用户发送消息（第一阶段）后，点击对号触发群内角色
/// 随机顺序、逐成员 LLM 判定是否插话、各自模型回复（第二阶段）。
///
/// 用户再次提交新消息会自增 Provider 内的回复轮次序号，立即打断旧轮。
class GroupChatScreen extends StatefulWidget {
  final String groupId;

  /// 桌面壳嵌入模式：复用完整群聊业务与消息输入，仅隐藏手机导航栏，
  /// 由桌面侧提供自己的标题栏和详情入口。
  final bool embedded;

  const GroupChatScreen({
    super.key,
    required this.groupId,
    this.embedded = false,
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();

  GroupChatProvider? _groupProvider;

  int _lastRenderedCount = -1;
  static const int _sendThrottleMs = 500;
  DateTime _lastSendAt = DateTime.fromMillisecondsSinceEpoch(0);
  // 输入框 key：撤回消息时把内容回填到输入框
  final GlobalKey<GroupMessageInputState> _inputKey =
      GlobalKey<GroupMessageInputState>();
  // 长按气泡引用的消息（非空时输入框上方显示引用条）
  Message? _quoteMessage;
  // 长按气泡悬浮菜单（Overlay）
  OverlayEntry? _menuOverlay;
  // @ 提及：名字 -> 角色 id（输入 @ 选择后记录；发送时按文本过滤出仍存在的提及）
  final Map<String, String> _mentionMap = {};
  // 最近一次发送消息中的 @ 提及 id，对号触发回复时传给 Provider 优先且必定回复
  List<String> _pendingMentions = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 打开群聊：记录当前群并清除其未读（此后该群新增角色消息不再计入未读）
    _groupProvider = context.read<GroupChatProvider>();
    _groupProvider!.markGroupActive(widget.groupId);
    // 预加载本群聊背景（懒加载完成后自动重建渲染）
    context.read<ChatBackgroundProvider>().getInfo(widget.groupId);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 退到后台/切到其他应用（未 pop 路由、dispose 不会触发）：
    // 视为"离开群聊页面"，此后角色新消息计入未读并弹系统通知；
    // 回到前台重新进入群聊时清除未读
    if (_groupProvider == null) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _groupProvider!.markGroupActive(widget.groupId);
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _groupProvider!.markGroupInactive(widget.groupId);
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break; // 短暂遮挡（来电/系统弹层等）不改变未读状态
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 退出群聊：恢复未读计数（若回复轮仍在后台跑，新消息将记未读并点亮主页角标）
    _groupProvider?.markGroupInactive(widget.groupId);
    _menuOverlay?.remove();
    _scrollController.dispose();
    super.dispose();
  }

  /// 跳转到角色的私聊会话
  void _navigateToCharacterChat(String characterId) {
    final chatProvider = context.read<ChatProvider>();
    final characterProvider = context.read<CharacterProvider>();

    // 根据 characterId 找到对应的 conversation
    final conversation = chatProvider.conversations.firstWhere(
      (c) => c.characterId == characterId,
      orElse: () => Conversation(
        id: characterId,
        characterId: characterId,
        characterName:
            characterProvider.getCharacterById(characterId)?.displayName ?? '',
        characterAvatar:
            characterProvider.getCharacterById(characterId)?.avatar ?? '',
      ),
    );

    Navigator.pushNamed(
      context,
      AppRoutes.chat,
      arguments: {
        'conversationId': conversation.id,
        'characterName': conversation.characterName,
        'characterAvatar': conversation.characterAvatar,
      },
    );
  }

  bool _isAtBottom() {
    if (!_scrollController.hasClients) return true;
    return _scrollController.position.pixels <= 1;
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!_scrollController.hasClients) return;
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  /// 发送用户消息（第一阶段：仅入库，不触发回复），携带引用信息。
  /// 从文本中提取仍存在的 @ 提及，对号触发回复时让被 @ 的角色优先且必定回复。
  void _handleSend(String content) {
    final now = DateTime.now();
    if (now.difference(_lastSendAt).inMilliseconds < _sendThrottleMs) return;
    _lastSendAt = now;
    final quote = _quoteMessage;
    _pendingMentions = [
      for (final e in _mentionMap.entries)
        if (content.contains('@${e.key}')) e.value,
    ];
    context.read<GroupChatProvider>().sendMessage(
          groupId: widget.groupId,
          content: content,
          quoteContent: quote?.content ?? '',
          quoteSender:
              quote == null ? '' : (quote.isFromUser ? '我' : quote.senderName),
        );
    // 发送后清空引用
    if (_quoteMessage != null) {
      setState(() => _quoteMessage = null);
    }
  }

  /// 输入 @ 时弹出成员选择：选择后插入「@名字 」并记录提及。
  void _onMentionRequest() {
    final group =
        context.read<GroupChatProvider>().getGroupById(widget.groupId);
    if (group == null) return;
    final charProvider = context.read<CharacterProvider>();
    final candidates = <Character>[
      for (final id in group.memberCharacterIds)
        if (charProvider.getCharacterById(id) != null)
          charProvider.getCharacterById(id)!,
    ];
    if (candidates.isEmpty) return;

    // 保留软键盘：面板通过底部 SafeArea 定位在键盘上方弹出，不影响继续输入
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.5,
        ),
        decoration: BoxDecoration(
          color: context.listBgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '选择要 @ 的成员',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in candidates)
                      CupertinoListTile(
                        leading: CharacterAvatar(
                          base64: c.avatar,
                          size: 36,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        title: Text(
                          c.displayName,
                          style: TextStyle(
                            fontSize: 16,
                            color: context.textPrimaryColor,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          _inputKey.currentState?.appendMention(c.displayName);
                          setState(() => _mentionMap[c.displayName] = c.id);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 导出群聊聊天记录 zip（含各角色发送者信息与图片/文件）。
  Future<void> _exportGroupChat() async {
    final groupProvider = context.read<GroupChatProvider>();
    final group = groupProvider.getGroupById(widget.groupId);
    if (group == null) return;
    final messages = groupProvider.getMessages(widget.groupId);
    if (messages.isEmpty) {
      _showInfo('暂无聊天记录可导出');
      return;
    }
    try {
      final bytes = await ChatRecordsService.buildExportZip(
        characterName: group.name,
        messages: messages,
      );
      if (!mounted) return;
      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final fileName = '${group.name}_群聊记录_'
          '${now.year}${two(now.month)}${two(now.day)}_'
          '${two(now.hour)}${two(now.minute)}.zip';
      final savedName = await FilePickerHelper.saveFile(
        suggestedName: fileName,
        mimeType: 'application/zip',
        bytes: bytes,
      );
      if (!mounted || savedName == null) return; // 用户取消保存
      _showInfo('已将 ${messages.length} 条群聊记录（含图片/文件）保存为 zip：$savedName');
    } catch (e) {
      if (!mounted) return;
      _showInfo('导出失败：$e');
    }
  }

  /// 导入群聊聊天记录 zip：解析后追加到当前群聊，还原各角色发言。
  Future<void> _importGroupChat() async {
    try {
      final picked = await FilePickerHelper.pickFile();
      if (picked == null || !mounted) return; // 用户取消选择
      if (!picked.name.toLowerCase().endsWith('.zip')) {
        _showInfo('导入失败：请选择聊天记录 zip 文件');
        return;
      }
      final groupProvider = context.read<GroupChatProvider>();
      final messages = await ChatRecordsService.importZip(
        zipPath: picked.path,
        conversationId: widget.groupId,
      );
      if (messages.isEmpty) {
        _showInfo('导入失败：压缩包中没有可导入的消息');
        return;
      }
      await groupProvider.importMessages(
        groupId: widget.groupId,
        messages: messages,
      );
      if (!mounted) return;
      _scrollToBottom();
      _showInfo('已将 ${messages.length} 条聊天记录导入到当前群聊（${picked.name}）');
    } catch (e) {
      if (!mounted) return;
      _showInfo('导入失败：$e');
    }
  }

  /// 发送图片消息（用户）：本地插入图片气泡，不触发回复。
  void _handlePickImage(String imagePath) {
    context.read<GroupChatProvider>().sendImageMessage(
          groupId: widget.groupId,
          imagePath: imagePath,
        );
    _scrollToBottom();
  }

  /// 发送文件消息（用户）：本地插入文件气泡，不触发回复。
  void _handlePickFile(String filePath, String fileName) {
    context.read<GroupChatProvider>().sendFileMessage(
          groupId: widget.groupId,
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

  // ─── 长按气泡菜单 ─────────────────────────────────────────

  /// 长按气泡：在气泡旁弹出灰色菜单面板
  void _showBubbleMenu(Message message, GlobalKey bubbleKey) {
    _menuOverlay?.remove();

    final items = _buildMenuItems(message);
    final RenderBox? renderBox =
        bubbleKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final bubblePosition = renderBox.localToGlobal(Offset.zero);
    final bubbleSize = renderBox.size;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // 菜单尺寸：按等宽等高按钮网格推算（见 _menuPanelWidth / _menuPanelHeight）
    final double menuWidth = _menuPanelWidth(items.length);
    final double menuHeight = _menuPanelHeight(items.length);

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
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _closeMenu,
            ),
          ),
          Positioned(
            left: left,
            top: top,
            width: menuWidth,
            child: _buildMenuPanel(items),
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

  // ─── 剧情建议（群聊） ────────────────────────────────────

  /// 剧情建议：先询问用户是否有补充，再基于群聊上下文生成建议，
  /// 点选一条填入输入框（可编辑后发送），语C / 短信通用。
  Future<void> _plotSuggestion() async {
    final chatSettings = context.read<ChatSettingsProvider>();
    final api = context.read<ApiProvider>();
    final model = api.getModelById(chatSettings.selectedModelId);
    if (model == null) {
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('未选择模型'),
          content: const Text(
            '无法生成剧情建议。请在聊天设置里选择模型后再试。',
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
      return;
    }

    final controller = TextEditingController();
    final supplement = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('剧情建议'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '生成前有补充要交代吗？会写进这次的建议里。',
                style: TextStyle(fontSize: 13, height: 1.45),
              ),
              const SizedBox(height: 10),
              CupertinoTextField(
                controller: controller,
                autofocus: true,
                maxLines: 4,
                minLines: 2,
                placeholder: '可选：想发展的方向、禁忌、心情…',
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('生成建议'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || supplement == null) return;

    final groupProvider = context.read<GroupChatProvider>();
    final group = groupProvider.getGroupById(widget.groupId);
    final charProvider = context.read<CharacterProvider>();
    final memberNames = <String>[
      for (final id in group?.memberCharacterIds ?? const <String>[])
        if (charProvider.getCharacterById(id)?.displayName.trim().isNotEmpty ==
            true)
          charProvider.getCharacterById(id)!.displayName.trim(),
    ];
    final userNickname = context.read<AuthProvider>().user?.nickname ?? '用户';
    // 群聊不套用单一角色人设：建议是给用户出主意，不是角色发言
    final systemPrompt = '当前是群聊「${group?.name ?? ''}」。\n'
        '群成员（角色）：${memberNames.isEmpty ? '（无）' : memberNames.join('、')}。\n'
        '用户昵称：$userNickname（你正在帮这个人出主意）。\n'
        '你的任务是作为对话剧情顾问，给用户提供可以直接发进群聊的消息建议，'
        '帮助ta推进群聊对话，而不是扮演任何群成员发言。';

    final chatMessages = groupProvider.getMessages(widget.groupId);
    final contextCount = (group?.contextCount ?? chatSettings.contextCount) > 0
        ? (group?.contextCount ?? chatSettings.contextCount)
        : 20;
    final texts = chatMessages
        .where((m) =>
            (m.type == MessageType.text || m.type == MessageType.narration) &&
            m.content.trim().isNotEmpty)
        .toList();
    final start = texts.length > contextCount ? texts.length - contextCount : 0;
    final historyMessages = <Map<String, String>>[
      for (final m in texts.sublist(start))
        {
          'role': m.isFromUser ? 'user' : 'assistant',
          'content': m.senderName.trim().isEmpty
              ? m.content
              : '${m.senderName}：${m.content}',
        },
    ];

    if (!mounted) return;
    showCupertinoDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const CupertinoAlertDialog(
        title: Text('剧情建议'),
        content: Padding(
          padding: EdgeInsets.only(top: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CupertinoActivityIndicator(),
              SizedBox(width: 12),
              Text('正在生成建议…'),
            ],
          ),
        ),
      ),
    );
    try {
      final result = await generatePlotSuggestions(
        model: model,
        systemPrompt: systemPrompt,
        historyMessages: historyMessages,
        userSupplement: supplement,
        roleplayMode: chatSettings.isRoleplayMode,
      );
      await TokenUsageProvider.instance.addUsage(
        widget.groupId,
        result.usage,
        label: group?.name ?? '群聊',
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      final suggestions = result.messages
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (suggestions.isEmpty) {
        _showPlotTip('没有生成有效的剧情建议，可稍后重试');
        return;
      }
      _showPlotSuggestionResult(suggestions);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _showPlotTip('生成失败：${LLMService.describeException(e)}');
    }
  }

  void _showPlotTip(String message) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('提示'),
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

  /// 剧情建议结果：点选一条填入群聊输入框
  void _showPlotSuggestionResult(List<String> suggestions) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('剧情建议'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '点选一条填入输入框，可编辑后发送',
              style: TextStyle(fontSize: 12, color: ctx.textSecondaryColor),
            ),
            const SizedBox(height: 10),
            for (final suggestion in suggestions) ...[
              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  color: ctx.fieldBgColor,
                  borderRadius: BorderRadius.circular(10),
                  alignment: Alignment.centerLeft,
                  onPressed: () {
                    Navigator.pop(ctx);
                    _inputKey.currentState?.setText(suggestion);
                  },
                  child: Text(
                    suggestion,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: ctx.textPrimaryColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 构建长按菜单项：复制 / 选择文本 / 引用 +（我方）撤回或（角色）删除
  List<Widget> _buildMenuItems(Message message) {
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
          setState(() => _quoteMessage = message);
        },
      ),
      _menuItem(
        icon: CupertinoIcons.bookmark,
        label: '保存为记忆点',
        onTap: () {
          _closeMenu();
          _saveAsMemory(message);
        },
      ),
    ];
    if (message.isFromUser) {
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
          icon: CupertinoIcons.delete,
          label: '删除',
          onTap: () {
            _closeMenu();
            context
                .read<GroupChatProvider>()
                .deleteMessage(widget.groupId, message.id);
          },
        ),
      );
    }
    return items;
  }

  /// 撤回消息（我方）：删除消息，中断回复轮，内容回填输入框供重新编辑
  void _withdrawMessage(Message message) {
    context
        .read<GroupChatProvider>()
        .withdrawMessage(widget.groupId, message.id);
    _inputKey.currentState?.setText(message.content);
    _inputKey.currentState?.focus();
    if (_quoteMessage?.id == message.id) {
      setState(() => _quoteMessage = null);
    }
  }

  /// 保存单条消息为角色持久化记忆点（与私聊一致）：
  /// - 角色消息 → 存入该角色自己的记忆
  /// - 用户消息 → 存入群内所有角色（全员记住用户说的话）
  /// 后续群聊提示词会自动拼入这些记忆点。
  Future<void> _saveAsMemory(Message message) async {
    if (message.type != MessageType.text || message.content.trim().isEmpty) {
      _showInfo('选中的消息不包含可保存的文字内容');
      return;
    }
    final groupProvider = context.read<GroupChatProvider>();
    final group = groupProvider.getGroupById(widget.groupId);
    if (group == null) return;
    final charProvider = context.read<CharacterProvider>();
    final memoryProvider = context.read<MemoryPointProvider>();
    final userName = context.read<AuthProvider>().user?.nickname ?? '用户';
    final text = message.content.trim();

    final List<String> targetIds;
    final String targetLabel;
    final String point;
    if (message.isFromUser) {
      // 用户消息：群内所有角色共同记住
      targetIds = group.memberCharacterIds
          .where((id) => charProvider.getCharacterById(id) != null)
          .toList();
      if (targetIds.isEmpty) return;
      targetLabel = '群内所有角色';
      point = '$userName说："$text"';
    } else {
      // 角色消息：存入该角色自己的记忆
      final sender = charProvider.getCharacterById(message.senderCharacterId);
      if (sender == null) return;
      targetIds = [sender.id];
      targetLabel = sender.displayName;
      point = '${sender.displayName}说："$text"';
    }

    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('保存为记忆点'),
        content: Text(
          '将以下内容保存为「$targetLabel」的一条记忆点：\n\n"$text"',
          style: const TextStyle(fontSize: 14, height: 1.5),
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

    for (final id in targetIds) {
      await memoryProvider.addPoints(id, [point]);
    }
    if (!mounted) return;
    _showInfo(
      '已保存为「$targetLabel」的一条记忆点，后续群聊中角色会自动记住这些内容。',
    );
  }

  void _showInfo(String message) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('提示'),
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

  /// 长按菜单按钮：等宽等高，保证多行时纵向对齐
  static const double _menuCellWidth = 74;
  static const double _menuCellHeight = 46;
  static const double _menuSpacing = 4;
  static const double _menuPadding = 8;

  /// Border.all 的线宽；Container 会把它计入内边距（decoration.padding），
  /// 尺寸公式必须预留，否则 Positioned 约束会比面板固有宽高各窄 1dp（debug 溢出黄条）。
  static const double _menuBorder = 0.5;

  /// 单行最多按钮数（再宽会超出手机屏宽）
  static const int _menuMaxColumns = 3;

  /// 行数：按每行最多 [_menuMaxColumns] 个换行
  int _menuRowCount(int itemCount) =>
      (itemCount + _menuMaxColumns - 1) ~/ _menuMaxColumns;

  /// 单行最大按钮数：用于推导面板宽度（各行尽量均分后最宽的一行）
  int _menuColumns(int itemCount) {
    final rows = _menuRowCount(itemCount);
    return (itemCount + rows - 1) ~/ rows;
  }

  double _menuPanelWidth(int itemCount) {
    final columns = _menuColumns(itemCount);
    return columns * _menuCellWidth +
        (columns - 1) * _menuSpacing +
        (_menuPadding + _menuBorder) * 2;
  }

  double _menuPanelHeight(int itemCount) {
    final rows = _menuRowCount(itemCount);
    return rows * _menuCellHeight +
        (rows - 1) * _menuSpacing +
        (_menuPadding + _menuBorder) * 2;
  }

  Widget _buildMenuPanel(List<Widget> items) =>
      ChatBubbleMenuPanel(items: items);

  Widget _menuItem(
          {required IconData icon,
          required String label,
          required VoidCallback onTap}) =>
      ChatBubbleMenuItem(icon: icon, label: label, onTap: onTap);

  // ─── 功能检测（模型是否支持图片发送） ─────────────────────

  /// 【功能检测】测试当前选中的全局聊天模型是否支持图片发送；
  /// 检测结果用于提示（相册/拍照始终可用，不因检测结果禁用）。
  Future<bool> _runFeatureDetect() async {
    final chatSettings = context.read<ChatSettingsProvider>();
    final model =
        context.read<ApiProvider>().getModelById(chatSettings.selectedModelId);
    if (model == null) {
      _showNoModelDialog();
      return false;
    }
    try {
      final supported = await LLMService.testImageSupport(model);
      if (!mounted) return supported;
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

  /// 未选择模型时的引导弹窗
  void _showNoModelDialog() {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('未选择模型'),
        content: const Text('请先在「API 设置」中选择聊天模型，或为群内角色单独指定模型后再试。'),
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

  /// 打开群聊上下文设置（底部加号面板入口）
  void _openContextSettings() {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => GroupChatSettingsScreen(groupId: widget.groupId),
      ),
    );
  }

  /// 触发群聊回复（第二阶段：对号按钮）。
  Future<void> _triggerReply() async {
    final groupProvider = context.read<GroupChatProvider>();
    final group = groupProvider.getGroupById(widget.groupId);
    if (group == null) return;

    final chatSettings = context.read<ChatSettingsProvider>();
    final api = context.read<ApiProvider>();
    final charProvider = context.read<CharacterProvider>();
    final memoryProvider = context.read<MemoryPointProvider>();
    final chatProvider = context.read<ChatProvider>();
    final userNickname = context.read<AuthProvider>().user?.nickname ?? '用户';

    final members = <GroupMemberReply>[];
    final missingModelNames = <String>[];

    // 群聊共同记忆池：汇总群内全部成员各自的「用户长期记忆」，
    // 去重合并为一份共同记忆，群内所有成员共用同一份，
    // 让群成员共享对用户/事件的集体记忆（不再各自持有私有记忆点）
    final sharedMemoryPool = <String>[];
    {
      final seen = <String>{};
      for (final id in group.memberCharacterIds) {
        for (final p in memoryProvider.pointsFor(id)) {
          final content = p.content.trim();
          if (content.isEmpty || !seen.add(content)) continue;
          sharedMemoryPool.add(content);
        }
      }
    }

    for (final id in group.memberCharacterIds) {
      final c = charProvider.getCharacterById(id);
      if (c == null) continue;
      // 模型解析顺序：角色指定模型 → 角色缺省模型 → 全局聊天模型，
      // 保证未单独指定模型的角色在全局未配置时也有兜底模型应答
      final modelId = c.modelId.isNotEmpty
          ? c.modelId
          : c.defaultModelId.isNotEmpty
              ? c.defaultModelId
              : chatSettings.selectedModelId;
      final model = api.getModelById(modelId);
      if (model == null) {
        missingModelNames.add(c.displayName);
        continue;
      }
      members.add(GroupMemberReply(
        characterId: c.id,
        // 语C不带联系人备注；短信模式仍使用备注优先的显示名。
        name: chatSettings.isRoleplayMode ? c.name : c.displayName,
        systemPrompt: c.systemPrompt,
        userRelationship: c.userRelationship,
        activeStart: c.activeStart,
        activeEnd: c.activeEnd,
        model: model,
        // 群聊记忆：所有成员共用群内汇总的共同记忆池
        memoryPoints: sharedMemoryPool,
        avatarBase64: c.avatar,
        // 角色记忆池：朋友圈 / 近期私聊 / 其他群内容 / 资料卡。
        // 群聊场景排除当前群（当前群历史已作为对话上下文传入），
        // 保留各角色近期的私聊内容与朋友圈动态，保持跨场景记忆连贯
        memoryPool: chatSettings.isRoleplayMode
            ? ''
            : MemoryPoolBuilder.build(
                character: c,
                chatProvider: chatProvider,
                groupChatProvider: groupProvider,
                chatSettings: chatSettings,
                user: context.read<AuthProvider>().user,
                includePrivateHistory: true,
                excludeGroupId: widget.groupId,
              ),
      ));
    }

    if (members.isEmpty) {
      _showEmptyMembersDialog(missingModelNames);
      return;
    }

    // 上下文条数：群聊可单独设置（null=跟随全局聊天设置；0=无限制）
    final groupContextCount = group.contextCount;
    final effectiveContextCount =
        groupContextCount ?? chatSettings.contextCount;

    groupProvider.runGroupReply(
      groupId: widget.groupId,
      members: members,
      userNickname: userNickname,
      contextCount: effectiveContextCount,
      roleplayMode: chatSettings.isRoleplayMode,
      // @ 提及的角色优先且必定回复
      mentionedCharacterIds: _pendingMentions,
      // 关闭「允许角色发送表情包」时不注入检索器，查询标记会被静默忽略。
      findSticker: context.read<SettingsProvider>().allowStickerSend
          ? (query) => context.read<StickerProvider>().pickStickerForRole(query)
          : null,
    );
    _pendingMentions = const [];
  }

  void _showEmptyMembersDialog(List<String> missingModelNames) {
    final message = missingModelNames.isNotEmpty
        ? '群内角色尚未配置可用模型，请先到「API 设置」添加模型，'
            '或为角色单独指定模型后再试。'
        : '群内没有可用的角色成员，请到群聊详情添加成员后再试。';
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('无法发起群聊回复'),
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

  Widget _buildTimeLabel(DateTime time) => ChatTimeLabel(time: time);

  void _openGroupDetail() {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => GroupChatDetailScreen(groupId: widget.groupId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final group =
        context.watch<GroupChatProvider>().getGroupById(widget.groupId);
    final title = group == null ? '群聊' : '${group.name}（${group.memberCount}）';

    final body = Consumer<ChatBackgroundProvider>(
      builder: (context, bgProvider, _) {
        final bgInfo = bgProvider.getInfoSync(widget.groupId);
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
                      imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                      child: Image.file(
                        File(bgInfo.imagePath),
                        fit: BoxFit.cover,
                        width: bgSize.width,
                        height: bgSize.height,
                        cacheWidth: decodeWidth,
                      ),
                    );
                  },
                ),
              ),
            // 消息内容层
            Column(
              children: [
                Expanded(
                  // Only the message count controls list structure. Message
                  // rows subscribe to their own provider revision, so an
                  // unrelated reply-progress notification stays cheap.
                  child: Selector<GroupChatProvider, int>(
                    selector: (_, p) => p.getMessages(widget.groupId).length,
                    builder: (context, _, __) {
                      final groupProvider = context.read<GroupChatProvider>();
                      final messages =
                          groupProvider.getMessages(widget.groupId);
                      if (messages.length != _lastRenderedCount) {
                        final added = _lastRenderedCount >= 0 &&
                            messages.length > _lastRenderedCount;
                        _lastRenderedCount = messages.length;
                        if (added && !_isAtBottom()) _scrollToBottom();
                      }

                      final userAvatar =
                          context.read<AuthProvider>().user?.avatar ?? '';

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
                                  CupertinoIcons.person_3_fill,
                                  size: 48,
                                  color: context.textSecondaryColor,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  '在群聊里开始聊天吧',
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

                      // 预计算群成员头像 map：避免每条消息在 build 时都做一次
                      // CharacterProvider 线性查找（长聊天时省去大量重复查找）
                      final charProvider = context.read<CharacterProvider>();
                      final group = context
                          .read<GroupChatProvider>()
                          .getGroupById(widget.groupId);
                      final avatarById = <String, String>{};
                      if (group != null) {
                        for (final id in group.memberCharacterIds) {
                          final c = charProvider.getCharacterById(id);
                          if (c != null && c.avatar.isNotEmpty) {
                            avatarById[id] = c.avatar;
                          }
                        }
                      }

                      return Container(
                        color: hasBg
                            ? context.chatBgColor.withValues(alpha: 0.86)
                            : context.chatBgColor,
                        child: ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final msg = messages[messages.length - 1 - index];
                            final prev = index < messages.length - 1
                                ? messages[messages.length - 2 - index]
                                : null;
                            final showTime = prev == null ||
                                msg.createdAt
                                        .difference(prev.createdAt)
                                        .inMinutes >=
                                    10;
                            final isUser = msg.isFromUser;
                            final characterAvatar = isUser
                                ? userAvatar
                                : (avatarById[msg.senderCharacterId] ?? '');
                            return RepaintBoundary(
                              key: ValueKey(msg.id),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (showTime) _buildTimeLabel(msg.createdAt),
                                  _GroupChatMessageTile(
                                    groupId: widget.groupId,
                                    message: msg,
                                    userAvatar: userAvatar,
                                    characterAvatar: characterAvatar,
                                    senderName: isUser ? '' : msg.senderName,
                                    onLongPress: (message, bubbleKey) =>
                                        _showBubbleMenu(message, bubbleKey),
                                    onFileTap: _openFileMessage,
                                    onCharacterAvatarTap:
                                        isUser || msg.senderCharacterId.isEmpty
                                            ? null
                                            : () => _navigateToCharacterChat(
                                                msg.senderCharacterId),
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
                Consumer<GroupChatProvider>(
                  builder: (context, groupProvider, _) {
                    final lastMessage =
                        groupProvider.getMessages(widget.groupId).lastOrNull;
                    final replyEnabled =
                        lastMessage != null && lastMessage.isFromUser;
                    final error = groupProvider.lastError;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
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
                                  onTap: groupProvider.clearError,
                                  child: Icon(
                                    CupertinoIcons.xmark_circle_fill,
                                    size: 16,
                                    color: context.textSecondaryColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _quoteMessage!.isFromUser
                                              ? '引用 我'
                                              : '引用 ${_quoteMessage!.senderName}',
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
                                    onTap: () =>
                                        setState(() => _quoteMessage = null),
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
                        GroupMessageInput(
                          key: _inputKey,
                          onSend: _handleSend,
                          onRequestReply: _triggerReply,
                          replyEnabled: replyEnabled,
                          onPickImage: _handlePickImage,
                          onPickFile: _handlePickFile,
                          onFeatureDetect: _runFeatureDetect,
                          onMentionRequest: _onMentionRequest,
                          onExport: _exportGroupChat,
                          onImport: _importGroupChat,
                          onContextSettings: _openContextSettings,
                          onPlotSuggestion: _plotSuggestion,
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
    );

    if (widget.embedded) return body;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Selector<GroupChatProvider, (bool, int, int)>(
          selector: (_, p) => (
            p.isReplying(widget.groupId),
            p.replyDone,
            p.replyTotal,
          ),
          builder: (context, data, _) {
            final (replying, done, total) = data;
            // 终末地 UI 样式：群名称靠左 + 群简介副标题 + 回复中黄色呼吸输入状态点
            if (context.uiStyle == UiStyle.zmd) {
              return Align(
                alignment: Alignment.centerLeft,
                child: ChatTitleBar(
                  name: group?.name ?? '群聊',
                  isGroup: true,
                  groupIntro: group?.description ?? '',
                  inputStatus: replying ? '输入中（$done/$total）' : null,
                ),
              );
            }
            return Text(
              replying ? '群成员正在回复……（$done/$total）' : title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            );
          },
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _openGroupDetail,
          child: const Icon(CupertinoIcons.line_horizontal_3),
        ),
      ),
      child: body,
    );
  }
}

/// Keeps a group message bubble local to its own content revision. Group
/// reply progress still notifies the provider, but does not rebuild every row.
class _GroupChatMessageTile extends StatefulWidget {
  final String groupId;
  final Message message;
  final String userAvatar;
  final String characterAvatar;
  final String senderName;
  final Future<void> Function(String filePath)? onFileTap;
  final VoidCallback? onCharacterAvatarTap;
  final void Function(Message message, GlobalKey bubbleKey)? onLongPress;

  const _GroupChatMessageTile({
    required this.groupId,
    required this.message,
    required this.userAvatar,
    required this.characterAvatar,
    required this.senderName,
    this.onFileTap,
    this.onCharacterAvatarTap,
    this.onLongPress,
  });

  @override
  State<_GroupChatMessageTile> createState() => _GroupChatMessageTileState();
}

class _GroupChatMessageTileState extends State<_GroupChatMessageTile> {
  late final GroupChatProvider _provider;
  late int _revision;

  @override
  void initState() {
    super.initState();
    _provider = context.read<GroupChatProvider>();
    _revision = _provider.messageRevisionFor(
      widget.groupId,
      widget.message.id,
    );
    _provider.addListener(_handleProviderChanged);
  }

  void _handleProviderChanged() {
    if (!mounted) return;
    final next = _provider.messageRevisionFor(
      widget.groupId,
      widget.message.id,
    );
    if (next == _revision) return;
    _revision = next;
    setState(() {});
  }

  @override
  void dispose() {
    _provider.removeListener(_handleProviderChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = _provider.messageFor(widget.groupId, widget.message.id) ??
        widget.message;
    return ChatBubble(
      message: message,
      userAvatar: widget.userAvatar,
      characterAvatar: widget.characterAvatar,
      senderName: widget.senderName,
      onLongPress: widget.onLongPress,
      onFileTap: widget.onFileTap,
      onCharacterAvatarTap: widget.onCharacterAvatarTap,
    );
  }
}
