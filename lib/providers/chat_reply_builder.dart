
import 'api_provider.dart';
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

  const ChatReplyHooks({
    required this.setLastError,
    required this.estimateTokens,
    required this.setSystemTokens,
    required this.compress,
    required this.buildHistory,
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
  final prompt = PromptBuilder.buildSystemPrompt(
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
  final outputInstruction = PromptBuilder.buildOutputInstruction(
    characterName: characterName,
    replyToUser: replyToUser,
    currentTime: roleplayMode ? null : now,
    roleplayMode: roleplayMode,
    includeRoleplayChoices: false,
  );
  hooks.setSystemTokens(
    conversationId,
    hooks.estimateTokens(prompt) +
        hooks.estimateTokens(outputInstruction) +
        kChatReplyPerMessageJsonTokens * 2,
  );
  if (enableCompression && compressModel != null && contextLength > 0) {
    await hooks.compress(
      conversationId: conversationId,
      compressModel: compressModel,
      contextLength: contextLength,
      threshold: compressThreshold,
      systemPromptTokens: hooks.estimateTokens(prompt) +
          hooks.estimateTokens(outputInstruction) +
          kChatReplyPerMessageJsonTokens * 2,
      contextCount: contextCount,
    );
  }
  try {
    final history =
        historyMessages ?? hooks.buildHistory(conversationId, contextCount);
    if (imagePath != null && imagePath.isNotEmpty) {
      return await generateVisionReply(
        model: model,
        systemPrompt: prompt,
        historyMessages: history,
        imagePath: imagePath,
        outputInstruction: outputInstruction,
        roleplayMode: roleplayMode,
      );
    }
    return await generateMessages(
      model: model,
      systemPrompt: prompt,
      historyMessages: history,
      outputInstruction: outputInstruction,
      roleplayMode: roleplayMode,
    );
  } on LLMException catch (e) {
    hooks.setLastError(e.message);
    return const ProactiveResult([], ChatUsage());
  } catch (e) {
    hooks.setLastError(LLMService.describeException(e));
    return const ProactiveResult([], ChatUsage());
  }
}
