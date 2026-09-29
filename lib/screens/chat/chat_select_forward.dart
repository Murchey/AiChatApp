import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../providers/api_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/character_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/chat_settings_provider.dart';
import '../../providers/memory_point_provider.dart';
import '../../services/llm_service.dart';

enum MemorySaveMode { direct, compress }

/// 多选模式下的「存记忆点 / 转发」。
/// 选中集合与模式开关仍由 ChatScreen 持有，这里只做业务与弹窗。
class ChatSelectForward {
  ChatSelectForward._();

  /// 保存选中的文本消息为角色记忆点（多条合并为一条）。
  static Future<void> saveSelectedAsMemory(
    BuildContext context, {
    required String conversationId,
    required String fallbackCharacterName,
    required Set<String> selectedIds,
    required VoidCallback onSaved,
  }) async {
    final chatProvider = context.read<ChatProvider>();
    final conversation = chatProvider.conversations
        .where((c) => c.id == conversationId)
        .firstOrNull;
    if (conversation == null) return;
    final character = context
        .read<CharacterProvider>()
        .getCharacterById(conversation.characterId);
    final characterName = character?.displayName ?? fallbackCharacterName;
    final userName = context.read<AuthProvider>().user?.nickname ?? '用户';

    final messages = chatProvider
        .getMessages(conversationId)
        .where((m) => selectedIds.contains(m.id))
        .toList();
    final texts = messages
        .where((m) => m.type == MessageType.text && m.content.trim().isNotEmpty)
        .map((m) =>
            '${m.isFromUser ? userName : characterName}说："${m.content.trim()}"')
        .toList();
    if (texts.isEmpty) {
      await _alert(context, '提示', '选中的消息中不包含可保存的文字内容');
      return;
    }
    final mergedContent = texts.join('\n');

    final memoryProvider = context.read<MemoryPointProvider>();
    final saveMode = await showCupertinoDialog<MemorySaveMode>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('保存为记忆点'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '将以下 ${texts.length} 条消息保存为「$characterName」的一条记忆点：',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final t in texts)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(t, style: const TextStyle(fontSize: 13)),
                        ),
                    ],
                  ),
                ),
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
            onPressed: () => Navigator.pop(ctx, MemorySaveMode.direct),
            child: const Text('直接保存'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, MemorySaveMode.compress),
            child: const Text('总结压缩后保存'),
          ),
        ],
      ),
    );
    if (saveMode == null || !context.mounted) return;

    var memoryContent = mergedContent;
    if (saveMode == MemorySaveMode.compress) {
      final chatSettings = context.read<ChatSettingsProvider>();
      final model = context
          .read<ApiProvider>()
          .getModelById(chatSettings.selectedModelId);
      if (model == null) {
        await _alert(
          context,
          '无法总结',
          '尚未配置当前聊天模型，请先到「API 设置」中选择可用模型。',
        );
        return;
      }

      final compressionHistory = messages
          .where(
              (m) => m.type == MessageType.text && m.content.trim().isNotEmpty)
          .map((m) => <String, String>{
                'role': m.isFromUser ? 'user' : 'assistant',
                'content':
                    '${m.isFromUser ? userName : characterName}：${m.content.trim()}',
              })
          .toList();

      showCupertinoDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const CupertinoAlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CupertinoActivityIndicator(),
              SizedBox(height: 12),
              Text('正在总结记忆，请稍候……'),
            ],
          ),
        ),
      );
      try {
        final summary = await LLMService.compressHistory(
          model: model,
          historyMessages: compressionHistory,
        );
        if (summary.trim().isEmpty) {
          throw const LLMException('模型没有返回有效的总结内容');
        }
        memoryContent = summary.trim();
      } catch (e) {
        if (context.mounted) {
          Navigator.of(context, rootNavigator: true).pop();
          await _alert(context, '总结失败', LLMService.describeException(e));
        }
        return;
      }
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (!context.mounted) return;
    }

    await memoryProvider.addPoints(conversation.characterId, [memoryContent]);
    onSaved();
    if (!context.mounted) return;
    await _alert(
      context,
      '已保存',
      '已将 ${texts.length} 条消息合并为一条记忆点保存，后续对话中「$characterName」会自动记住这些内容。可在聊天详情「提示词设置 → 记忆点管理」中查看或修改。',
    );
  }

  /// 转发选中消息；[merge] 为 true 时合并转发卡片。
  static Future<void> forwardMessages(
    BuildContext context, {
    required String conversationId,
    required String fallbackCharacterName,
    required Set<String> selectedIds,
    required bool merge,
    required VoidCallback onDone,
  }) async {
    final chatProvider = context.read<ChatProvider>();
    final messages = chatProvider
        .getMessages(conversationId)
        .where((m) => selectedIds.contains(m.id))
        .toList();
    if (messages.isEmpty) return;

    final target = await pickTargetConversation(context, conversationId);
    if (target == null || !context.mounted) return;

    final conversation = chatProvider.conversations
        .where((c) => c.id == conversationId)
        .firstOrNull;
    final character = conversation != null
        ? context
            .read<CharacterProvider>()
            .getCharacterById(conversation.characterId)
        : null;
    final sourceName = character?.displayName ?? fallbackCharacterName;
    final sourceAvatar = character?.avatar ?? '';

    if (merge) {
      await chatProvider.forwardMerged(
        conversationId: target.id,
        sourceName: sourceName,
        sourceAvatar: sourceAvatar,
        messages: messages,
      );
    } else {
      await chatProvider.forwardIndividually(
        conversationId: target.id,
        messages: messages,
      );
    }
    onDone();
    if (!context.mounted) return;
    await _alert(
      context,
      '转发成功',
      '已将 ${messages.length} 条消息${merge ? '（合并）' : ''}转发到「${target.characterName}」',
    );
  }

  /// 目标会话选择器（排除当前会话）
  static Future<Conversation?> pickTargetConversation(
    BuildContext context,
    String excludeId,
  ) {
    final chatProvider = context.read<ChatProvider>();
    final candidates = chatProvider.conversations
        .where((c) => c.id != excludeId)
        .toList();
    if (candidates.isEmpty) {
      return _alert(context, '提示', '暂无可转发的聊天，请先创建其他聊天')
          .then((_) => null);
    }
    return showCupertinoModalPopup<Conversation>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(8),
          height: min(360.0, candidates.length * 56.0 + 96.0),
          decoration: BoxDecoration(
            color: context.listBgColor,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              const Text(
                '选择转发到',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: candidates.length,
                  itemBuilder: (_, i) {
                    final c = candidates[i];
                    return CupertinoListTile(
                      title: Text(c.characterName),
                      onTap: () => Navigator.pop(ctx, c),
                    );
                  },
                ),
              ),
              CupertinoButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _alert(
    BuildContext context,
    String title,
    String message,
  ) {
    return showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
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
}
