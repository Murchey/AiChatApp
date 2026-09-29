import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../providers/api_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/character_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/chat_settings_provider.dart';
import '../../providers/memory_point_provider.dart';
import '../../providers/token_usage_provider.dart';
import '../../services/llm_service.dart';
import '../../services/prompt_builder.dart';

/// 剧情建议：询问补充 → 生成 → 点选填入输入框。
class ChatPlotSuggestion {
  ChatPlotSuggestion._();

  static Future<void> run(
    BuildContext context, {
    required String conversationId,
    required String fallbackName,
    required void Function(String text) fillInput,
    required VoidCallback? onNeedModel,
  }) async {
    final chatSettings = context.read<ChatSettingsProvider>();
    final model =
        context.read<ApiProvider>().getModelById(chatSettings.selectedModelId);
    if (model == null) {
      onNeedModel?.call();
      return;
    }

    final controller = TextEditingController();
    final supplement = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('剧情建议'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '生成前有补充要交代吗？会写进这次的建议里。',
                style: TextStyle(fontSize: 13, height: 1.45),
              ),
              const SizedBox(height: 10),
              CupertinoTextField(
                controller: controller,
                autofocus: true,
                maxLines: 4,
                minLines: 2,
                placeholder: '可选：想发展的方向、禁忌、心情…',
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('生成建议'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (supplement == null || !context.mounted) return;

    final chatProvider = context.read<ChatProvider>();
    final conversation = chatProvider.conversations
        .where((c) => c.id == conversationId)
        .firstOrNull;
    final character = conversation != null
        ? context
            .read<CharacterProvider>()
            .getCharacterById(conversation.characterId)
        : null;
    final isRoleplayMode = chatSettings.isRoleplayMode;
    final characterName = isRoleplayMode
        ? (character?.name.trim().isNotEmpty == true
            ? character!.name.trim()
            : fallbackName)
        : character?.displayName ?? fallbackName;
    final memoryPoints = conversation != null
        ? context
            .read<MemoryPointProvider>()
            .pointsFor(conversation.characterId)
            .map((p) => p.content)
            .toList()
        : const <String>[];
    final historyMessages = conversation == null
        ? const <Map<String, String>>[]
        : chatProvider.getRecentHistoryForCharacter(
            conversation.characterId,
            chatSettings.contextCount,
          );
    final systemPrompt = PromptBuilder.buildSystemPrompt(
      baseSystemPrompt: character?.systemPrompt ?? '',
      characterName: characterName,
      userNickname: context.read<AuthProvider>().user?.nickname ?? '用户',
      userRelationship: character?.userRelationship ?? '',
      currentTime: DateTime.now(),
      memoryPoints: memoryPoints,
      roleplayProgressionStyle: chatSettings.roleplayProgressionStyle.name,
      roleplayMode: isRoleplayMode,
    );

    if (!context.mounted) return;
    showCupertinoDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const CupertinoAlertDialog(
        title: Text('剧情建议'),
        content: Padding(
          padding: EdgeInsets.only(top: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CupertinoActivityIndicator(),
              SizedBox(width: 12),
              Text('正在生成建议…'),
            ],
          ),
        ),
      ),
    );
    try {
      final result = await generatePlotSuggestions(
        model: model,
        systemPrompt: systemPrompt,
        historyMessages: historyMessages,
        userSupplement: supplement,
        roleplayMode: isRoleplayMode,
      );
      await TokenUsageProvider.instance.addUsage(
        conversationId,
        result.usage,
        label: fallbackName,
      );
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      final suggestions = result.messages
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (suggestions.isEmpty) {
        await _tip(context, '没有生成有效的剧情建议，可稍后重试');
        return;
      }
      await _showResult(context, suggestions, fillInput);
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await _tip(context, '生成失败：${LLMService.describeException(e)}');
    }
  }

  static Future<void> _tip(BuildContext context, String message) {
    return showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('提示'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  static Future<void> _showResult(
    BuildContext context,
    List<String> suggestions,
    void Function(String) fillInput,
  ) {
    return showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('剧情建议'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '点选一条填入输入框，可编辑后发送',
              style: TextStyle(fontSize: 12, color: ctx.textSecondaryColor),
            ),
            const SizedBox(height: 10),
            for (final suggestion in suggestions) ...[
              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  color: ctx.fieldBgColor,
                  borderRadius: BorderRadius.circular(10),
                  alignment: Alignment.centerLeft,
                  onPressed: () {
                    Navigator.pop(ctx);
                    fillInput(suggestion);
                  },
                  child: Text(
                    suggestion,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: ctx.textPrimaryColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
