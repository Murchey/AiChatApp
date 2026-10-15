import '../providers/chat_provider.dart';
import '../providers/token_usage_provider.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/platform_support.dart';

class WidgetSyncService {
  /// Explicit refresh reports native errors instead of treating them as success.
  static Future<void> refreshNow(
      TokenUsageProvider token, ChatProvider chat) async {
    if (!PlatformSupport.supportsHomeWidgets) {
      throw UnsupportedError('当前平台不支持小组件');
    }
    int privateChat = 0, groupChat = 0, moment = 0;
    token.allUsages.forEach((id, u) {
      if (id == TokenUsageProvider.kMomentUsageId) {
        moment += u.totalTokens;
      } else if (id.startsWith('group_')) {
        groupChat += u.totalTokens;
      } else {
        privateChat += u.totalTokens;
      }
    });
    final prefs = await SharedPreferences.getInstance();
    for (final e in {
      'total': token.total,
      'sent': token.sentTotal,
      'received': token.receivedTotal,
      'private': privateChat,
      'group': groupChat,
      'moment': moment
    }.entries) {
      if (!await prefs.setInt('widget_data_token_${e.key}', e.value)) {
        throw StateError('小组件数据写入失败');
      }
    }
    await prefs.setInt(
        'widget_data_token_last_update', DateTime.now().millisecondsSinceEpoch);
    await prefs.setString(
        'widget_conversations',
        jsonEncode(chat.conversations
            .take(10)
            .map((c) => {
                  'id': c.id,
                  'character_id': c.characterId,
                  'character_name': c.characterName,
                  'last_message': c.lastMessage,
                  'last_message_time': c.lastMessageTime.millisecondsSinceEpoch,
                  'unread_count': c.unreadCount,
                  'pinned': c.pinned,
                })
            .toList()));
    await prefs.setInt('widget_conversations_last_update',
        DateTime.now().millisecondsSinceEpoch);
    final ok = await _channel.invokeMethod<bool>('updateWidgets');
    if (ok != true) throw StateError('小组件刷新失败');
  }

  static const _tokenKey = 'widget_data';
  static const _convKey = 'widget_conversations';
  static const _channel = MethodChannel('com.aichat.ai_chat/widget');

  static Future<void> syncTokenUsage({
    required int total,
    required int sent,
    required int received,
    required int privateChat,
    required int groupChat,
    required int moment,
  }) async {
    if (!PlatformSupport.supportsHomeWidgets) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('${_tokenKey}_token_total', total);
      await prefs.setInt('${_tokenKey}_token_sent', sent);
      await prefs.setInt('${_tokenKey}_token_received', received);
      await prefs.setInt('${_tokenKey}_token_private', privateChat);
      await prefs.setInt('${_tokenKey}_token_group', groupChat);
      await prefs.setInt('${_tokenKey}_token_moment', moment);
      await prefs.setInt('${_tokenKey}_token_last_update',
          DateTime.now().millisecondsSinceEpoch);
      debugPrint('[WidgetSync] Token 数据已同步');

      // 通知 Android 端更新小组件
      await _notifyWidgetUpdate();
    } catch (e) {
      debugPrint('[WidgetSync] Token 同步失败: $e');
    }
  }

  static Future<void> syncConversations(
      List<Map<String, dynamic>> conversations) async {
    if (!PlatformSupport.supportsHomeWidgets) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(conversations.take(10).toList());
      await prefs.setString(_convKey, jsonString);
      await prefs.setInt(
          '${_convKey}_last_update', DateTime.now().millisecondsSinceEpoch);
      debugPrint('[WidgetSync] 会话数据已同步，共 ${conversations.length} 条');

      // 通知 Android 端更新小组件
      await _notifyWidgetUpdate();
    } catch (e) {
      debugPrint('[WidgetSync] 会话同步失败: $e');
    }
  }

  /// 通知 Android 端更新小组件
  static Future<void> _notifyWidgetUpdate() async {
    if (!PlatformSupport.supportsHomeWidgets) return;
    try {
      await _channel.invokeMethod('updateWidgets');
      debugPrint('[WidgetSync] 已通知 Android 更新小组件');
    } catch (e) {
      debugPrint('[WidgetSync] 通知更新失败: $e');
    }
  }
}
