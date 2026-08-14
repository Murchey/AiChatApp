import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/character.dart';
import '../providers/api_provider.dart';
import '../providers/character_provider.dart';
import '../providers/group_chat_provider.dart';
import '../widgets/character_avatar.dart';

/// 群聊详情 → 【缺省模型设置】二级页：
/// 为群内每个角色配置模型。模型解析顺序：
/// 角色指定模型 → 缺省模型（全局聊天模型未配置时的兜底）→ 全局聊天模型。
class GroupMemberModelScreen extends StatefulWidget {
  final String groupId;

  const GroupMemberModelScreen({super.key, required this.groupId});

  @override
  State<GroupMemberModelScreen> createState() => _GroupMemberModelScreenState();
}

class _GroupMemberModelScreenState extends State<GroupMemberModelScreen> {
  /// 弹出单个角色的模型选择面板（与私聊会话详情一致的三档结构）
  void _showModelPicker(Character character) {
    final api = context.read<ApiProvider>();
    final currentId = character.modelId;
    final defaultId = character.defaultModelId;

    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        decoration: BoxDecoration(
          color: context.listBgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Text(
                  '设置「${character.displayName}」的模型',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    CupertinoListTile(
                      leading: Icon(
                        currentId.isEmpty && defaultId.isEmpty
                            ? CupertinoIcons.check_mark_circled_solid
                            : CupertinoIcons.circle,
                        color: currentId.isEmpty && defaultId.isEmpty
                            ? context.accentColor
                            : context.textSecondaryColor,
                      ),
                      title: const Text('跟随全局模型'),
                      subtitle: Text(
                        '使用「聊天设置」中选中的全局聊天模型',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondaryColor,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        final provider = context.read<CharacterProvider>();
                        provider.updateCharacterModel(character.id, '');
                        provider.updateCharacterDefaultModel(character.id, '');
                      },
                    ),
                    _sectionLabel('缺省模型（全局模型未设置时的兜底）'),
                    for (final m in api.models)
                      CupertinoListTile(
                        leading: Icon(
                          currentId.isEmpty && m.id == defaultId
                              ? CupertinoIcons.check_mark_circled_solid
                              : CupertinoIcons.circle,
                          color: currentId.isEmpty && m.id == defaultId
                              ? context.accentColor
                              : context.textSecondaryColor,
                        ),
                        title: Text(m.displayName),
                        subtitle: Text(
                          m.modelName,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondaryColor,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          final provider = context.read<CharacterProvider>();
                          provider.updateCharacterDefaultModel(
                            character.id,
                            m.id,
                          );
                          provider.updateCharacterModel(character.id, '');
                        },
                      ),
                    _sectionLabel('指定模型（始终使用该模型）'),
                    for (final m in api.models)
                      CupertinoListTile(
                        leading: Icon(
                          m.id == currentId
                              ? CupertinoIcons.check_mark_circled_solid
                              : CupertinoIcons.circle,
                          color: m.id == currentId
                              ? context.accentColor
                              : context.textSecondaryColor,
                        ),
                        title: Text(m.displayName),
                        subtitle: Text(
                          m.modelName,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondaryColor,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          final provider = context.read<CharacterProvider>();
                          provider.updateCharacterModel(character.id, m.id);
                          provider.updateCharacterDefaultModel(character.id, '');
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

  Widget _sectionLabel(String text) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: context.textSecondaryColor),
      ),
    );
  }

  String _modelLabel(Character c, ApiProvider api) {
    if (c.modelId.isNotEmpty) {
      final m = api.getModelById(c.modelId);
      return '指定模型：${m?.displayName ?? c.modelId}';
    }
    if (c.defaultModelId.isNotEmpty) {
      final m = api.getModelById(c.defaultModelId);
      return '缺省模型：${m?.displayName ?? c.defaultModelId}';
    }
    return '跟随全局模型';
  }

  @override
  Widget build(BuildContext context) {
    final group =
        context.watch<GroupChatProvider>().getGroupById(widget.groupId);
    if (group == null) {
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('缺省模型设置')),
        child: Center(
          child: Text(
            '群聊不存在或已删除',
            style: TextStyle(color: context.textSecondaryColor),
          ),
        ),
      );
    }
    final charProvider = context.watch<CharacterProvider>();
    final api = context.read<ApiProvider>();
    final members = <Character>[
      for (final id in group.memberCharacterIds)
        if (charProvider.getCharacterById(id) != null)
          charProvider.getCharacterById(id)!,
    ];

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('缺省模型设置')),
      child: members.isEmpty
          ? ColoredBox(
              color: context.scaffoldColor,
              child: Center(
                child: Text(
                  '群内没有角色成员',
                  style: TextStyle(color: context.textSecondaryColor),
                ),
              ),
            )
          : ColoredBox(
              color: context.scaffoldColor,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                    child: Text(
                      '模型解析顺序：角色指定模型 → 缺省模型（全局未设置时兜底）→ 全局聊天模型。\n'
                      '群聊回复时，未单独指定模型的角色也会用「缺省模型」应答，不会因无模型而沉默。',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: context.textSecondaryColor,
                      ),
                    ),
                  ),
                  for (final c in members)
                    Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: context.listBgColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: CupertinoListTile(
                        leading: CharacterAvatar(
                          base64: c.avatar,
                          size: 40,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        title: Text(
                          c.displayName,
                          style: TextStyle(
                            fontSize: 16,
                            color: context.textPrimaryColor,
                          ),
                        ),
                        subtitle: Text(
                          _modelLabel(c, api),
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
                        onTap: () => _showModelPicker(c),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
