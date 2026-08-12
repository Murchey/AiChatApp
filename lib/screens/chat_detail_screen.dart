import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/character.dart';
import '../models/conversation.dart';
import '../providers/chat_provider.dart';
import '../providers/character_provider.dart';
import '../services/prompt_builder.dart';
import '../widgets/character_avatar.dart';
import 'character_detail_screen.dart';

/// 聊天详情/角色资料：上半部分可编辑角色卡（备注/昵称/个性签名/定位地区），
/// 中部聊天管理（聊天场景），最下方折叠的提示词设置 panel。
///
/// 通过 [conversationId] 进入时为聊天详情页；通过 [characterId] 直接进入时
/// 为角色资料编辑页（如角色管理页），可设置 [showChatManage] 为 false 隐藏聊天管理区。
class ChatDetailScreen extends StatefulWidget {
  final String conversationId;
  final String characterName;

  /// 直接指定要编辑的角色（角色管理页使用，不再依赖会话）
  final String? characterId;

  /// 是否显示"清空上下文/删除聊天"管理区（仅聊天场景）
  final bool showChatManage;

  const ChatDetailScreen({
    super.key,
    required this.conversationId,
    required this.characterName,
    this.characterId,
    this.showChatManage = true,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  bool _promptExpanded = false;
  TextEditingController? _promptController;

  @override
  void dispose() {
    _promptController?.dispose();
    super.dispose();
  }

  String get _characterId {
    // 直接指定的角色优先（角色管理页场景）
    final direct = widget.characterId;
    if (direct != null && direct.isNotEmpty) return direct;
    return context
            .read<ChatProvider>()
            .conversations
            .where((c) => c.id == widget.conversationId)
            .firstOrNull
            ?.characterId ??
        '';
  }

  /// 保存角色资料字段，并同步备注/昵称变更到会话显示名（首页列表实时更新）。
  /// 文本输入会做防注入清理与长度限制。
  Future<void> _saveField({
    String? name,
    String? remark,
    String? signature,
    String? region,
    String? userRelationship,
  }) async {
    final charProvider = context.read<CharacterProvider>();
    final chatProvider = context.read<ChatProvider>();
    final characterId = _characterId;
    await charProvider.updateCharacterInfo(
      characterId,
      name: name,
      remark: remark,
      signature: signature,
      region: region,
      userRelationship: userRelationship == null
          ? null
          : PromptBuilder.sanitize(userRelationship),
    );
    final updated = charProvider.getCharacterById(characterId);
    if (updated != null) {
      chatProvider.updateCharacterDisplayName(characterId, updated.displayName);
    }
  }

  /// 选择相册图片并更新角色头像
  Future<void> _pickAvatar() async {
    final characterId = _characterId;
    if (characterId.isEmpty) return;
    final provider = context.read<CharacterProvider>();
    final chatProvider = context.read<ChatProvider>();
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 500,
      maxHeight: 500,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    await provider.updateAvatar(characterId, base64Encode(bytes));
    // 同步会话快照，首页消息列表头像实时更新
    chatProvider.updateCharacterAvatar(characterId, base64Encode(bytes));
    if (!mounted) return;
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('头像已更新'),
        content: const Text('新的角色头像已保存'),
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

  /// 弹出单字段编辑框
  void _editField({
    required String title,
    required String initial,
    required String hint,
    bool multiline = false,
    int? maxLength,
    required void Function(String value) onSave,
  }) {
    final controller = TextEditingController(text: initial);
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: multiline
              ? CupertinoTextField(
                  controller: controller,
                  maxLines: 4,
                  minLines: 2,
                  padding: const EdgeInsets.all(10),
                  placeholder: hint,
                  maxLength: maxLength,
                )
              : CupertinoTextField(
                  controller: controller,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  placeholder: hint,
                  maxLength: maxLength,
                ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              onSave(controller.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  /// 清空上下文：抹除全部记录，打开聊天不显示任何记录，AI 不继承上下文
  void _clearContext() {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('清空上下文'),
        content: const Text(
          '清空后该聊天的全部消息将被完全删除。再次打开时不会显示任何历史记录，AI 也不会继承此前的对话内容。',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(ctx);
              context
                  .read<ChatProvider>()
                  .clearMessages(widget.conversationId);
              Navigator.pop(context); // 返回聊天页，显示空状态
            },
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }

  /// 删除聊天：从首页移除该聊天，同时删除上下文
  void _deleteChat() {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('删除聊天'),
        content: const Text(
          '删除后该聊天将从首页会话列表中移除，聊天记录与上下文一并完全删除，且无法恢复。',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(ctx);
              context
                  .read<ChatProvider>()
                  .deleteConversation(widget.conversationId);
              // 返回首页
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _togglePrompt() {
    setState(() {
      _promptExpanded = !_promptExpanded;
      if (_promptExpanded && _promptController == null) {
        final character =
            context.read<CharacterProvider>().getCharacterById(_characterId);
        _promptController =
            TextEditingController(text: character?.systemPrompt ?? '');
      }
    });
  }

  Future<void> _savePrompt() async {
    await context
        .read<CharacterProvider>()
        .updateSystemPrompt(_characterId, _promptController?.text.trim() ?? '');
    if (!mounted) return;
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('保存成功'),
        content: const Text('角色的提示词已更新，新对话将使用该提示词。'),
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
    final chatProvider = context.watch<ChatProvider>();
    final conversation = widget.conversationId.isEmpty
        ? null
        : chatProvider.conversations
            .where((c) => c.id == widget.conversationId)
            .firstOrNull;

    final characterId = _characterId;
    final character = characterId.isNotEmpty
        ? context.watch<CharacterProvider>().getCharacterById(characterId)
        : null;

    final avatar = character?.avatar ?? conversation?.characterAvatar ?? '';
    final displayName = character?.displayName ?? widget.characterName;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: Text(displayName)),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          _buildCharacterCard(conversation, avatar, displayName),
          const SizedBox(height: 16),
          _buildInfoSection(character),
          if (widget.showChatManage && conversation != null) ...[
            const SizedBox(height: 24),
            _buildManageSection(),
          ],
          const SizedBox(height: 24),
          _buildPromptPanel(character),
        ],
      ),
    );
  }

  // ── 上半部分：角色卡 ──
  Widget _buildCharacterCard(
    Conversation? conversation,
    String avatar,
    String displayName,
  ) {
    final characterId = _characterId;
    final character = characterId.isNotEmpty
        ? context.read<CharacterProvider>().getCharacterById(characterId)
        : null;
    final signature = character?.signature ?? '';
    final region = character?.region ?? '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.listBgColor,
        borderRadius: BorderRadius.circular(14),
      ),
      // 点击角色栏目（头像除外）进入通讯录角色空间页
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openCharacterSpace,
        child: Row(
          children: [
            // 头像（点击更换，形状跟随全局设置）
            GestureDetector(
              onTap: _pickAvatar,
              child: Stack(
                children: [
                  CharacterAvatar(
                    base64: avatar,
                    size: 72,
                    borderRadius: BorderRadius.circular(12),
                    iconSize: 36,
                  ),
                  // 右下角相机角标
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: context.accentColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: context.listBgColor,
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        CupertinoIcons.camera_fill,
                        size: 10,
                        color: CupertinoColors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  if (signature.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      signature,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: context.textSecondaryColor,
                      ),
                    ),
                  ],
                  if (region.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          CupertinoIcons.location,
                          size: 13,
                          color: context.textSecondaryColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          region,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondaryColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_right,
              size: 18,
              color: context.textSecondaryColor,
            ),
          ],
        ),
      ),
    );
  }

  /// 进入通讯录角色空间页（角色详情：背景图 + 朋友圈）
  void _openCharacterSpace() {
    final characterId = _characterId;
    if (characterId.isEmpty) return;
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => CharacterDetailScreen(characterId: characterId),
      ),
    );
  }

