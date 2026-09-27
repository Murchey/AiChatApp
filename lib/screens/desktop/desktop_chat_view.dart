import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/api_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/character_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/chat_settings_provider.dart';
import '../../providers/group_chat_provider.dart';
import '../../providers/memory_point_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/sticker_provider.dart';
import '../../models/message.dart';
import '../../services/memory_pool_builder.dart';
import '../../widgets/chat_bubble.dart';
import '../../widgets/message_input.dart';
import '../chat_detail_screen.dart';
import '../chat_settings_screen.dart';
import '../sticker_picker_screen.dart';
import 'desktop_context_menu.dart';
import 'desktop_theme.dart';

enum _DesktopChatPanel { none, settings, detail }

/// 电脑端聊天面板：完整消息流 + 完整输入条。
/// 交互为桌面模型：右键菜单、Enter 发送、侧栏面板（非手机推入页）。
/// 独立于手机端 ChatScreen，互不影响。
class DesktopChatView extends StatefulWidget {
  final String conversationId;
  final String characterName;
  final String characterAvatar;

  const DesktopChatView({
    super.key,
    required this.conversationId,
    required this.characterName,
    this.characterAvatar = '',
  });

  @override
  State<DesktopChatView> createState() => _DesktopChatViewState();
}

class _DesktopChatViewState extends State<DesktopChatView> {
  final _scroll = ScrollController();
  final _inputKey = GlobalKey<MessageInputState>();
  final _shortcutsFocus = FocusNode();
  String? _pendingImagePath;
  String? _pendingStickerPath;
  String? _pendingStickerLabel;
  _DesktopChatPanel _panel = _DesktopChatPanel.none;
  Message? _quoteMessage;
  int _lastCount = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().markConversationActive(widget.conversationId);
      _scrollToBottom();
      _shortcutsFocus.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant DesktopChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      setState(() => _panel = _DesktopChatPanel.none);
      context
          .read<ChatProvider>()
          .markConversationInactive(oldWidget.conversationId);
      context
          .read<ChatProvider>()
          .markConversationActive(widget.conversationId);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  @override
  void dispose() {
    context
        .read<ChatProvider>()
        .markConversationInactive(widget.conversationId);
    _scroll.dispose();
    _shortcutsFocus.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent + 80,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  bool get _nearBottom {
    if (!_scroll.hasClients) return true;
    final pos = _scroll.position;
    return pos.pixels >= pos.maxScrollExtent - 80;
  }

  Future<void> _handlePickImage(String path) async {
    await context.read<ChatProvider>().sendImageMessage(
          conversationId: widget.conversationId,
          imagePath: path,
          characterName: widget.characterName,
        );
    _pendingImagePath = path;
    _scrollToBottom();
  }

  Future<void> _handlePickFile(String path, String name) async {
    await context.read<ChatProvider>().sendFileMessage(
          conversationId: widget.conversationId,
          filePath: path,
          fileName: name,
        );
    _scrollToBottom();
  }

  Future<void> _handleSticker(StickerSelection selection) async {
    final label = (selection.label ?? '').trim();
    await context.read<ChatProvider>().sendStickerMessage(
          conversationId: widget.conversationId,
          stickerPath: selection.imagePath,
          label: label,
        );
    _pendingStickerPath = selection.imagePath;
    _pendingStickerLabel = label;
    _scrollToBottom();
  }

  /// 触发角色回复（对号按钮）
  Future<void> _requestReply() async {
    final imagePath = _pendingImagePath ?? _pendingStickerPath;
    final stickerLabel = _pendingStickerPath == null ? null : _pendingStickerLabel;
    _pendingImagePath = null;
    _pendingStickerPath = null;
    _pendingStickerLabel = null;
    await DesktopChatReply.trigger(
      context: context,
      conversationId: widget.conversationId,
      fallbackName: widget.characterName,
      replyToUser: true,
      imagePath: imagePath,
      stickerLabel: stickerLabel,
    );
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Focus(
      focusNode: _shortcutsFocus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          if (_panel != _DesktopChatPanel.none) {
            setState(() => _panel = _DesktopChatPanel.none);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Row(
        children: [
          Expanded(child: _buildChatColumn(p)),
          if (_panel != _DesktopChatPanel.none) _buildSidePanel(p),
        ],
      ),
    );
  }

  Widget _buildChatColumn(DesktopPalette p) {
    return ColoredBox(
      color: p.chatBg,
      child: Column(
        children: [
          _buildHeader(p),
          Expanded(
            child: Consumer<ChatProvider>(
              builder: (context, chat, _) {
                final messages = chat.getMessages(widget.conversationId);
                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      '和「${widget.characterName}」打个招呼吧',
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  );
                }
                // 仅在贴底时自动跟随新消息，避免打断用户回看历史
                if (_lastCount != messages.length) {
                  final first = _lastCount < 0;
                  final grew = !first && messages.length > _lastCount;
                  _lastCount = messages.length;
                  if (first || (grew && _nearBottom)) {
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => _scrollToBottom());
                  }
                }
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final m = messages[i];
                    return GestureDetector(
                      onSecondaryTapUp: (e) =>
                          _showMessageMenu(e.globalPosition, m),
                      child: ChatBubble(
                        message: m,
                        userAvatar:
                            context.read<AuthProvider>().user?.avatar ?? '',
                        characterAvatar: widget.characterAvatar,
                      ),
                    );
                  },
                );
              },
            ),
          ),
          _buildInput(p),
        ],
      ),
    );
  }

  void _showMessageMenu(Offset pos, Message m) {
    showDesktopContextMenu(
      context,
      globalPos: pos,
      items: [
        DesktopMenuItem(
          label: '复制',
          icon: CupertinoIcons.doc_on_doc,
          onTap: () {
            Clipboard.setData(ClipboardData(text: m.content));
          },
        ),
        DesktopMenuItem(
          label: '引用回复',
          icon: CupertinoIcons.reply,
          onTap: () => setState(() => _quoteMessage = m),
        ),
        DesktopMenuItem(
          label: '删除',
          icon: CupertinoIcons.delete,
          destructive: true,
          dividerBefore: true,
          onTap: () {
            context
                .read<ChatProvider>()
                .deleteMessage(widget.conversationId, m.id);
          },
        ),
      ],
    );
  }

  Widget _buildSidePanel(DesktopPalette p) {
    return Container(
      width: 360,
      decoration: BoxDecoration(
        color: p.panelBg,
        border: Border(left: BorderSide(color: p.border)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 52,
            child: Row(
              children: [
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    _panel == _DesktopChatPanel.settings ? '聊天设置' : '会话详情',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: p.textPrimary,
                    ),
                  ),
                ),
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  onPressed: () =>
                      setState(() => _panel = _DesktopChatPanel.none),
                  child: const Text('关闭'),
                ),
              ],
            ),
          ),
          Container(height: 1, color: p.divider),
          Expanded(
            child: _panel == _DesktopChatPanel.settings
                ? ChatSettingsScreen(conversationId: widget.conversationId)
                : ChatDetailScreen(
                    conversationId: widget.conversationId,
                    characterName: widget.characterName,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(DesktopPalette p) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: p.chatBg,
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Selector<ChatProvider, bool>(
              selector: (_, p0) => p0.isReplying(widget.conversationId),
              builder: (context, replying, _) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.characterName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: p.textPrimary,
                      ),
                    ),
                    if (replying)
                      Text(
                        '对方正在输入……',
                        style: TextStyle(
                          fontSize: 11,
                          color: p.textTertiary,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          _headerBtn(
            p,
            icon: CupertinoIcons.gear,
            label: '聊天设置',
            active: _panel == _DesktopChatPanel.settings,
            onTap: () => setState(() {
              _panel = _panel == _DesktopChatPanel.settings
                  ? _DesktopChatPanel.none
                  : _DesktopChatPanel.settings;
            }),
          ),
          _headerBtn(
            p,
            icon: CupertinoIcons.line_horizontal_3,
            label: '详情',
            active: _panel == _DesktopChatPanel.detail,
            onTap: () => setState(() {
              _panel = _panel == _DesktopChatPanel.detail
                  ? _DesktopChatPanel.none
                  : _DesktopChatPanel.detail;
            }),
          ),
        ],
      ),
    );
  }

  Widget _headerBtn(
    DesktopPalette p, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) {
    final color = active ? p.accent : p.textSecondary;
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      onPressed: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 13, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildInput(DesktopPalette p) {
    return Column(
      children: [
        if (_quoteMessage != null)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '引用：${_quoteMessage!.content}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: p.textSecondary,
                    ),
                  ),
                ),
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  onPressed: () => setState(() => _quoteMessage = null),
                  child: const Text('取消'),
                ),
              ],
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: p.inputBarBg,
            border: Border(top: BorderSide(color: p.border)),
          ),
          child: Consumer2<ChatSettingsProvider, ChatProvider>(
            builder: (context, settings, chat, _) {
              return MessageInput(
                key: _inputKey,
                enterToSend: true,
                onSend: (text) async {
                  final quote = _quoteMessage;
                  await context.read<ChatProvider>().sendMessage(
                        conversationId: widget.conversationId,
                        content: text,
                        quoteContent: quote?.content ?? '',
                        quoteSender: quote == null
                            ? ''
                            : (quote.isFromUser
                                ? '我'
                                : widget.characterName),
                      );
                  setState(() => _quoteMessage = null);
                  _scrollToBottom();
                },
                onPickImage: _handlePickImage,
                onPickFile: _handlePickFile,
                onStickerSelected: _handleSticker,
                onSettings: () => setState(
                  () => _panel = _DesktopChatPanel.settings,
                ),
                showStickerButton: settings.showStickerButton,
                onRequestReply: _requestReply,
                replyEnabled: chat
                        .getMessages(widget.conversationId)
                        .lastOrNull
                        ?.isFromUser ??
                    true,
                isRoleplayMode: settings.isRoleplayMode,
                roleplayChoices: settings.enableRoleplayChoices
                    ? chat.roleplayChoicesFor(widget.conversationId)
                    : const [],
                onRoleplayChoice: (text) =>
                    _inputKey.currentState?.setText(text),
                onRoleplayNarration:
                    settings.isRoleplayMode ? _promptNarration : null,
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _promptNarration() async {
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
            maxLines: 6,
            minLines: 3,
            placeholder: '描述你的行动或故事发展',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('确定'),
            onPressed: () => Navigator.pop(ctx, controller.text),
          ),
        ],
      ),
    );
    if (content == null || content.trim().isEmpty || !mounted) return;
    await context.read<ChatProvider>().addRoleplayNarration(
          conversationId: widget.conversationId,
          content: content.trim(),
        );
    _scrollToBottom();
  }
}

