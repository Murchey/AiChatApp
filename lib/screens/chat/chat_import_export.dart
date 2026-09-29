import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../providers/chat_provider.dart';
import '../../services/chat_records_service.dart';
import '../../utils/file_picker_helper.dart';

/// 会话聊天记录导入 / 导出（zip：chat.json + 图片/文件）。
class ChatImportExport {
  ChatImportExport._();

  /// 导出当前会话为 zip，由用户选择保存位置。
  static Future<void> exportChat(
    BuildContext context, {
    required String conversationId,
    required String characterName,
  }) async {
    final messages =
        context.read<ChatProvider>().getMessages(conversationId);
    if (messages.isEmpty) {
      await _alert(context, '提示', '暂无聊天记录可导出');
      return;
    }

    final includeReasoning = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('导出聊天记录'),
        content: const Text('是否将 AI 思考过程一并写入导出文件？'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('不含思考'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('包含思考'),
          ),
        ],
      ),
    );
    if (includeReasoning == null) return;

    try {
      final bytes = await ChatRecordsService.buildExportZip(
        characterName: characterName,
        messages: messages,
        includeReasoning: includeReasoning,
      );
      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final fileName = '${characterName}_聊天记录_'
          '${now.year}${two(now.month)}${two(now.day)}_'
          '${two(now.hour)}${two(now.minute)}${two(now.second)}.zip';
      final savedName = await FilePickerHelper.saveFile(
        suggestedName: fileName,
        mimeType: 'application/zip',
        bytes: bytes,
      );
      if (savedName == null) return;
      if (!context.mounted) return;
      await _alert(
        context,
        '导出成功',
        '已将 ${messages.length} 条聊天记录（含聊天中的图片/文件）保存为 zip 文件：$savedName',
      );
    } catch (e) {
      if (!context.mounted) return;
      await _alert(context, '导出失败', '打包聊天记录时出错：$e');
    }
  }

  /// 从 zip 导入聊天记录到 [conversationId]。
  /// [onImported] 导入成功后回调（如滚到底部）。
  static Future<void> importChat(
    BuildContext context, {
    required String conversationId,
    VoidCallback? onImported,
  }) async {
    try {
      final picked = await FilePickerHelper.pickFile();
      if (picked == null) return;
      if (!picked.name.toLowerCase().endsWith('.zip')) {
        if (!context.mounted) return;
        await _alert(context, '导入失败', '请选择聊天记录 zip 文件');
        return;
      }
      if (!context.mounted) return;
      final chatProvider = context.read<ChatProvider>();
      final messages = await ChatRecordsService.importZip(
        zipPath: picked.path,
        conversationId: conversationId,
      );
      if (messages.isEmpty) {
        if (!context.mounted) return;
        await _alert(context, '导入失败', '压缩包中没有可导入的消息');
        return;
      }
      await chatProvider.importMessages(
        conversationId: conversationId,
        messages: messages,
      );
      onImported?.call();
      if (!context.mounted) return;
      await _alert(
        context,
        '导入成功',
        '已将 ${messages.length} 条聊天记录导入到当前会话（${picked.name}）',
      );
    } catch (e) {
      if (!context.mounted) return;
      await _alert(context, '导入失败', '$e');
    }
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
