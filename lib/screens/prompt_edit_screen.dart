import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../providers/character_provider.dart';

/// 提示词编辑二级页：全屏大文本框编辑角色 systemPrompt。
/// 文字变动自动保存；底部仅保留「清空」。
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
  Timer? _debounce;
  late final CharacterProvider _characters;
  Future<void> _saveQueue = Future<void>.value();
  bool _leaving = false;
  String _status = '已自动保存';
  String _lastSavedText = '';

  @override
  void initState() {
    super.initState();
    _characters = context.read<CharacterProvider>();
    final character = _characters.getCharacterById(widget.characterId);
    _lastSavedText = character?.systemPrompt ?? '';
    _controller = TextEditingController(text: _lastSavedText);
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _leaving = true;
    // Capture pending text before disposing its controller. Queued writes keep
    // their order so the final edit cannot be overwritten by an earlier save.
    unawaited(_saveText(_controller.text));
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    setState(() => _status = '正在输入…');
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _saveNow);
  }

  Future<void> _saveNow() => _saveText(_controller.text);

  Future<void> _saveText(String text) {
    final task = _saveQueue.then((_) async {
      if (text == _lastSavedText) return;
      if (mounted && !_leaving) setState(() => _status = '保存中…');
      try {
        await _characters.updateSystemPrompt(widget.characterId, text);
        _lastSavedText = text;
        if (mounted && !_leaving) {
          setState(() => _status = '已自动保存');
        }
      } catch (_) {
        if (mounted && !_leaving) {
          setState(() => _status = '保存失败，稍后重试');
        }
      }
    });
    _saveQueue = task;
    return task;
  }

  void _clear() {
    if (_controller.text.isEmpty) return;
    _controller.text = '';
    _onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final length = _controller.text.trim().length;
    final isGeneralAgent = context
            .watch<CharacterProvider>()
            .getCharacterById(widget.characterId)
            ?.isGeneralAgent ??
        false;
    return CupertinoPageScaffold(
      backgroundColor: context.scaffoldColor,
      navigationBar: const CupertinoNavigationBar(
        middle: Text('编辑提示词'),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                children: [
                  Text(
                    '${isGeneralAgent ? '智能体' : '角色'}：${widget.characterName}',
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
                    placeholder: isGeneralAgent
                        ? '在此编辑智能体提示词…\n\n可描述：任务、能力、回答方式和约束等。'
                        : '在此编辑角色提示词…\n\n可描述：身份、性格、说话方式、世界观、禁止事项等。',
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
                    '修改后自动保存；新对话将使用新的提示词，已进行的对话不受影响。',
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
