import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/memory_point_provider.dart';

/// 记忆点管理页：编辑 / 添加 / 删除某个角色的持久化记忆点。
/// 从会话详情「提示词设置 → 记忆点管理」进入。
class MemoryPointManageScreen extends StatefulWidget {
  final String characterId;

  const MemoryPointManageScreen({super.key, required this.characterId});

  @override
  State<MemoryPointManageScreen> createState() =>
      _MemoryPointManageScreenState();
}

class _MemoryPointManageScreenState extends State<MemoryPointManageScreen> {
  static final DateFormat _dateFmt = DateFormat('yyyy-MM-dd HH:mm');

  Future<void> _add() async {
    final content = await _showEditDialog(title: '添加记忆点');
    if (content == null || content.trim().isEmpty) return;
    if (!mounted) return;
    await context
        .read<MemoryPointProvider>()
        .addPoints(widget.characterId, [content]);
  }

  Future<void> _edit(String pointId, String oldContent) async {
    final content =
        await _showEditDialog(title: '编辑记忆点', initial: oldContent);
    if (content == null || !mounted) return;
    await context
        .read<MemoryPointProvider>()
        .updatePoint(widget.characterId, pointId, content);
  }

  Future<void> _delete(String pointId, String content) async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('删除记忆点'),
        content: Text('确定删除这条记忆点吗？\n"${_shorten(content)}"'),
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
    if (confirm != true || !mounted) return;
    await context
        .read<MemoryPointProvider>()
        .removePoint(widget.characterId, pointId);
  }

  /// 弹出输入框编辑记忆点内容（空内容保存视为删除由 provider 处理）
  Future<String?> _showEditDialog({
    required String title,
    String initial = '',
  }) {
    final controller = TextEditingController(text: initial);
    return showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: CupertinoTextField(
            controller: controller,
            autofocus: true,
            maxLines: 4,
            minLines: 2,
            placeholder: '输入记忆内容…',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  String _shorten(String s) => s.length > 30 ? '${s.substring(0, 30)}…' : s;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('记忆点管理'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _add,
          child: const Icon(CupertinoIcons.add),
        ),
      ),
      child: Consumer<MemoryPointProvider>(
        builder: (context, provider, _) {
          final points = provider.pointsFor(widget.characterId);
          if (points.isEmpty) {
            return ColoredBox(
              color: context.scaffoldColor,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      CupertinoIcons.bookmark,
                      size: 48,
                      color: context.textSecondaryColor,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '还没有记忆点',
                      style: TextStyle(
                        fontSize: 16,
                        color: context.textSecondaryColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '在聊天中长按消息 → 「保存为记忆点」，\n或点击右上角 + 手动添加',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: context.textSecondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return ColoredBox(
            color: context.scaffoldColor,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: points.length,
              itemBuilder: (context, index) {
                final point = points[index];
                return Container(
                  color: context.listBgColor,
                  padding: const EdgeInsets.only(left: 16, right: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _edit(point.id, point.content),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  point.content,
                                  style: TextStyle(
                                    fontSize: 15,
                                    height: 1.4,
                                    color: context.textPrimaryColor,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '记录于 ${_dateFmt.format(point.createdAt)} · 点击编辑',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: context.textSecondaryColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        onPressed: () => _edit(point.id, point.content),
                        child: Icon(
                          CupertinoIcons.pencil,
                          size: 19,
                          color: context.textSecondaryColor,
                        ),
                      ),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        onPressed: () => _delete(point.id, point.content),
                        child: const Icon(
                          CupertinoIcons.trash,
                          size: 20,
                          color: CupertinoColors.systemRed,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
