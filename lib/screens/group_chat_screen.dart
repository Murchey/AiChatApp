import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/character.dart';
import '../models/message.dart';
import '../providers/api_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_settings_provider.dart';
import '../providers/character_provider.dart';
import '../providers/group_chat_provider.dart';
import '../providers/memory_point_provider.dart';
import '../services/chat_records_service.dart';
import '../services/llm_service.dart';
import '../utils/app_toast.dart';
import '../utils/file_picker_helper.dart';
import '../widgets/character_avatar.dart';
import '../widgets/chat_bubble.dart';
import 'group_chat_detail_screen.dart';
import 'group_chat_settings_screen.dart';

/// 群聊会话页：用户发送消息（第一阶段）后，点击对号触发群内角色
/// 随机顺序、逐成员 LLM 判定是否插话、各自模型回复（第二阶段）。
///
/// 用户再次提交新消息会自增 Provider 内的回复轮次序号，立即打断旧轮。
class GroupChatScreen extends StatefulWidget {
  final String groupId;

  const GroupChatScreen({super.key, required this.groupId});

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final ScrollController _scrollController = ScrollController();
  static final DateFormat _timeFmt = DateFormat('HH:mm');
  static final DateFormat _dateFmt = DateFormat('M月d日 HH:mm');
  static final DateFormat _fullFmt = DateFormat('yyyy年M月d日 HH:mm');

  int _lastRenderedCount = -1;
  static const int _sendThrottleMs = 500;
  DateTime _lastSendAt = DateTime.fromMillisecondsSinceEpoch(0);
  // 输入框 key：撤回消息时把内容回填到输入框
  final GlobalKey<_GroupMessageInputState> _inputKey =
      GlobalKey<_GroupMessageInputState>();
  // 长按气泡引用的消息（非空时输入框上方显示引用条）
  Message? _quoteMessage;
  // 长按气泡悬浮菜单（Overlay）
  OverlayEntry? _menuOverlay;
  // @ 提及：名字 -> 角色 id（输入 @ 选择后记录；发送时按文本过滤出仍存在的提及）
  final Map<String, String> _mentionMap = {};
  // 最近一次发送消息中的 @ 提及 id，对号触发回复时传给 Provider 优先且必定回复
  List<String> _pendingMentions = const [];

