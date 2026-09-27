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
  bool _saving = false;
  bool _pendingSave = false;
  String _status = '已自动保存';
  String _lastSavedText = '';

  @override
  void initState() {
    super.initState();
    final character =
        context.read<CharacterProvider>().getCharacterById(widget.characterId);
    _lastSavedText = character?.systemPrompt ?? '';
    _controller = TextEditingController(text: _lastSavedText);
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onChanged);
    _controller.dispose();
    // 退出前把未写入的内容落盘
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
    try {
      await context
          .read<CharacterProvider>()
          .updateSystemPrompt(widget.characterId, text);
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