/// 桌面端触发角色回复（复用与手机端一致的 Prompt/模型参数组装）。
class DesktopChatReply {
  static Future<void> trigger({
    required BuildContext context,
    required String conversationId,
    required String fallbackName,
    bool replyToUser = false,
    String? imagePath,
    String? stickerLabel,
  }) async {
    final chatSettings = context.read<ChatSettingsProvider>();
    final model =
        context.read<ApiProvider>().getModelById(chatSettings.selectedModelId);
    if (model == null) {
      await showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('无法回复'),
          content: const Text('请先在「API 设置」中配置模型'),
          actions: [
            CupertinoDialogAction(
              child: const Text('确定'),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      );
      return;
    }

    final chatProvider = context.read<ChatProvider>();
    final conversation = chatProvider.conversations
        .where((c) => c.id == conversationId)
        .firstOrNull;
    final character = conversation != null
        ? context
            .read<CharacterProvider>()
            .getCharacterById(conversation.characterId)
        : null;
    final isRoleplayMode = chatSettings.isRoleplayMode;
    final characterName = isRoleplayMode
        ? (character?.name.trim().isNotEmpty == true
            ? character!.name.trim()
            : fallbackName)
        : character?.displayName ?? fallbackName;

    final memoryPoints = conversation != null
        ? context
            .read<MemoryPointProvider>()
            .pointsFor(conversation.characterId)
            .map((p) => p.content)
            .toList()
        : const <String>[];

    final memoryPool = !isRoleplayMode && character != null
        ? MemoryPoolBuilder.build(
            character: character,
            chatProvider: chatProvider,
            groupChatProvider: context.read<GroupChatProvider>(),
            chatSettings: chatSettings,
            user: context.read<AuthProvider>().user,
            includePrivateHistory: false,
          )
        : '';

    final api = context.read<ApiProvider>();
    final compressModel = api.getModelById(api.compressionModelId) ?? model;
    final isVisionSupported = api.isVisionSupported(model.id) == true;
    final modelImagePath =
        stickerLabel == null || isVisionSupported ? imagePath : null;

    try {
      if (isRoleplayMode && chatSettings.enableRoleplayStream) {
        await chatProvider.runRoleplayStream(
          conversationId: conversationId,
          model: model,
          characterName: characterName,
          characterSystemPrompt: character?.systemPrompt ?? '',
          userRelationship: character?.userRelationship ?? '',
          userNickname: context.read<AuthProvider>().user?.nickname ?? '用户',
          memoryPoints: memoryPoints,
          contextCount: chatSettings.contextCount,
          progressionStyle: chatSettings.roleplayProgressionStyle.name,
          includeChoices: chatSettings.enableRoleplayChoices,
        );
      } else {
        await chatProvider.runProactiveReply(
          conversationId: conversationId,
          model: model,
          characterName: characterName,
          characterSystemPrompt: character?.systemPrompt ?? '',
          userRelationship: character?.userRelationship ?? '',
          userNickname: context.read<AuthProvider>().user?.nickname ?? '用户',
          replyToUser: replyToUser,
          contextCount: chatSettings.contextCount,
          enableCompression: chatSettings.enableCompression,
          compressModel: compressModel,
          contextLength: model.contextLength,
          compressThreshold: chatSettings.compressThreshold,
          imagePath: modelImagePath,
          activeStart: character?.activeStart ?? '',
          activeEnd: character?.activeEnd ?? '',
          memoryPoints: memoryPoints,
          extraSystemContext: memoryPool,
          roleplayMode: isRoleplayMode,
          roleplayProgressionStyle:
              chatSettings.roleplayProgressionStyle.name,
          findSticker: context.read<SettingsProvider>().allowStickerSend
              ? (query) =>
                  context.read<StickerProvider>().pickStickerForRole(query)
              : null,
        );
      }
    } catch (e) {
      debugPrint('[DesktopChat] reply failed: $e');
    }
  }
}
