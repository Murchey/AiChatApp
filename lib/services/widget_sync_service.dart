import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WidgetSyncService {
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
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('${_tokenKey}_token_total', total);
      await prefs.setInt('${_tokenKey}_token_sent', sent);
      await prefs.setInt('${_tokenKey}_token_received', received);
      await prefs.setInt('${_tokenKey}_token_private', privateChat);
      await prefs.setInt('${_tokenKey}_token_group', groupChat);
      await prefs.setInt('${_tokenKey}_token_moment', moment);
      await prefs.setInt('${_tokenKey}_token_last_update', DateTime.now().millisecondsSinceEpoch);
      debugPrint('[WidgetSync] Token 数据已同步');
      
      // 通知 Android 端更新小组件
      await _notifyWidgetUpdate();
    } catch (e) {
      debugPrint('[WidgetSync] Token 同步失败: $e');
    }
  }
  
  static Future<void> syncConversations(List<Map<String, dynamic>> conversations) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(conversations.take(10).toList());
      await prefs.setString(_convKey, jsonString);
      await prefs.setInt('${_convKey}_last_update', DateTime.now().millisecondsSinceEpoch);
      debugPrint('[WidgetSync] 会话数据已同步，共 ${conversations.length} 条');
      
      // 通知 Android 端更新小组件
      await _notifyWidgetUpdate();
    } catch (e) {
      debugPrint('[WidgetSync] 会话同步失败: $e');
    }
  }
  
  /// 通知 Android 端更新小组件
  static Future<void> _notifyWidgetUpdate() async {
    try {
      await _channel.invokeMethod('updateWidgets');
      debugPrint('[WidgetSync] 已通知 Android 更新小组件');
    } catch (e) {
      debugPrint('[WidgetSync] 通知更新失败: $e');
    }
  }
}