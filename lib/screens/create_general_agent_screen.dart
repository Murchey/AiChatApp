import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../config/routes.dart';
import '../config/theme.dart';
import '../models/character.dart';
import '../providers/character_provider.dart';
import '../providers/chat_provider.dart';

/// 创建普通聊天智能体，提示词由用户自由填写。
class CreateGeneralAgentScreen extends StatefulWidget {
  const CreateGeneralAgentScreen({super.key});

  @override
  State<CreateGeneralAgentScreen> createState() =>
      _CreateGeneralAgentScreenState();
}

class _CreateGeneralAgentScreenState extends State<CreateGeneralAgentScreen> {
  final _nameController = TextEditingController();
  final _promptController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (_saving || name.isEmpty) return;
    final characters = context.read<CharacterProvider>();
    final chat = context.read<ChatProvider>();
    setState(() => _saving = true);
    try {
      final agent = Character(
        id: const Uuid().v4(),
        name: name,
        systemPrompt: _promptController.text,
        isGeneralAgent: true,
      );
      await characters.addCharacter(agent);
      final conversation = chat.getOrCreateConversation(
        characterId: agent.id,
        characterName: agent.displayName,
      );
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AppRoutes.chat, arguments: {
        'conversationId': conversation.id,
        'characterName': agent.displayName,
        'characterAvatar': agent.avatar,
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      await showCupertinoDialog<void>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('创建失败'),
          content: const Text('保存智能体时出现问题，请稍后重试。'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('确定'),
            )
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: context.scaffoldColor,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('创建一般智能体'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed:
              _saving || _nameController.text.trim().isEmpty ? null : _create,
          child:
              _saving ? const CupertinoActivityIndicator() : const Text('创建'),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('名称'),
            const SizedBox(height: 8),
            CupertinoTextField(
              key: const Key('general-agent-name'),
              controller: _nameController,
              enabled: !_saving,
              placeholder: '给智能体起个名字',
              padding: const EdgeInsets.all(12),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 24),
            const Text('提示词（可选）'),
            const SizedBox(height: 8),
            CupertinoTextField(
              key: const Key('general-agent-prompt'),
              controller: _promptController,
              enabled: !_saving,
              minLines: 8,
              maxLines: null,
              placeholder: '填写你的系统提示词，留空即可直接聊天',
              padding: const EdgeInsets.all(12),
              textAlignVertical: TextAlignVertical.top,
            ),
            const SizedBox(height: 12),
            Text(
              '提示词可随时在会话详情的「提示词设置」中编辑。',
              style: TextStyle(fontSize: 13, color: context.textSecondaryColor),
            ),
          ],
        ),
      ),
    );
  }
}
