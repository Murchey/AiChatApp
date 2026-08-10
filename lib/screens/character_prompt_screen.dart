import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/character_provider.dart';

/// 角色系统提示词编辑页
class CharacterPromptScreen extends StatefulWidget {
  final String characterId;
  final String characterName;

  const CharacterPromptScreen({
    super.key,
    required this.characterId,
    required this.characterName,
  });

  @override
  State<CharacterPromptScreen> createState() => _CharacterPromptScreenState();
}

class _CharacterPromptScreenState extends State<CharacterPromptScreen> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final character =
        context.read<CharacterProvider>().getCharacterById(widget.characterId);
    _controller = TextEditingController(text: character?.systemPrompt ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await context
        .read<CharacterProvider>()
        .updateSystemPrompt(widget.characterId, _controller.text.trim());
    if (mounted) {
      Navigator.pop(context);
      // 提示已保存
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('已保存'),
          content: const Text('系统提示词修改成功'),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('好'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text('${widget.characterName}的提示词'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _save,
          child: Text(
            '保存',
            style: TextStyle(
              color: context.accentColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '系统提示词决定角色的说话风格与设定，修改后将影响后续所有对话。',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: context.textSecondaryColor,
                  ),
                ),
                const SizedBox(height: 12),
                CupertinoTextField(
                  controller: _controller,
                  maxLines: 12,
                  minLines: 8,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.fieldBgColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.6,
                    color: context.textPrimaryColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '剩余字符：${_remainingChars()}',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              color: context.textSecondaryColor,
            ),
          ),
        ],
      ),
    );
  }

  int _remainingChars() {
    final len = _controller.text.length;
    return len > 2000 ? 0 : 2000 - len;
  }
}
