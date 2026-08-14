import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/group_chat.dart';
import '../providers/auth_provider.dart';
import '../providers/character_provider.dart';
import '../providers/group_chat_provider.dart';
import '../widgets/character_avatar.dart';
import 'group_chat_settings_screen.dart';
import 'group_member_memory_screen.dart';
import 'group_member_model_screen.dart';

/// 群聊详情：修改群名、查看成员、添加成员、移除成员、删除群聊。
class GroupChatDetailScreen extends StatefulWidget {
  final String groupId;

  const GroupChatDetailScreen({super.key, required this.groupId});

  @override
  State<GroupChatDetailScreen> createState() => _GroupChatDetailScreenState();
}

class _GroupChatDetailScreenState extends State<GroupChatDetailScreen> {
  Future<void> _rename(GroupChat group) async {
    final controller = TextEditingController(text: group.name);
    final newName = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('修改群名'),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: CupertinoTextField(
            controller: controller,
            autofocus: true,
            maxLength: 20,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            placeholder: '群聊名称',
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
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || !mounted) return;
    context.read<GroupChatProvider>().updateGroupName(widget.groupId, newName);
  }

  /// 从相册选择图片并更新群头像
  Future<void> _changeAvatar() async {
    final groupProvider = context.read<GroupChatProvider>();
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 500,
      maxHeight: 500,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    await groupProvider.updateGroupAvatar(widget.groupId, base64Encode(bytes));
    if (!mounted) return;
    _showInfo('群头像已更新');
  }

