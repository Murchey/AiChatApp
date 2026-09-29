import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../models/character.dart';
import '../../models/message.dart';
import '../../providers/character_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/memory_point_provider.dart';
import '../chat_screen.dart';

/// 单条消息操作：查看思考、选择文本、编辑、撤回、重新回复、增加分支。
class ChatMessageActions {
  ChatMessageActions._();

  static String formatThinkingDuration(int ms) {
    if (ms < 1000) return '${ms}ms';
    final s = ms / 1000;
    return s >= 10 ? '${s.toStringAsFixed(0)}s' : '${s.toStringAsFixed(1)}s';
  }

  static Future<void> showReasoning(
    BuildContext context,
    Message message,
  ) {
    final text = message.reasoningContent.trim();
    if (text.isEmpty) return Future.value();
    final duration = message.reasoningDurationMs;
    return showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('AI 思考过程'),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.55,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (duration != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '思考耗时 ${formatThinkingDuration(duration)}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: ctx.textSecondaryColor,
                      ),
                    ),
                  ),
                Text(
                  text,
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: ctx.textPrimaryColor,
                  ),
                ),
              ],
            ),
          ),
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

  static Future<void> showTextSelection(
    BuildContext context,
    Message message,
  ) {
    return showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('选择文本'),
        content: CupertinoTextField(
          controller: TextEditingController(text: message.content),
          maxLines: null,
          readOnly: true,
          style: TextStyle(
            fontSize: 15,
            color: ctx.textPrimaryColor,
          ),
          decoration: const BoxDecoration(color: CupertinoColors.transparent),
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('关闭'),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }

  static Future<void> editMessage(
    BuildContext context, {
    required String conversationId,
    required Message message,
  }) async {
    final controller = TextEditingController(text: message.content);
    final content = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(
          message.type == MessageType.narration ? '编辑剧情行动' : '修改角色回复',
        ),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            autofocus: true,
            maxLines: 8,
            minLines: 3,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (content == null || content.trim().isEmpty || !context.mounted) return;
    await context.read<ChatProvider>().editMessage(
          conversationId: conversationId,
          messageId: message.id,
          content: content,
        );
  }

  /// 撤回：删除消息，内容回填输入框；[onClearedQuote] 若撤回的是被引用消息则清空引用
  static void withdraw(
    BuildContext context, {
    required String conversationId,
    required Message message,
    required void Function(String text) setTextInput,
    required void Function() focusInput,
    required Message? Function() currentQuote,
    required void Function() clearQuote,
  }) {
    context.read<ChatProvider>().withdrawMessage(conversationId, message.id);
    setTextInput(message.content);
    focusInput();
    if (currentQuote()?.id == message.id) clearQuote();
  }

  /// 重新回复：删除 AI 条与上一条用户消息后重新发送
  static void reroll({
    required BuildContext context,
    required String conversationId,
    required Message aiMessage,
    required void Function(String content) resend,
  }) {
    final chatProvider = context.read<ChatProvider>();
    final messages = chatProvider.getMessages(conversationId);
    Message? lastUserMessage;
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].id == aiMessage.id) continue;
      if (messages[i].isFromUser) {
        lastUserMessage = messages[i];
        break;
      }
    }
    if (lastUserMessage == null) return;
    chatProvider.deleteMessage(conversationId, aiMessage.id);
    chatProvider.deleteMessage(conversationId, lastUserMessage.id);
    resend(lastUserMessage.content);
  }

  /// 从当前消息处分出新角色会话（复制角色卡 + 记忆点 + 截至该条的聊天）
  static Future<void> branchConversation(
    BuildContext context, {
    required String conversationId,
    required Message message,
  }) async {
    final controller = TextEditingController();
    final newName = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('增加分支'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '给新角色命名，将从当前消息处分出新会话：\n'
                '该条及之前的聊天记录会复制到新会话，之后的消息不会带入。\n'
                '新角色将完整复制当前角色的角色包内容（人设、提示词、头像、记忆点等），仅名称为你新填的名字。',
                style: TextStyle(fontSize: 13, height: 1.45),
              ),
              const SizedBox(height: 10),
              CupertinoTextField(
                controller: controller,
                autofocus: true,
                maxLength: 20,
                placeholder: '输入新角色名称',
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
            child: const Text('创建分支'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || newName.isEmpty || !context.mounted) return;

    final characterProvider = context.read<CharacterProvider>();
    final chatProvider = context.read<ChatProvider>();
    final memoryProvider = context.read<MemoryPointProvider>();

    final sourceConversation = chatProvider.conversations
        .where((c) => c.id == conversationId)
        .firstOrNull;
    final source = sourceConversation == null
        ? null
        : characterProvider.getCharacterById(sourceConversation.characterId);

    final characterId =
        'branch_${DateTime.now().millisecondsSinceEpoch}';
    final newCharacter = source == null
        ? Character(id: characterId, name: newName)
        : Character(
            id: characterId,
            name: newName,
            remark: source.remark,
            signature: source.signature,
            region: source.region,
            avatar: source.avatar,
            background: source.background,
            description: source.description,
            personality: source.personality,
            greeting: source.greeting,
            systemPrompt: source.systemPrompt,
            userRelationship: source.userRelationship,
            activeStart: source.activeStart,
            activeEnd: source.activeEnd,
            modelId: source.modelId,
            defaultModelId: source.defaultModelId,
            tags: List.of(source.tags),
            moments: List.of(source.moments),
          );

    await characterProvider.addCharacter(newCharacter);
    if (source != null) {
      await memoryProvider.replacePoints(
        characterId,
        memoryProvider.pointsFor(source.id).toList(),
      );
    }
    if (!context.mounted) return;

    try {
      final branch = await chatProvider.branchConversation(
        sourceConversationId: conversationId,
        throughMessageId: message.id,
        newCharacterId: characterId,
        newCharacterName: newName,
        newCharacterAvatar: source?.avatar ?? '',
      );
      if (!context.mounted) return;
      await Navigator.push(
        context,
        CupertinoPageRoute(
          builder: (_) => ChatScreen(
            conversationId: branch.id,
            characterName: newName,
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      await showCupertinoDialog<void>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('提示'),
          content: Text('创建分支失败：$e'),
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
  }
}
