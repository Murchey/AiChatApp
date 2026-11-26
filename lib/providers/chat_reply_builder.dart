import 'dart:io';

import 'api_provider.dart';
import 'chat_token_estimator.dart';
import '../services/llm_service.dart';
import '../services/prompt_builder.dart';

/// ChatProvider 与回复生成之间的回调钩子。
class ChatReplyHooks {
  final void Function(String? message) setLastError;
  final int Function(String text) estimateTokens;
  final void Function(String conversationId, int tokens) setSystemTokens;
  final Future<void> Function({
    required String conversationId,
    required ApiModel compressModel,
    required int contextLength,
    required double threshold,
    required int systemPromptTokens,
    required int contextCount,
  }) compress;
  final List<Map<String, Object>> Function(String conversationId, int count)
      buildHistory;
  final List<Map<String, Object>> Function(String conversationId, int count)?
      buildGeneralAgentHistory;

  const ChatReplyHooks({
    required this.setLastError,
    required this.estimateTokens,
    required this.setSystemTokens,
    required this.compress,
    required this.buildHistory,
    this.buildGeneralAgentHistory,
  });
}

const int kChatReplyPerMessageJsonTokens = 5;

/// 组装 Prompt 并请求模型（私聊主动发言 / 回复）。
/// 独立于 ChatProvider，便于拆分大类。
Future<ProactiveResult> generateProactiveMessagesWithHooks({
  required ChatReplyHooks hooks,
  required String conversationId,
  required ApiModel model,
  required String characterName,
  required String characterSystemPrompt,
  required String userRelationship,
  required String userNickname,
  bool replyToUser = false,
  bool roleplayMode = false,
  bool isGeneralAgent = false,
  String roleplayProgressionStyle = 'free',
  List<Map<String, Object>>? historyMessages,
  int contextCount = 10,
  ApiModel? compressModel,
  bool enableCompression = false,
  int contextLength = 8000,
  double compressThreshold = 0.7,
  String? imagePath,
  String activeStart = '',
  String activeEnd = '',
  List<String> memoryPoints = const [],
  String extraSystemContext = '',
}) async {
  final now = DateTime.now();
  final prompt = isGeneralAgent
      ? characterSystemPrompt
      : PromptBuilder.buildSystemPrompt(
          baseSystemPrompt: characterSystemPrompt,
          characterName: characterName,
          userNickname: userNickname,
          userRelationship: userRelationship,
          currentTime: now,
          replyToUser: replyToUser,
          activeStart: roleplayMode ? '' : activeStart,
          activeEnd: roleplayMode ? '' : activeEnd,
          memoryPoints: memoryPoints,
          roleplayProgressionStyle: roleplayProgressionStyle,
          extraContext: roleplayMode ? '' : extraSystemContext,
          roleplayMode: roleplayMode,
        );
  final outputInstruction = isGeneralAgent
      ? ''
      : PromptBuilder.buildOutputInstruction(
          characterName: characterName,
          replyToUser: replyToUser,
          currentTime: roleplayMode ? null : now,
          roleplayMode: roleplayMode,
          includeRoleplayChoices: false,
        );
  final fixedMessages = <Map<String, Object>>[
    if (!isGeneralAgent || prompt.trim().isNotEmpty)
      {'role': 'system', 'content': prompt},
    if (outputInstruction.trim().isNotEmpty)
      {'role': 'user', 'content': outputInstruction.trim()},
  ];
  final systemTokens = ChatTokenEstimator.estimatePayload(fixedMessages);
  hooks.setSystemTokens(conversationId, systemTokens);
  var recordedUsage = const ChatUsage();
  void recordUsage(ChatUsage usage) {
    recordedUsage = recordedUsage.add(usage);
  }

  try {
    final hasImage = imagePath != null && imagePath.isNotEmpty;
    // The vision service sends this image in the final output-instruction turn.
    var imageTokens = 0;
    if (hasImage) {
      try {
        await File(imagePath).length();
      } catch (_) {
        throw const LLMException('无法读取图片，请重新选择图片后重试');
      }
      // Visual token cost depends on image dimensions and provider processing.
      // This fixed reserve avoids treating base64 bytes as visual tokens.
      imageTokens =
          4096 + (isGeneralAgent ? ChatTokenEstimator.perMessageJsonTokens : 0);
    }
    final fixedBudget = ChatTokenEstimator.requestBudget(
      model: model,
      messages: fixedMessages,
      requestedOutputTokens: ChatTokenEstimator.proactiveReplyOutputTokens,
      contextLength: model.contextLength,
      additionalInputTokens: imageTokens,
    );
    fixedBudget.ensureFits();
    // Explicit history is a caller-owned projection and cannot be rebuilt from
    // stored messages after compression.
    if (!isGeneralAgent &&
        historyMessages == null &&
        enableCompression &&
        compressModel != null &&
        model.contextLength > 0) {
      await hooks.compress(
        conversationId: conversationId,
        compressModel: compressModel,
        contextLength: model.contextLength,
        threshold: compressThreshold,
        systemPromptTokens:
            systemTokens + imageTokens + fixedBudget.reservedTokens,
        contextCount: contextCount,
      );
    }
    final history = historyMessages ??
        (isGeneralAgent
            ? hooks.buildGeneralAgentHistory
                    ?.call(conversationId, contextCount) ??
                hooks.buildHistory(conversationId, contextCount)
            : hooks.buildHistory(conversationId, contextCount));
    ChatTokenEstimator.requestBudget(
      model: model,
      messages: [
        if (!isGeneralAgent || prompt.trim().isNotEmpty)
          {'role': 'system', 'content': prompt},
        ...history,
        if (outputInstruction.trim().isNotEmpty)
          {'role': 'user', 'content': outputInstruction.trim()},
      ],
      requestedOutputTokens: ChatTokenEstimator.proactiveReplyOutputTokens,
      contextLength: model.contextLength,
      additionalInputTokens: imageTokens,
    ).ensureFits();
    if (imagePath != null && imagePath.isNotEmpty) {
      return await generateVisionReply(
        model: model,
        systemPrompt: prompt,
        historyMessages: history,
        imagePath: imagePath,
        outputInstruction: outputInstruction,
        roleplayMode: roleplayMode,
        isGeneralAgent: isGeneralAgent,
        onUsage: recordUsage,
      );
    }
    return await generateMessages(
      model: model,
      systemPrompt: prompt,
      historyMessages: history,
      outputInstruction: outputInstruction,
      roleplayMode: roleplayMode,
      isGeneralAgent: isGeneralAgent,
      onUsage: recordUsage,
    );
  } on LLMException catch (e) {
    hooks.setLastError(e.message);
    return ProactiveResult([], recordedUsage);
  } catch (e) {
    hooks.setLastError(LLMService.describeException(e));
    return ProactiveResult([], recordedUsage);
  }
}
