import 'package:flutter/cupertino.dart';

import '../config/theme.dart';

/// 记忆点编辑二级页：全屏编辑单条记忆点内容。
/// 从「记忆点管理」添加 / 点条目编辑进入，替代弹窗小输入框。
class MemoryPointEditScreen extends StatefulWidget {
  final String title;
  final String initial;

  const MemoryPointEditScreen({
    super.key,
    required this.title,
    this.initial = '',
  });

  /// 返回编辑后的文本；取消返回 null
  static Future<String?> open(
    BuildContext context, {
    required String title,
    String initial = '',
  }) {
    return Navigator.push<String>(
      context,
      CupertinoPageRoute(
        builder: (_) => MemoryPointEditScreen(title: title, initial: initial),
      ),
    );
  }

  @override
  State<MemoryPointEditScreen> createState() => _MemoryPointEditScreenState();
}

class _MemoryPointEditScreenState extends State<MemoryPointEditScreen> {
  late final TextEditingController _controller;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
    _controller.addListener(() {
      if (!_dirty && mounted) setState(() => _dirty = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirmPop() async {
    if (!_dirty) {
      Navigator.pop(context);
      return;
    }
    final leave = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('放弃修改？'),
        content: const Text('内容尚未保存，返回将丢失本次编辑。'),
        actions: [
          CupertinoDialogAction(
            child: const Text('继续编辑'),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('放弃'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final length = _controller.text.trim().length;
    return CupertinoPageScaffold(
      backgroundColor: context.scaffoldColor,
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.title),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _confirmPop,
          child: const Text('返回'),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('保存'),
        ),
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
                      '已输入 $length 字',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondaryColor,
                      ),
                    ),
                  ),
                  CupertinoButton.filled(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 12,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    onPressed: () => Navigator.pop(context, _controller.text),
                    child: const Text('保存'),
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