  @override
  void dispose() {
    _menuOverlay?.remove();
    _scrollController.dispose();
    super.dispose();
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
          quoteSender: quote == null
              ? ''
              : (quote.isFromUser ? '我' : quote.senderName),
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

    // 菜单宽度/高度：4 项以内一行（64 高），更多则两行（128 高）
    final double menuWidth = items.length > 2 ? 260 : 190;
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
            child: Container(
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
            ),
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
    final userName =
        context.read<AuthProvider>().user?.nickname ?? '用户';
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

  // ─── 功能检测（群聊相册/拍照可用性） ─────────────────────

  /// 【功能检测】测试当前选中的全局聊天模型是否支持图片发送；
  /// 支持则返回 true（面板据此开启【相册】【拍照】）。
  Future<bool> _runFeatureDetect() async {
    final chatSettings = context.read<ChatSettingsProvider>();
    final model = context
        .read<ApiProvider>()
        .getModelById(chatSettings.selectedModelId);
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
    final userNickname =
        context.read<AuthProvider>().user?.nickname ?? '用户';

    final members = <GroupMemberReply>[];
    final missingModelNames = <String>[];
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
        name: c.displayName,
        systemPrompt: c.systemPrompt,
        userRelationship: c.userRelationship,
        activeStart: c.activeStart,
        activeEnd: c.activeEnd,
        model: model,
        memoryPoints: memoryProvider
            .pointsFor(c.id)
            .map((p) => p.content)
            .toList(),
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
      // @ 提及的角色优先且必定回复
      mentionedCharacterIds: _pendingMentions,
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
          style: TextStyle(fontSize: 11, color: context.textSecondaryColor),
        ),
      ),
    );
  }

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
    final group = context.watch<GroupChatProvider>().getGroupById(widget.groupId);
    final title = group == null
        ? '群聊'
        : '${group.name}（${group.memberCount}）';

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Selector<GroupChatProvider, bool>(
          selector: (_, p) => p.isReplying(widget.groupId),
          builder: (context, replying, _) => Text(
            replying ? '群成员正在输入……' : title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _openGroupDetail,
          child: const Icon(CupertinoIcons.line_horizontal_3),
        ),
      ),
      child: Column(
        children: [
          Expanded(
            // 用 Selector 只监听消息列表引用变化：回复轮/错误/成员变更等
            // 无关通知不再重建整棵消息列表，长聊天下明显减少无谓 build
            child: Selector<GroupChatProvider, List<Message>>(
              selector: (_, p) => p.getMessages(widget.groupId),
              shouldRebuild: (a, b) => !identical(a, b),
              builder: (context, messages, _) {
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
                    color: context.chatBgColor,
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
                final group =
                    context.read<GroupChatProvider>().getGroupById(widget.groupId);
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
                  color: context.chatBgColor,
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
                          msg.createdAt.difference(prev.createdAt).inMinutes >=
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
                            ChatBubble(
                              message: msg,
                              userAvatar: userAvatar,
                              characterAvatar: characterAvatar,
                              senderName:
                                  isUser ? '' : msg.senderName,
                              onLongPress: (message, bubbleKey) =>
                                  _showBubbleMenu(message, bubbleKey),
                              onFileTap: _openFileMessage,
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
              final replyEnabled = lastMessage != null && lastMessage.isFromUser;
              final error = groupProvider.lastError;
              // 当前全局聊天模型已检测为视觉模型（缓存），相册/拍照直接放开
              final visionReady = context
                      .watch<ApiProvider>()
                      .isVisionSupported(context
                          .watch<ChatSettingsProvider>()
                          .selectedModelId) ==
                  true;
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
                  // 引用条（长按消息选择「引用」后显示在输入框上方）
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
                              onTap: () => setState(() => _quoteMessage = null),
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
                  _GroupMessageInput(
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
                    imageReady: visionReady,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 群聊底部输入框：与私聊输入框视觉一致（方形 5px 圆角 + 加号面板 + 发送/对号）。
/// 加号面板含【相册】【拍照】【文件】【功能检测】【导出记录】【导入记录】；
/// 输入 @ 触发成员选择（onMentionRequest）；对号触发群聊回复。
class _GroupMessageInput extends StatefulWidget {
  final ValueChanged<String> onSend;
  final VoidCallback onRequestReply;
  final bool replyEnabled;
  final ValueChanged<String>? onPickImage;
  final void Function(String, String)? onPickFile;
  final Future<bool> Function()? onFeatureDetect;
  /// 输入 @ 时回调（由外层弹出成员选择）
  final VoidCallback? onMentionRequest;
  final VoidCallback? onExport;
  final VoidCallback? onImport;
  /// 打开群聊上下文设置（加号面板入口）
  final VoidCallback? onContextSettings;
  final bool imageReady;

  const _GroupMessageInput({
    super.key,
    required this.onSend,
    required this.onRequestReply,
    required this.replyEnabled,
    this.onPickImage,
    this.onPickFile,
    this.onFeatureDetect,
    this.onMentionRequest,
    this.onExport,
    this.onImport,
    this.onContextSettings,
    this.imageReady = false,
  });

  @override
  State<_GroupMessageInput> createState() => _GroupMessageInputState();
}

class _GroupMessageInputState extends State<_GroupMessageInput> {
  // 原生系统文件选择（MainActivity 中实现，Android 专用）
  static const MethodChannel _fileChannel =
      MethodChannel('com.aichat.ai_chat/files');

  final TextEditingController _controller = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final FocusNode _inputFocusNode = FocusNode();
  bool _hasText = false;
  bool _showGrid = false;
  bool _detectedReady = false; // 本次页面内手动检测通过（相册/拍照可用）
  bool _prevEndsAt = false; // @ 边沿检测：上一次文本是否以 @ 结尾
  bool get _imageReady => widget.imageReady || _detectedReady;

  /// 外部（撤回消息）可回填输入框内容
  void setText(String text) {
    _controller.text = text;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: text.length),
    );
    setState(() => _hasText = text.trim().isNotEmpty);
  }

  /// 输入 @ 选中成员后插入「@名字 」（替换文本末尾孤立的 @）。
  void appendMention(String name) {
    var text = _controller.text;
    if (text.endsWith('@')) {
      text = text.substring(0, text.length - 1);
    }
    final offset = _controller.selection.isValid
        ? _controller.selection.baseOffset.clamp(0, text.length)
        : text.length;
    final insert = '@$name ';
    final newText =
        text.substring(0, offset) + insert + text.substring(offset);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: offset + insert.length),
    );
    setState(() => _hasText = newText.trim().isNotEmpty);
  }

  void focus() {
    FocusScope.of(context).requestFocus(_inputFocusNode);
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() => _hasText = _controller.text.trim().isNotEmpty);
    });
    // 点击（聚焦）输入框时自动折叠面板
    _inputFocusNode.addListener(() {
      if (_inputFocusNode.hasFocus && _showGrid) {
        setState(() => _showGrid = false);
      }
    });
  }

  /// 文本变化（用户输入）处理：检测「刚输入 @」边沿，触发成员选择。
  /// 用 onChanged（仅用户编辑触发）而非原始 controller 监听，
  /// 并通过微任务延迟 push 弹层，避免同步 push 路由导致的触发失败。
  void _handleInputChanged(String text) {
    final endsWithAt = text.endsWith('@');
    final justTypedAt = endsWithAt && !_prevEndsAt;
    _prevEndsAt = endsWithAt;
    if (justTypedAt) {
      Future.microtask(() => widget.onMentionRequest?.call());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
  }

  void _handleToggleGrid() {
    if (_showGrid) {
      // 面板已打开：点击加号关闭面板，恢复键盘（聚焦输入框）
      FocusScope.of(context).requestFocus(_inputFocusNode);
      setState(() => _showGrid = false);
    } else {
      // 面板未打开：点击加号，收起软键盘，只展示面板
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _showGrid = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 输入栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: context.navBarColor,
            border: Border(top: BorderSide(color: context.separatorColor)),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                // 左侧加号：展开功能面板（相册/拍照/文件/功能检测）
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _handleToggleGrid,
                  child: Icon(
                    _showGrid
                        ? CupertinoIcons.keyboard
                        : CupertinoIcons.add_circled,
                    color: context.textSecondaryColor,
                  ),
                ),
                Expanded(
                  child: CupertinoTextField(
                    controller: _controller,
                    focusNode: _inputFocusNode,
                    onChanged: _handleInputChanged,
                    placeholder: '输入消息...',
                    maxLines: 4,
                    minLines: 1,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    style: TextStyle(
                      fontSize: 16,
                      color: context.textPrimaryColor,
                    ),
                    decoration: BoxDecoration(
                      color: context.fieldBgColor,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
                // 右侧按钮：有输入内容时显示"发送"，无内容时显示"对号"（触发群聊回复）
                if (_hasText) ...[
                  SizedBox(
                    width: 64,
                    height: 40,
                    child: CupertinoButton.filled(
                      onPressed: _handleSend,
                      padding: EdgeInsets.zero,
                      borderRadius: BorderRadius.circular(10),
                      child: const Text(
                        '发送',
                        style: TextStyle(
                          fontSize: 14,
                          color: CupertinoColors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ] else
                  CupertinoButton(
                    padding: const EdgeInsets.all(4),
                    onPressed:
                        widget.replyEnabled ? widget.onRequestReply : null,
                    child: Icon(
                      CupertinoIcons.checkmark_circle_fill,
                      size: 30,
                      color: widget.replyEnabled
                          ? context.accentColor
                          : context.textSecondaryColor,
                    ),
                  ),
              ],
            ),
          ),
        ),
        // 加号功能面板（位于输入框下方，将输入框抬起）
        if (_showGrid) _buildGridPanel(context),
      ],
    );
  }

  Widget _buildGridPanel(BuildContext context) {
    final items = [
      _GroupGridItem(
        icon: CupertinoIcons.photo,
        label: '相册',
        enabled: _imageReady,
        onTap: () async {
          setState(() => _showGrid = false);
          final file = await _picker.pickImage(source: ImageSource.gallery);
          if (file != null && widget.onPickImage != null) {
            widget.onPickImage!(file.path);
          }
        },
      ),
      _GroupGridItem(
        icon: CupertinoIcons.camera,
        label: '拍照',
        enabled: _imageReady,
        onTap: () async {
          setState(() => _showGrid = false);
          final file = await _picker.pickImage(source: ImageSource.camera);
          if (file != null && widget.onPickImage != null) {
            widget.onPickImage!(file.path);
          }
        },
      ),
      _GroupGridItem(
        icon: CupertinoIcons.doc,
        label: '文件',
        onTap: () async {
          setState(() => _showGrid = false);
          try {
            final result = await _fileChannel.invokeMethod('pickFile');
            if (result != null && widget.onPickFile != null) {
              final map = Map<String, dynamic>.from(result as Map);
              widget.onPickFile!(map['path'] as String, map['name'] as String);
            }
          } on PlatformException catch (e) {
            if (mounted) _showPickError(e.message ?? '选择文件失败');
          } catch (_) {
            if (mounted) _showPickError('选择文件失败，请重试');
          }
        },
      ),
      _GroupGridItem(
        icon: CupertinoIcons.wrench,
        label: '功能检测',
        onTap: () async {
          setState(() => _showGrid = false);
          final ok = await widget.onFeatureDetect?.call() ?? false;
          if (mounted) {
            setState(() => _detectedReady = ok);
          }
        },
      ),
      _GroupGridItem(
        icon: CupertinoIcons.arrow_down_circle,
        label: '导出记录',
        onTap: () {
          setState(() => _showGrid = false);
          widget.onExport?.call();
        },
      ),
      _GroupGridItem(
        icon: CupertinoIcons.arrow_up_circle,
        label: '导入记录',
        onTap: () {
          setState(() => _showGrid = false);
          widget.onImport?.call();
        },
      ),
      _GroupGridItem(
        icon: CupertinoIcons.slider_horizontal_3,
        label: '上下文',
        onTap: () {
          setState(() => _showGrid = false);
          widget.onContextSettings?.call();
        },
      ),
    ];

    return Container(
      color: context.navBarColor,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: SafeArea(
        top: false,
        child: GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 4,
          mainAxisSpacing: 12,
          crossAxisSpacing: 16,
          children: items
              .map((item) => _buildGridTile(context, item))
              .toList(),
        ),
      ),
    );
  }

  Widget _buildGridTile(BuildContext context, _GroupGridItem item) {
    final enabled = item.enabled;
    return GestureDetector(
      // 禁用的【相册】【拍照】：点击提示先做功能检测
      onTap: enabled
          ? item.onTap
          : () => showAppToast('请先点击【功能检测】进行模型能力测试'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: enabled
                  ? context.fieldBgColor
                  : context.fieldBgColor.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(
              item.icon,
              size: 28,
              color: enabled
                  ? context.textPrimaryColor
                  : context.textSecondaryColor.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.label,
            style: TextStyle(
              fontSize: 12,
              color: enabled
                  ? context.textSecondaryColor
                  : context.textSecondaryColor.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  void _showPickError(String message) {
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
}

class _GroupGridItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  const _GroupGridItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });
}
