import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 聊天设置：上下文条数、使用的模型、自动压缩
class ChatSettingsProvider extends ChangeNotifier {
  static const _contextKey = 'chat_context_count';
  static const _modelKey = 'chat_selected_model';
  static const _compressKey = 'chat_compress_enabled';
  static const _compressThresholdKey = 'chat_compress_threshold';

  /// 携带上下文条数，0 表示无限制（携带全部记录）
  int _contextCount = 10;
  String? _selectedModelId;
  /// 自动压缩会话（无限制上下文时自动开启；达到模型上下文阈值触发压缩）
  bool _enableCompression = false;
  /// 压缩触发阈值（0.0~1.0，默认 0.7 即 70%）
  double _compressThreshold = 0.7;

  int get contextCount => _contextCount;
  String? get selectedModelId => _selectedModelId;
  bool get enableCompression => _enableCompression;
  double get compressThreshold => _compressThreshold;

  /// 是否为无限制上下文
  bool get isUnlimitedContext => _contextCount == 0;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _contextCount = prefs.getInt(_contextKey) ?? 10;
    if (_contextCount < 0) _contextCount = 0;
    _selectedModelId = prefs.getString(_modelKey);
    _enableCompression = prefs.getBool(_compressKey) ?? false;
    _compressThreshold = prefs.getDouble(_compressThresholdKey) ?? 0.7;
    if (_compressThreshold <= 0 || _compressThreshold > 1) _compressThreshold = 0.7;
    notifyListeners();
  }

  /// 设置上下文条数；传 0 表示无限制，此时自动开启压缩会话
  Future<void> setContextCount(int count) async {
    _contextCount = count < 0 ? 0 : count;
    if (_contextCount == 0) {
      // 无限制上下文时自动开启压缩会话（到达 70% 阈值自动压缩）
      _enableCompression = true;
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_contextKey, _contextCount);
    await prefs.setBool(_compressKey, _enableCompression);
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

  Future<void> setEnableCompression(bool value) async {
    _enableCompression = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_compressKey, value);
  }

  /// 设置压缩触发阈值（0.0~1.0）
  Future<void> setCompressThreshold(double value) async {
    _compressThreshold = value.clamp(0.0, 1.0);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_compressThresholdKey, _compressThreshold);
  }
}
