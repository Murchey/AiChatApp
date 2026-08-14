import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/character.dart';
import '../providers/character_provider.dart';
import '../providers/group_chat_provider.dart';
import '../providers/memory_point_provider.dart';
import '../widgets/character_avatar.dart';
import 'memory_point_manage_screen.dart';

/// 群聊详情 → 【持久化记忆点存储】二级页：
/// 列出群内各角色及其记忆点数量，点击进入该角色的记忆点管理页
/// （复用私聊的 MemoryPointManageScreen：编辑 / 添加 / 删除）。
/// 群聊中长按消息 → 「保存为记忆点」会自动存入对应角色。
class GroupMemberMemoryScreen extends StatefulWidget {
  final String groupId;

  const GroupMemberMemoryScreen({super.key, required this.groupId});

  @override
  State<GroupMemberMemoryScreen> createState() => _GroupMemberMemoryScreenState();
}

class _GroupMemberMemoryScreenState extends State<GroupMemberMemoryScreen> {
  @override
  Widget build(BuildContext context) {
    final group =
        context.watch<GroupChatProvider>().getGroupById(widget.groupId);
    if (group == null) {
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('持久化记忆点存储')),
        child: Center(
          child: Text(
            '群聊不存在或已删除',
            style: TextStyle(color: context.textSecondaryColor),
          ),
        ),
      );
    }
    final charProvider = context.watch<CharacterProvider>();
    final memoryProvider = context.watch<MemoryPointProvider>();
    final members = <Character>[
      for (final id in group.memberCharacterIds)
        if (charProvider.getCharacterById(id) != null)
          charProvider.getCharacterById(id)!,
    ];

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('持久化记忆点存储'),
      ),
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
                      '群聊中长按消息 → 「保存为记忆点」：\n'
                      '角色消息存入该角色自己的记忆，用户消息存入群内所有角色。\n'
                      '记忆点会进入模型请求上下文，点击成员可查看 / 编辑 / 删除。',
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
                          '${memoryProvider.pointsFor(c.id).length} 条记忆点',
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
                              builder: (_) => MemoryPointManageScreen(
                                characterId: c.id,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
