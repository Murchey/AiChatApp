import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/character_provider.dart';
import '../providers/group_chat_provider.dart';
import '../widgets/character_avatar.dart';
import 'group_chat_screen.dart';

/// 创建群聊：输入群名 + 多选角色成员（用户恒为群成员）。
///
/// [initialMemberIds] 用于从某个角色会话的「组建群聊」进入时预选该角色。
/// 创建成功后替换本页为群聊会话页，返回时回到进入前的页面。
class CreateGroupScreen extends StatefulWidget {
  final List<String> initialMemberIds;

  const CreateGroupScreen({super.key, this.initialMemberIds = const []});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final TextEditingController _nameController = TextEditingController();
  late final Set<String> _selected = {...widget.initialMemberIds};

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _canCreate =>
      _nameController.text.trim().isNotEmpty && _selected.length >= 2;

  Future<void> _create() async {
    if (!_canCreate) return;
    final group = context.read<GroupChatProvider>().createGroup(
          name: _nameController.text.trim(),
          memberCharacterIds: _selected.toList(),
        );
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      CupertinoPageRoute(builder: (_) => GroupChatScreen(groupId: group.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final characters = context
        .watch<CharacterProvider>()
        .manageableCharacters;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('创建群聊'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _canCreate ? _create : null,
          child: Text(
            '创建',
            style: TextStyle(
              color: _canCreate
                  ? context.accentColor
                  : context.textSecondaryColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      child: Column(
        children: [
          // 群名输入
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: CupertinoTextField(
              controller: _nameController,
              placeholder: '填写群聊名称',
              maxLength: 20,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: const BoxDecoration(),
              style: TextStyle(fontSize: 16, color: context.textPrimaryColor),
              onChanged: (_) => setState(() {}),
            ),
          ),
          // 成员选择标题
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Row(
              children: [
                Text(
                  '选择群成员',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimaryColor,
                  ),
                ),
                const Spacer(),
                Text(
                  '已选 ${_selected.length} 人（含用户共 ${_selected.length + 1} 人）',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondaryColor,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              '提示：目前暂时不建议超过 5 人群，对模型性能要求过高',
              style: TextStyle(
                fontSize: 12,
                color: context.textSecondaryColor,
              ),
            ),
          ),
          Expanded(
            child: Container(
              color: context.scaffoldColor,
              child: ListView.builder(
                itemCount: characters.length,
                itemBuilder: (context, index) {
                  final c = characters[index];
                  final selected = _selected.contains(c.id);
                  return CupertinoListTile(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leadingSize: 44,
                    leading: CharacterAvatar(base64: c.avatar, size: 44),
                    title: Text(
                      c.displayName,
                      style: TextStyle(
                        fontSize: 16,
                        color: context.textPrimaryColor,
                      ),
                    ),
                    trailing: Icon(
                      selected
                          ? CupertinoIcons.check_mark_circled_solid
                          : CupertinoIcons.circle,
                      color: selected
                          ? context.accentColor
                          : context.textSecondaryColor.withValues(alpha: 0.5),
                    ),
                    onTap: () {
                      setState(() {
                        if (!_selected.remove(c.id)) {
                          _selected.add(c.id);
                        }
                      });
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
