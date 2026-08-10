import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 聊天设置：上下文条数、使用的模型
class ChatSettingsProvider extends ChangeNotifier {
  static const _contextKey = 'chat_context_count';
  static const _modelKey = 'chat_selected_model';

  int _contextCount = 10; // 默认携带最近 10 条消息作为上下文
  String? _selectedModelId;

  int get contextCount => _contextCount;
  String? get selectedModelId => _selectedModelId;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _contextCount = prefs.getInt(_contextKey) ?? 10;
    _selectedModelId = prefs.getString(_modelKey);
    notifyListeners();
  }

  Future<void> setContextCount(int count) async {
    _contextCount = count;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_contextKey, count);
  }

  Future<void> setSelectedModel(String? modelId) async {
    _selectedModelId = modelId;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (modelId == null) {
      await prefs.remove(_modelKey);
    } else {
      await prefs.setString(_modelKey, modelId);
    }
  }
}
