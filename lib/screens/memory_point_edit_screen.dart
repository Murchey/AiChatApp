import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../providers/memory_point_provider.dart';

/// 记忆点编辑二级页：全屏编辑单条记忆点。
/// 文字变动自动保存；底部仅保留「清空」。
class MemoryPointEditScreen extends StatefulWidget {
  final String characterId;

  /// 编辑已有记忆点时传入；为空表示新增
  final String? pointId;
  final String initial;

  const MemoryPointEditScreen({
    super.key,
    required this.characterId,
    this.pointId,
    this.initial = '',
  });

  static Future<void> open(
    BuildContext context, {
    required String characterId,
    String? pointId,
    String initial = '',
  }) {
    return Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => MemoryPointEditScreen(
          characterId: characterId,
          pointId: pointId,
          initial: initial,
        ),
      ),
    );
  }

  @override
  State<MemoryPointEditScreen> createState() => _MemoryPointEditScreenState();
}

class _MemoryPointEditScreenState extends State<MemoryPointEditScreen> {
  late final TextEditingController _controller;
  Timer? _debounce;
  bool _saving = false;
  bool _pendingSave = false;
  String? _pointId;
  String _status = '已自动保存';
  String _lastSavedText = '';

  @override
  void initState() {
    super.initState();
    _pointId = widget.pointId;
    _lastSavedText = widget.initial;
    _controller = TextEditingController(text: widget.initial);
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _flushSave();
    super.dispose();
  }

  void _onChanged() {
    final text = _controller.text;
    if (text == _lastSavedText) return;
    setState(() => _status = '正在输入…');
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _saveNow);
  }

  Future<void> _flushSave() async {
    _debounce?.cancel();
    if (_controller.text != _lastSavedText) {
      await _saveNow();
    }
  }

  Future<void> _saveNow() async {
    if (_saving) {
      _pendingSave = true;
      return;
    }
    final text = _controller.text;
    if (text == _lastSavedText) return;
    setState(() {
      _saving = true;
      _status = '保存中…';
    });
    final provider = context.read<MemoryPointProvider>();
    try {
      if (_pointId != null) {
        await provider.updatePoint(widget.characterId, _pointId!, text);
      } else if (text.trim().isNotEmpty) {
        // 新建：首次有内容时插入，并记录 id 供后续编辑
        await provider.addPoints(widget.characterId, [text]);
        final created = provider
            .pointsFor(widget.characterId)
            .where((p) => p.content == text.trim())
            .toList();
        if (created.isNotEmpty) _pointId = created.first.id;
      }
      _lastSavedText = text;
      if (mounted) {
        setState(() {
          _saving = false;
          _status = '已自动保存';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _status = '保存失败，稍后重试';
        });
      }
    }
    if (_pendingSave) {
      _pendingSave = false;
      if (mounted) await _saveNow();
    }
  }

  void _clear() {
    if (_controller.text.isEmpty) return;
    _controller.text = '';
    _onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final length = _controller.text.trim().length;
    final isNew = widget.pointId == null && _pointId == null;
    return CupertinoPageScaffold(
      backgroundColor: context.scaffoldColor,
      navigationBar: CupertinoNavigationBar(
        middle: Text(isNew ? '添加记忆点' : '编辑记忆点'),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                children: [
                  Text(
                    '可写入世界观、用户人设、重要剧情节点等，对话时会回传到上下文。',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: context.textSecondaryColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  CupertinoTextField(
                    controller: _controller,
                    maxLines: null,
                    minLines: 16,
                    textAlignVertical: TextAlignVertical.top,
                    placeholder: '输入记忆内容…',
                    placeholderStyle: TextStyle(
                      fontSize: 15,
                      height: 1.6,
                      color: context.textSecondaryColor,
                    ),
                    padding: const EdgeInsets.all(14),
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.65,
                      color: context.textPrimaryColor,
                    ),
                    decoration: BoxDecoration(
                      color: context.fieldBgColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '修改后自动保存；清空内容并自动保存后将删除该记忆点。',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: context.textSecondaryColor,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              decoration: BoxDecoration(
                color: context.listBgColor,
                border: Border(top: BorderSide(color: context.separatorColor)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '已输入 $length 字 · $_status',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondaryColor,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    onPressed: _clear,
                    child: const Text('清空'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