  // ── 资料设置（类似微信联系人，点击条目编辑）──
  Widget _buildInfoSection(Character? character) {
    final name = character?.name ?? '';
    final remark = character?.remark ?? '';
    final signature = character?.signature ?? '';
    final region = character?.region ?? '';
    final userRelationship = character?.userRelationship ?? '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.listBgColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          _infoTile(
            icon: CupertinoIcons.person,
            label: '角色昵称',
            value: name,
            placeholder: '未设置',
            onTap: () => _editField(
              title: '角色昵称',
              initial: name,
              hint: '请输入角色昵称',
              onSave: (v) => _saveField(name: v),
            ),
          ),
          _separator(),
          _infoTile(
            icon: CupertinoIcons.tag,
            label: '角色备注',
            value: remark,
            placeholder: '未设置，默认显示昵称',
            onTap: () => _editField(
              title: '角色备注',
              initial: remark,
              hint: '设置后聊天列表将优先显示备注',
              onSave: (v) => _saveField(remark: v),
            ),
          ),
          _separator(),
          _infoTile(
            icon: CupertinoIcons.quote_bubble,
            label: '个性签名',
            value: signature,
            placeholder: '未设置',
            onTap: () => _editField(
              title: '个性签名',
              initial: signature,
              hint: '填写角色的个性签名',
              multiline: true,
              onSave: (v) => _saveField(signature: v),
            ),
          ),
          _separator(),
          _infoTile(
            icon: CupertinoIcons.location,
            label: '定位地区',
            value: region,
            placeholder: '未设置',
            onTap: () => _editField(
              title: '定位地区',
              initial: region,
              hint: '例如：中国 · 上海',
              onSave: (v) => _saveField(region: v),
            ),
          ),
          _separator(),
          _infoTile(
            icon: CupertinoIcons.person_2,
            label: '与我的关系',
            value: userRelationship,
            placeholder: '未设置',
            onTap: () => _editField(
              title: '与我的关系',
              initial: userRelationship,
              hint: '例如：青梅竹马 / 刚认识',
              maxLength: PromptBuilder.maxRelationshipLength,
              onSave: (v) => _saveField(userRelationship: v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoTile({
    required IconData icon,
    required String label,
    required String value,
    required String placeholder,
    required VoidCallback onTap,
  }) {
    return CupertinoListTile(
      leading: Icon(icon, color: context.textPrimaryColor),
      title: Text(
        label,
        style: TextStyle(color: context.textPrimaryColor),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              value.isEmpty ? placeholder : value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                color: value.isEmpty
                    ? context.textSecondaryColor.withValues(alpha: 0.6)
                    : context.textSecondaryColor,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            CupertinoIcons.chevron_right,
            size: 14,
            color: context.textSecondaryColor,
          ),
        ],
      ),
      onTap: onTap,
    );
  }

  // ── 聊天管理 ──
  Widget _buildManageSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.listBgColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          CupertinoListTile(
            leading: Icon(
              CupertinoIcons.clear_circled,
              color: context.textPrimaryColor,
            ),
            title: Text(
              '清空上下文',
              style: TextStyle(color: context.textPrimaryColor),
            ),
            subtitle: Text(
              '清除当前聊天的全部消息，再次打开时不会显示任何记录，AI 也不会继承此前的对话内容',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: context.textSecondaryColor,
              ),
            ),
            onTap: _clearContext,
          ),
          Container(
            height: 0.5,
            margin: const EdgeInsets.only(left: 16),
            color: context.separatorColor,
          ),
          CupertinoListTile(
            leading: const Icon(
              CupertinoIcons.trash,
              color: CupertinoColors.systemRed,
            ),
            title: const Text(
              '删除聊天',
              style: TextStyle(color: CupertinoColors.systemRed),
            ),
            subtitle: Text(
              '从首页会话列表中移除该聊天，同时删除全部聊天记录与上下文，此操作不可恢复',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: context.textSecondaryColor,
              ),
            ),
            onTap: _deleteChat,
          ),
        ],
      ),
    );
  }

  // ── 最下方：折叠的提示词设置 panel ──
  Widget _buildPromptPanel(Character? character) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.listBgColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          CupertinoListTile(
            leading: const Icon(CupertinoIcons.text_quote),
            title: Text(
              '提示词设置',
              style: TextStyle(color: context.textPrimaryColor),
            ),
            subtitle: Text(
              '定义角色对话时的行为与设定，点击展开编辑',
              style: TextStyle(
                fontSize: 12,
                color: context.textSecondaryColor,
              ),
            ),
            trailing: Icon(
              _promptExpanded
                  ? CupertinoIcons.chevron_up
                  : CupertinoIcons.chevron_down,
              size: 16,
              color: context.textSecondaryColor,
            ),
            onTap: _togglePrompt,
          ),
          if (_promptExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CupertinoTextField(
                    controller: _promptController,
                    maxLines: 6,
                    minLines: 3,
                    padding: const EdgeInsets.all(12),
                    placeholder: '输入角色的提示词…',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: context.textPrimaryColor,
                    ),
                    decoration: BoxDecoration(
                      color: context.fieldBgColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  CupertinoButton.filled(
                    onPressed: _savePrompt,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    borderRadius: BorderRadius.circular(10),
                    child: const Text('保存'),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '保存后新对话将使用新的提示词，已进行的对话不受影响',
                    textAlign: TextAlign.center,
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
    );
  }

  Widget _separator() {
    return Container(
      height: 0.5,
      margin: const EdgeInsets.only(left: 16),
      color: context.separatorColor,
    );
  }
}
