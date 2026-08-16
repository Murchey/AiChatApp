import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/visibility_group.dart';
import '../providers/character_provider.dart';
import 'visibility_group_manage_screen.dart';

/// 选择朋友圈展示范围（发布页底部入口进入）：
/// 固定选项【仅自己可见】【全部角色可见】+ 自定义分组列表。
///
/// 点击固定选项 / 分组右侧圆点即选中并 `Navigator.pop` 返回范围 id；
/// 点击分组行进入其管理页（编辑联系人 / 删除分组）；
/// 底部【添加分组】创建新分组，创建后自动出现在列表中。
class MomentVisibilityScreen extends StatefulWidget {
  final String selectedId;

  const MomentVisibilityScreen({
    super.key,
    required this.selectedId,
  });

  @override
  State<MomentVisibilityScreen> createState() =>
      _MomentVisibilityScreenState();
}

class _MomentVisibilityScreenState extends State<MomentVisibilityScreen> {
  late final String _selectedId = widget.selectedId;

  Future<void> _addGroup() async {
    final controller = TextEditingController();
    final name = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('添加分组'),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: CupertinoTextField(
            controller: controller,
            autofocus: true,
            maxLength: 20,
            placeholder: '输入分组名称',
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    await context.read<CharacterProvider>().addVisibilityGroup(name);
  }

  /// 进入分组管理页；返回后刷新列表（分组可能被删除/联系人变化）
  Future<void> _openManage(VisibilityGroup group) async {
    await Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => VisibilityGroupManageScreen(group: group),
      ),
    );
    if (!mounted) return;
    setState(() {});
  }

  void _select(String id) {
    Navigator.pop(context, id);
  }

  Widget _divider() {
    return Container(
      height: 0.5,
      margin: const EdgeInsets.only(left: 16),
      color: context.separatorColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CharacterProvider>();
    final groups = provider.visibilityGroups;
    final characters = provider.characters;
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('选择展示范围'),
      ),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // 固定选项：仅自己可见 / 全部角色可见
                _buildFixedOption(
                  id: VisibilityScope.onlyMe,
                  icon: CupertinoIcons.lock_fill,
                  title: '仅自己可见',
                ),
                _divider(),
                _buildFixedOption(
                  id: VisibilityScope.all,
                  icon: CupertinoIcons.person_2_fill,
                  title: '全部角色可见',
                ),
                if (groups.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '自定义分组',
                          style: TextStyle(
                            fontSize: 13,
                            color: context.textSecondaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...groups.map((g) {
                    // 联系人数量按当前仍存在的角色统计
                    final memberCount = g.memberIds
                        .where((id) => characters.any((c) => c.id == id))
                        .length;
                    final isSelected = _selectedId == g.id;
                    return Container(
                      color: context.listBgColor,
                      padding: const EdgeInsets.only(
                        left: 16,
                        right: 8,
                        top: 10,
                        bottom: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.person_3_fill,
                            size: 20,
                            color: context.accentColor,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            // 点击分组行：进入管理页
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _openManage(g),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      g.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: context.textPrimaryColor,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$memberCount 位联系人',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: context.textSecondaryColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // 选中圆点：点击即选中该分组为展示范围
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _select(g.id),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Icon(
                                isSelected
                                    ? CupertinoIcons.checkmark_circle_fill
                                    : CupertinoIcons.circle,
                                size: 22,
                                color: isSelected
                                    ? context.accentColor
                                    : CupertinoColors.systemGrey,
                              ),
                            ),
                          ),
                            Icon(
                              CupertinoIcons.chevron_right,
                              size: 16,
                              color: context.textSecondaryColor,
                            ),
                          ],
                        ),
                      );
                  }),
                ],
              ],
            ),
          ),
          // 底部：添加分组
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: CupertinoButton.filled(
                onPressed: _addGroup,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                child: const Text(
                  '添加分组',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 固定选项行：点击整行即选中并返回
  Widget _buildFixedOption({
    required String id,
    required IconData icon,
    required String title,
  }) {
    final isSelected = _selectedId == id;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _select(id),
      child: Container(
        color: context.listBgColor,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: context.accentColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
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
  }
}
