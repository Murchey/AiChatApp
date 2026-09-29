import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../providers/api_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/character_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/chat_settings_provider.dart';
import '../../providers/group_chat_provider.dart';
import '../../providers/memory_point_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/sticker_provider.dart';
import '../../providers/token_usage_provider.dart';
import '../../services/llm_service.dart';
import '../../services/memory_pool_builder.dart';
import '../../services/prompt_builder.dart';
import '../../services/tts_playback_controller.dart';

/// 触发角色主动发言 / 回复：组装 Prompt 与模型参数后调用 ChatProvider。
class ChatProactiveReply {
  ChatProactiveReply._();

  /// [replyToUser] 为 true 时针对用户最近消息分条回复。
  /// [imagePath] 非空时作为视觉输入传给模型。
  static Future<List<String>> trigger({
    required BuildContext context,
    required String conversationId,
    required String fallbackName,
    bool replyToUser = false,
    String? imagePath,
    String? stickerLabel,
    VoidCallback? onNeedModel,
  }) async {
    debugPrint(
      '[ChatProactiveReply] trigger replyToUser=$replyToUser imagePath=$imagePath',
    );
    final chatSettings = context.read<ChatSettingsProvider>();
    final model =
        context.read<ApiProvider>().getModelById(chatSettings.selectedModelId);
    if (model == null) {
      onNeedModel?.call();
      return const [];
    }

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

    final memoryPool = !isRoleplayMode && character != null
        ? MemoryPoolBuilder.build(
            character: character,
            chatProvider: chatProvider,
            groupChatProvider: context.read<GroupChatProvider>(),
            chatSettings: chatSettings,
            user: context.read<AuthProvider>().user,
            includePrivateHistory: false,
          )
        : '';

    final api = context.read<ApiProvider>();
    final compressModel = api.getModelById(api.compressionModelId) ?? model;
    final isVisionSupported = api.isVisionSupported(model.id) == true;
    final modelImagePath =
        stickerLabel == null || isVisionSupported ? imagePath : null;

    final messages = isRoleplayMode && chatSettings.enableRoleplayStream
        ? await chatProvider.runRoleplayStream(
            conversationId: conversationId,
            model: model,
            characterName: characterName,
            characterSystemPrompt: character?.systemPrompt ?? '',
            userRelationship: character?.userRelationship ?? '',
            userNickname: context.read<AuthProvider>().user?.nickname ?? '用户',
            memoryPoints: memoryPoints,
            contextCount: chatSettings.contextCount,
            progressionStyle: chatSettings.roleplayProgressionStyle.name,
            includeChoices: chatSettings.enableRoleplayChoices,
          )
        : await chatProvider.runProactiveReply(
            conversationId: conversationId,
            model: model,
            characterName: characterName,
            characterSystemPrompt: character?.systemPrompt ?? '',
            userRelationship: character?.userRelationship ?? '',
            userNickname: context.read<AuthProvider>().user?.nickname ?? '用户',
            replyToUser: replyToUser,
            contextCount: chatSettings.contextCount,
            enableCompression: chatSettings.enableCompression,
            compressModel: compressModel,
            contextLength: model.contextLength,
            compressThreshold: chatSettings.compressThreshold,
            imagePath: modelImagePath,
            activeStart: character?.activeStart ?? '',
            activeEnd: character?.activeEnd ?? '',
            memoryPoints: memoryPoints,
            extraSystemContext: memoryPool,
            roleplayMode: isRoleplayMode,
            roleplayProgressionStyle:
                chatSettings.roleplayProgressionStyle.name,
            findSticker: context.read<SettingsProvider>().allowStickerSend
                ? (query) =>
                    context.read<StickerProvider>().pickStickerForRole(query)
                : null,
          );

    debugPrint('[ChatProactiveReply] 完成: ${messages.length} 条');

    // 自动朗读
    if (conversation?.autoRead == true && messages.isNotEmpty) {
      final ttsModel = api.getModelById(api.ttsModelId);
      if (ttsModel != null && context.mounted) {
        final characterVoice = conversation == null
            ? null
            : context
                .read<CharacterProvider>()
                .getCharacterById(conversation.characterId);
        final replyMessages = chatProvider
            .getMessages(conversationId)
            .where((m) => !m.isFromUser && m.content.trim().isNotEmpty)
            .toList();
        final roundMessages = replyMessages.length >= messages.length
            ? replyMessages.sublist(replyMessages.length - messages.length)
            : replyMessages;
        final entries = roundMessages
            .map((m) => TtsPlaybackEntry(
                  messageId: m.id,
                  model: ttsModel,
                  text: m.content,
                  voice: characterVoice?.voiceId ?? '',
                  instructions: characterVoice?.voiceInstructions ?? '',
                ))
            .toList();
        if (entries.isNotEmpty) {
          if (conversation?.continuousRead == true && entries.length > 1) {
            TtsPlaybackController.instance.playSequence(entries);
          } else {
            TtsPlaybackController.instance.enqueue(entries.last);
          }
        }
      }
    }

    // 非流式语C：二次请求候选行动（流式已随正文返回）
    if (isRoleplayMode &&
        chatSettings.enableRoleplayChoices &&
        !chatSettings.enableRoleplayStream &&
        messages.isNotEmpty &&
        conversation != null &&
        context.mounted) {
      try {
        final choicePrompt = PromptBuilder.buildSystemPrompt(
          baseSystemPrompt: character?.systemPrompt ?? '',
          characterName: characterName,
          userNickname: context.read<AuthProvider>().user?.nickname ?? '用户',
          userRelationship: character?.userRelationship ?? '',
          currentTime: DateTime.now(),
          memoryPoints: memoryPoints,
          roleplayProgressionStyle: chatSettings.roleplayProgressionStyle.name,
          roleplayMode: true,
        );
        final choiceResult = await LLMService.generateRoleplayChoices(
          model: model,
          systemPrompt: choicePrompt,
          historyMessages: chatProvider.getRecentHistoryForCharacter(
            conversation.characterId,
            chatSettings.contextCount,
          ),
        );
        await TokenUsageProvider.instance.addUsage(
          conversationId,
          choiceResult.usage,
          label: fallbackName,
        );
        if (context.mounted) {
          await chatProvider.setRoleplayChoices(
            conversationId,
            choiceResult.messages,
          );
        }
      } catch (e) {
        debugPrint('[ChatProactiveReply] 语C候选失败: $e');
      }
    }

    return messages;
  }
}
