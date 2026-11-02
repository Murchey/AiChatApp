import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/memory_point.dart';
import '../providers/memory_point_provider.dart';
import 'memory_point_edit_screen.dart';

/// 记忆点管理页：单页两个分区 ——
/// 「AI 托管 · 剧情记录」：记忆点自动托管写入的剧情记录（sourceType == 'auto'），
/// AI 可增/改/删，用户可查看、搜索、批量删除；
/// 「我的记忆」：手动添加、长按保存的记忆与故事线社区安装的内容。
/// 顶部搜索框跨分区过滤，导航栏「选择」进入多选批量删除。
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

  String _query = '';
  bool _selecting = false;
  final Set<String> _selected = <String>{};

  Future<void> _add() async {
    await MemoryPointEditScreen.open(
      context,
      characterId: widget.characterId,
    );
  }

  Future<void> _edit(String pointId, String oldContent) async {
    await MemoryPointEditScreen.open(
      context,
      characterId: widget.characterId,
      pointId: pointId,
      initial: oldContent,
    );
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

  void _toggleSelectMode() {
    setState(() {
      _selecting = !_selecting;
      _selected.clear();
    });
  }

  void _toggleSelection(String pointId) {
    setState(() {
      if (!_selected.remove(pointId)) _selected.add(pointId);
    });
  }

  Future<void> _confirmBatchDelete() async {
    if (_selected.isEmpty) return;
    final count = _selected.length;
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('批量删除记忆点'),
        content: Text('确定删除选中的 $count 条记忆点吗？此操作不可恢复。'),
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
    final ids = _selected.toList();
    setState(() {
      _selected.clear();
      _selecting = false;
    });
    await context.read<MemoryPointProvider>().removePoints(
          widget.characterId,
          ids,
        );
  }

  String _shorten(String s) => s.length > 30 ? '${s.substring(0, 30)}…' : s;

  List<MemoryPoint> _filter(List<MemoryPoint> points) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return points;
    return points
        .where((p) => p.content.toLowerCase().contains(q))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('记忆点管理'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Consumer<MemoryPointProvider>(
              builder: (context, provider, _) {
                if (provider.pointsFor(widget.characterId).isEmpty) {
                  return const SizedBox.shrink();
                }
                return CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _toggleSelectMode,
                  child: Text(_selecting ? '完成' : '选择'),
                );
              },
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _add,
              child: const Icon(CupertinoIcons.add),
            ),
          ],
        ),
      ),
      child: ColoredBox(
        color: context.scaffoldColor,
        child: SafeArea(
          child: Consumer<MemoryPointProvider>(
            builder: (context, provider, _) {
              final points = provider.pointsFor(widget.characterId);
              final autoPoints =
                  points.where((p) => p.isAutoManaged).toList(growable: false);
              final myPoints =
                  points.where((p) => !p.isAutoManaged).toList(growable: false);
              final autoVisible = _filter(autoPoints);
              final myVisible = _filter(myPoints);
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                    child: CupertinoSearchTextField(
                      placeholder: '搜索记忆点',
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 16),
                      children: [
                        _sectionHeader(
                          'AI 托管 · 剧情记录',
                          autoPoints.length,
                          subtitle: '由 AI 自动记录剧情推进，可查看、搜索、批量删除',
                        ),
                        if (autoVisible.isEmpty)
                          _emptyLine(_query.trim().isEmpty
                              ? '暂无托管记录\n在「聊天设置」开启「记忆点自动托管」后，AI 会自动记录'
                              : '没有匹配的记忆点')
                        else
                          for (final point in autoVisible) ...[
                            _row(point),
                            _separator(),
                          ],
                        const SizedBox(height: 16),
                        _sectionHeader(
                          '我的记忆',
                          myPoints.length,
                          subtitle: '手动保存的记忆与故事线社区安装的内容',
                        ),
                        if (myVisible.isEmpty)
                          _emptyLine(_query.trim().isEmpty
                              ? '还没有记忆点\n在聊天中长按消息 →「保存为记忆点」，或点击右上角 + 手动添加'
                              : '没有匹配的记忆点')
                        else
                          for (final point in myVisible) ...[
                            _row(point),
                            _separator(),
                          ],
                      ],
                    ),
                  ),
                  if (_selecting)
                    _selectionBar(
                      [...autoVisible, ...myVisible].map((p) => p.id).toSet(),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, int count, {required String subtitle}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.textSecondaryColor,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count 条',
                style: TextStyle(
                  fontSize: 11,
                  color: context.textSecondaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: context.textSecondaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyLine(String text) {
    return Container(
      color: context.listBgColor,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          height: 1.5,
          color: context.textSecondaryColor,
        ),
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

  Widget _badge(String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _row(MemoryPoint point) {
    final selected = _selected.contains(point.id);
    final badge = point.isAutoManaged
        ? _badge('AI 记录', context.accentColor)
        : (point.isStory
            ? _badge(
                '故事线${point.sourceTitle == null || point.sourceTitle!.trim().isEmpty ? '' : ' · ${point.sourceTitle}'}',
                CupertinoColors.systemPurple,
              )
            : null);
    return Container(
      color: context.listBgColor,
      padding: const EdgeInsets.only(left: 16, right: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (_selecting)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _toggleSelection(point.id),
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(
                  selected
                      ? CupertinoIcons.check_mark_circled_solid
                      : CupertinoIcons.circle,
                  size: 22,
                  color: selected
                      ? context.accentColor
                      : context.textSecondaryColor,
                ),
              ),
            ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _selecting
                  ? () => _toggleSelection(point.id)
                  : () => _edit(point.id, point.content),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (badge != null) badge,
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
                      _selecting
                          ? '记录于 ${_dateFmt.format(point.createdAt)}'
                          : '记录于 ${_dateFmt.format(point.createdAt)} · 点击编辑',
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
          if (!_selecting) ...[
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              onPressed: () => _edit(point.id, point.content),
              child: Icon(
                CupertinoIcons.pencil,
                size: 19,
                color: context.textSecondaryColor,
              ),
            ),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              onPressed: () => _delete(point.id, point.content),
              child: const Icon(
                CupertinoIcons.trash,
                size: 20,
                color: CupertinoColors.systemRed,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _selectionBar(Set<String> visibleIds) {
    final allSelected =
        visibleIds.isNotEmpty && visibleIds.every(_selected.contains);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: context.listBgColor,
        border: Border(top: BorderSide(color: context.separatorColor)),
      ),
      child: Row(
        children: [
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            onPressed: () {
              setState(() {
                if (allSelected) {
                  _selected.removeAll(visibleIds);
                } else {
                  _selected.addAll(visibleIds);
                }
              });
            },
            child: Text(allSelected ? '取消全选' : '全选'),
          ),
          const Spacer(),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            onPressed: _selected.isEmpty ? null : _confirmBatchDelete,
            child: Text(
              '删除(${_selected.length})',
              style: TextStyle(
                color: _selected.isEmpty
                    ? context.textSecondaryColor
                    : CupertinoColors.systemRed,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
