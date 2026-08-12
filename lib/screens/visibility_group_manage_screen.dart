import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/visibility_group.dart';
import '../providers/character_provider.dart';
import '../widgets/character_avatar.dart';

/// 分组管理页：编辑联系人（勾选 / 取消角色）+ 删除分组。
///
/// 列表展示全部可管理角色（不含"自己"），勾选即为加入分组的联系人；
/// 底部左侧【删除分组】（确认后删除并返回上一页）、右侧【保存】写入分组。
class VisibilityGroupManageScreen extends StatefulWidget {
  final VisibilityGroup group;

  const VisibilityGroupManageScreen({super.key, required this.group});

  @override
  State<VisibilityGroupManageScreen> createState() =>
      _VisibilityGroupManageScreenState();
}

class _VisibilityGroupManageScreenState extends State<VisibilityGroupManageScreen> {
  late final Set<String> _selected = widget.group.memberIds.toSet();

  Future<void> _save() async {
    await context.read<CharacterProvider>().updateVisibilityGroup(
          widget.group.copyWith(memberIds: _selected.toList()),
        );
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _deleteGroup() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('删除分组'),
        content: Text('确定删除分组「${widget.group.name}」吗？'),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(ctx, false),
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
    await context
        .read<CharacterProvider>()
        .removeVisibilityGroup(widget.group.id);
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final characters = context.watch<CharacterProvider>().manageableCharacters;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.group.name),
      ),
      child: Column(
        children: [
          Expanded(
            child: characters.isEmpty
                ? Center(
                    child: Text(
                      '暂无角色可加入分组',
                      style: TextStyle(color: context.textSecondaryColor),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: characters.length,
                    separatorBuilder: (context, index) => Container(
                      height: 0.5,
                      margin: const EdgeInsets.only(left: 68),
                      color: context.separatorColor,
                    ),
                    itemBuilder: (context, index) {
                      final c = characters[index];
                      final isSelected = _selected.contains(c.id);
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selected.remove(c.id);
                            } else {
                              _selected.add(c.id);
                            }
                          });
                        },
                        child: Container(
                          color: context.listBgColor,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              CharacterAvatar(base64: c.avatar, size: 40),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  c.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: context.textPrimaryColor,
                                  ),
                                ),
                              ),
                              Icon(
                                isSelected
                                    ? CupertinoIcons.checkmark_circle_fill
                                    : CupertinoIcons.circle,
                                size: 24,
                                color: isSelected
                                    ? context.accentColor
                                    : CupertinoColors.systemGrey,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          // 底部操作栏：删除分组 / 保存
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      color: context.listBgColor,
                      borderRadius: BorderRadius.circular(10),
                      onPressed: _deleteGroup,
                      child: const Text(
                        '删除分组',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: CupertinoColors.systemRed,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CupertinoButton.filled(
                      onPressed: _save,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: const Text(
                        '保存',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
