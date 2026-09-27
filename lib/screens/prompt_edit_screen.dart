import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../providers/character_provider.dart';

/// 提示词编辑二级页：全屏大文本框编辑角色 systemPrompt。
/// 从「聊天详情 → 提示词设置」进入，替代原先的行内小输入框。
class PromptEditScreen extends StatefulWidget {
  final String characterId;
  final String characterName;

  const PromptEditScreen({
    super.key,
    required this.characterId,
    required this.characterName,
  });

  @override
  State<PromptEditScreen> createState() => _PromptEditScreenState();
}

class _PromptEditScreenState extends State<PromptEditScreen> {
  late final TextEditingController _controller;
  bool _saving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final character =
        context.read<CharacterProvider>().getCharacterById(widget.characterId);
    _controller = TextEditingController(text: character?.systemPrompt ?? '');
    _controller.addListener(() {
      if (!_dirty && mounted) setState(() => _dirty = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    await context
        .read<CharacterProvider>()
        .updateSystemPrompt(widget.characterId, _controller.text.trim());
    if (!mounted) return;
    setState(() {
      _saving = false;
      _dirty = false;
    });
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('已保存'),
        content: const Text('提示词已更新，新对话将使用该提示词。'),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
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
        content: const Text('提示词尚未保存，返回将丢失本次编辑。'),
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
        middle: const Text('编辑提示词'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _confirmPop,
          child: const Text('返回'),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _saving ? null : _save,
          child: _saving
              ? const CupertinoActivityIndicator(radius: 10)
              : const Text('保存'),
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
                    '角色：${widget.characterName}',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.textSecondaryColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  CupertinoTextField(
                    controller: _controller,
                    maxLines: null,
                    minLines: 18,
                    expands: false,
                    textAlignVertical: TextAlignVertical.top,
                    placeholder:
                        '在此编辑角色提示词…\n\n可描述：身份、性格、说话方式、世界观、禁止事项等。',
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
                    '保存后新对话将使用新的提示词，已进行的对话不受影响。',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: context.textSecondaryColor,
                    ),
                  ),
                ],
              ),
            ),
            // 底部工具条
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
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    onPressed: () {
                      _controller.text = '';
                      setState(() => _dirty = true);
                    },
                    child: const Text('清空'),
                  ),
                  const SizedBox(width: 8),
                  CupertinoButton.filled(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 12,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    onPressed: _saving ? null : _save,
                    child: const Text('保存提示词'),
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
