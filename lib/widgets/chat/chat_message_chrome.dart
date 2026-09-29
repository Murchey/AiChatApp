import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../models/message.dart';
import '../../providers/chat_settings_provider.dart';

String formatThinkingDuration(int ms) {
  if (ms < 1000) return '${ms}ms';
  final s = ms / 1000;
  return s >= 10 ? '${s.toStringAsFixed(0)}s' : '${s.toStringAsFixed(1)}s';
}

/// 角色气泡下方的思考时长标签（不入正文）
class ThinkingDurationLabel extends StatelessWidget {
  final Message message;

  const ThinkingDurationLabel({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    if (message.isFromUser) return const SizedBox.shrink();
    final duration = message.reasoningDurationMs;
    if (duration == null) return const SizedBox.shrink();
    return Consumer<ChatSettingsProvider>(
      builder: (context, settings, _) {
        if (!settings.showThinkingDuration) return const SizedBox.shrink();
        return Padding(
          padding:
              const EdgeInsets.only(top: 0, bottom: 6, left: 60, right: 48),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: context.textSecondaryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '思考 ${formatThinkingDuration(duration)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.textSecondaryColor,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 消息时间标签（列表内居中灰底胶囊）
class ChatTimeLabel extends StatelessWidget {
  final DateTime time;

  const ChatTimeLabel({super.key, required this.time});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(time.year, time.month, time.day);
    String text;
    if (day == today) {
      text = DateFormat('HH:mm').format(time);
    } else if (day.year == now.year) {
      text = DateFormat('M月d日 HH:mm').format(time);
    } else {
      text = DateFormat('yyyy年M月d日 HH:mm').format(time);
    }
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: context.textSecondaryColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: context.textSecondaryColor,
          ),
        ),
      ),
    );
  }
}