  /// 编辑群简介（简介会进入模型请求上下文，角色按简介语境对话）
  Future<void> _editDescription(GroupChat group) async {
    final controller = TextEditingController(text: group.description);
    final result = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('群聊简介'),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: CupertinoTextField(
            controller: controller,
            maxLines: 4,
            minLines: 2,
            maxLength: 120,
            padding: const EdgeInsets.all(10),
            placeholder: '例如：兴趣小组，群主请多照顾新成员',
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
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    await context
        .read<GroupChatProvider>()
        .updateGroupDescription(widget.groupId, result);
  }

  Future<void> _addMembers(GroupChat group) async {
    final charProvider = context.read<CharacterProvider>();
    final candidates = charProvider.manageableCharacters
        .where((c) => !group.memberCharacterIds.contains(c.id))
        .toList();
    if (candidates.isEmpty) {
      _showInfo('暂无可添加的角色');
      return;
    }

    final selected = <String>{};
    await showCupertinoModalPopup(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.6,
            ),
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Row(
                      children: [
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            '添加成员',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: context.textPrimaryColor,
                            ),
                          ),
                        ),
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('完成'),
                        ),
                      ],
                    ),
                  ),
                  Container(height: 0.5, color: context.separatorColor),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: candidates.length,
                      itemBuilder: (context, index) {
                        final c = candidates[index];
                        final isSelected = selected.contains(c.id);
                        return CupertinoListTile(
                          leading: CharacterAvatar(
                            base64: c.avatar,
                            size: 40,
                          ),
                          title: Text(
                            c.displayName,
                            style: TextStyle(
                              fontSize: 16,
                              color: context.textPrimaryColor,
                            ),
                          ),
                          trailing: Icon(
                            isSelected
                                ? CupertinoIcons.check_mark_circled_solid
                                : CupertinoIcons.circle,
                            color: isSelected
                                ? context.accentColor
                                : context.textSecondaryColor.withValues(
                                    alpha: 0.5,
                                  ),
                          ),
                          onTap: () {
                            setModalState(() {
                              if (!selected.remove(c.id)) {
                                selected.add(c.id);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (!mounted || selected.isEmpty) return;
    final selectedIds = selected.toList();
    // 选中角色 id 对应的显示名，供生成「XX 加入了群聊」事件气泡
    final nameById = {for (final c in candidates) c.id: c.displayName};
    context.read<GroupChatProvider>().addMembers(
          widget.groupId,
          selectedIds,
          names: [for (final id in selectedIds) nameById[id] ?? ''],
        );
  }

  Future<void> _removeMember(String characterId) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('移除成员'),
        content: const Text('将该角色移出群聊？其历史发言会保留在群内。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    // 角色显示名，供生成「XX 已被移出群聊」事件气泡
    final name = context
            .read<CharacterProvider>()
            .getCharacterById(characterId)
            ?.displayName ??
        '';
    context
        .read<GroupChatProvider>()
        .removeMembers(widget.groupId, [characterId], names: [name]);
  }

  Future<void> _deleteGroup() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('删除群聊'),
        content: const Text('删除后该群聊将从会话列表移除，全部群聊消息一并删除，且无法恢复。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
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
    context.read<GroupChatProvider>().deleteGroup(widget.groupId);
    Navigator.of(context).popUntil((route) => route.isFirst);
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

  @override
  Widget build(BuildContext context) {
    final group = context.watch<GroupChatProvider>().getGroupById(widget.groupId);
    if (group == null) {
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('群聊详情')),
        child: Center(
          child: Text(
            '群聊不存在或已删除',
            style: TextStyle(color: context.textSecondaryColor),
          ),
        ),
      );
    }

    final charProvider = context.watch<CharacterProvider>();
    final user = context.read<AuthProvider>().user;

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('群聊详情')),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          // 群名
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                CupertinoListTile(
                  leading: Icon(
                    CupertinoIcons.person_3,
                    color: context.textPrimaryColor,
                  ),
                  title: Text(
                    '群聊名称',
                    style: TextStyle(color: context.textPrimaryColor),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 140),
                        child: Text(
                          '${group.name}（${group.memberCount}）',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: context.textSecondaryColor,
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
                  onTap: () => _rename(group),
                ),
                Container(height: 0.5, color: context.separatorColor),
                // 群头像（点击更换）
                CupertinoListTile(
                  leading: const Icon(
                    CupertinoIcons.photo,
                    color: CupertinoColors.systemBlue,
                  ),
                  title: Text(
                    '群聊头像',
                    style: TextStyle(color: context.textPrimaryColor),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CharacterAvatar(
                            base64: group.avatar,
                            size: 36,
                            borderRadius: BorderRadius.circular(8),
                            fallbackIcon: CupertinoIcons.person_3_fill,
                            iconSize: 18,
                          ),
                          Positioned(
                            right: -3,
                            bottom: -3,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: context.accentColor,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: context.listBgColor,
                                  width: 1.2,
                                ),
                              ),
                              child: const Icon(
                                CupertinoIcons.camera_fill,
                                size: 8,
                                color: CupertinoColors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        CupertinoIcons.chevron_right,
                        size: 14,
                        color: context.textSecondaryColor,
                      ),
                    ],
                  ),
                  onTap: _changeAvatar,
                ),
                Container(height: 0.5, color: context.separatorColor),
                // 群简介（进入模型请求上下文）
                CupertinoListTile(
                  leading: const Icon(
                    CupertinoIcons.doc_text,
                    color: CupertinoColors.systemOrange,
                  ),
                  title: Text(
                    '群聊简介',
                    style: TextStyle(color: context.textPrimaryColor),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 140),
                        child: Text(
                          group.description.isEmpty ? '未设置' : group.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: group.description.isEmpty
                                ? context.textSecondaryColor
                                    .withValues(alpha: 0.6)
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
                  onTap: () => _editDescription(group),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 成员
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                CupertinoListTile(
                  leading: Icon(
                    CupertinoIcons.person_add,
                    color: context.accentColor,
                  ),
                  title: Text(
                    '添加成员',
                    style: TextStyle(color: context.accentColor),
                  ),
                  onTap: () => _addMembers(group),
                ),
                Container(height: 0.5, color: context.separatorColor),
                // 用户本人（隐性成员，不可移除）
                CupertinoListTile(
                  leading: CharacterAvatar(
                    base64: user?.avatar ?? '',
                    size: 40,
                  ),
                  title: Text(
                    user?.nickname ?? '我',
                    style: TextStyle(
                      fontSize: 16,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  trailing: Text(
                    '群主',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondaryColor,
                    ),
                  ),
                ),
                for (final id in group.memberCharacterIds)
                  Builder(
                    builder: (context) {
                      final c = charProvider.getCharacterById(id);
                      final name = c?.displayName ?? '已删除角色';
                      return Column(
                        children: [
                          Container(
                            height: 0.5,
                            margin: const EdgeInsets.only(left: 56),
                            color: context.separatorColor,
                          ),
                          CupertinoListTile(
                            leading: CharacterAvatar(
                              base64: c?.avatar ?? '',
                              size: 40,
                            ),
                            title: Text(
                              name,
                              style: TextStyle(
                                fontSize: 16,
                                color: context.textPrimaryColor,
                              ),
                            ),
                            trailing: CupertinoButton(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              onPressed: () => _removeMember(id),
                              child: const Text(
                                '移除',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: CupertinoColors.systemRed,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 成员设置（缺省模型 / 持久化记忆点）
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                CupertinoListTile(
                  leading: const Icon(
                    CupertinoIcons.gear_alt,
                    color: CupertinoColors.systemBlue,
                  ),
                  title: Text(
                    '缺省模型设置',
                    style: TextStyle(color: context.textPrimaryColor),
                  ),
                  subtitle: Text(
                    '为群内角色配置模型，全局模型未设置时用缺省模型兜底',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondaryColor,
                    ),
                  ),
                  trailing: Icon(
                    CupertinoIcons.chevron_right,
                    size: 14,
                    color: context.textSecondaryColor,
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      CupertinoPageRoute(
                        builder: (_) => GroupMemberModelScreen(
                          groupId: widget.groupId,
                        ),
                      ),
                    );
                  },
                ),
                Container(height: 0.5, color: context.separatorColor),
                CupertinoListTile(
                  leading: const Icon(
                    CupertinoIcons.bookmark,
                    color: CupertinoColors.systemOrange,
                  ),
                  title: Text(
                    '持久化记忆点存储',
                    style: TextStyle(color: context.textPrimaryColor),
                  ),
                  subtitle: Text(
                    '管理群内各角色的长期记忆点',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondaryColor,
                    ),
                  ),
                  trailing: Icon(
                    CupertinoIcons.chevron_right,
                    size: 14,
                    color: context.textSecondaryColor,
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      CupertinoPageRoute(
                        builder: (_) => GroupMemberMemoryScreen(
                          groupId: widget.groupId,
                        ),
                      ),
                    );
                  },
                ),
                Container(height: 0.5, color: context.separatorColor),
                CupertinoListTile(
                  leading: const Icon(
                    CupertinoIcons.slider_horizontal_3,
                    color: CupertinoColors.systemGreen,
                  ),
                  title: Text(
                    '上下文设置',
                    style: TextStyle(color: context.textPrimaryColor),
                  ),
                  subtitle: Text(
                    '设置群聊回复携带的上下文条数，可跟随全局或单独设置',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondaryColor,
                    ),
                  ),
                  trailing: Icon(
                    CupertinoIcons.chevron_right,
                    size: 14,
                    color: context.textSecondaryColor,
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      CupertinoPageRoute(
                        builder: (_) => GroupChatSettingsScreen(
                          groupId: widget.groupId,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // 删除群聊
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: CupertinoListTile(
              leading: const Icon(
                CupertinoIcons.trash,
                color: CupertinoColors.systemRed,
              ),
              title: const Text(
                '删除群聊',
                style: TextStyle(color: CupertinoColors.systemRed),
              ),
              subtitle: Text(
                '从首页会话列表移除该群聊，并删除全部群聊消息，此操作不可恢复',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: context.textSecondaryColor,
                ),
              ),
              onTap: _deleteGroup,
            ),
          ),
        ],
      ),
    );
  }
}
