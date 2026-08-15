import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 聊天设置：上下文条数、使用的模型、自动压缩、角色记忆池
class ChatSettingsProvider extends ChangeNotifier {
  static const _contextKey = 'chat_context_count';
  static const _modelKey = 'chat_selected_model';
  static const _compressKey = 'chat_compress_enabled';
  static const _compressThresholdKey = 'chat_compress_threshold';
  static const _momentMemoryKey = 'chat_moment_memory_count';
  static const _memoryPoolDisabledKey = 'chat_memory_pool_disabled_sections';

  /// 携带上下文条数，0 表示无限制（携带全部记录）
  int _contextCount = 10;
  String? _selectedModelId;
  /// 自动压缩会话（无限制上下文时自动开启；达到模型上下文阈值触发压缩）
  bool _enableCompression = false;
  /// 压缩触发阈值（0.0~1.0，默认 0.7 即 70%）
  double _compressThreshold = 0.7;
  /// 记忆池中「朋友圈记忆」条数：每个角色最近 N 条朋友圈贴文（含全部回复），
  /// 0 表示记忆池不拼入朋友圈内容（默认 3 条）。
  int _momentMemoryCount = 3;

  /// 记忆池按角色停用的来源（key=角色 id，value=停用的来源标题集合，
  /// 标题见 MemoryPoolBuilder 的 kPrivateSectionTitle 等常量）。
  Map<String, Set<String>> _disabledPoolSections = {};

  int get contextCount => _contextCount;
  String? get selectedModelId => _selectedModelId;
  bool get enableCompression => _enableCompression;
  double get compressThreshold => _compressThreshold;
  int get momentMemoryCount => _momentMemoryCount;

  /// 该角色记忆池中已停用的来源标题集合（停用后不拼入提示词）
  Set<String> disabledPoolSectionsFor(String characterId) =>
      _disabledPoolSections[characterId] ?? const {};

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
    _momentMemoryCount = prefs.getInt(_momentMemoryKey) ?? 3;
    if (_momentMemoryCount < 0) _momentMemoryCount = 0;
    final raw = prefs.getString(_memoryPoolDisabledKey);
    _disabledPoolSections = {};
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _disabledPoolSections = decoded.map((k, v) =>
            MapEntry(k, Set<String>.from((v as List).cast<String>())));
      } catch (_) {
        _disabledPoolSections = {};
      }
    }
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

  /// 设置记忆池中「朋友圈记忆」条数（0 = 记忆池不拼入朋友圈内容）
  Future<void> setMomentMemoryCount(int count) async {
    _momentMemoryCount = count < 0 ? 0 : count;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_momentMemoryKey, _momentMemoryCount);
  }

  /// 设置角色记忆池某来源（标题见 MemoryPoolBuilder 常量）的启停。
  /// [enabled] 为 false 时该角色拼接提示词时将跳过该来源。
  Future<void> setPoolSectionEnabled(
    String characterId,
    String sectionTitle,
    bool enabled,
  ) async {
    final set = Set<String>.from(
      _disabledPoolSections[characterId] ?? const <String>{},
    );
    if (enabled) {
      set.remove(sectionTitle);
    } else {
      set.add(sectionTitle);
    }
    if (set.isEmpty) {
      _disabledPoolSections.remove(characterId);
    } else {
      _disabledPoolSections[characterId] = set;
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_memoryPoolDisabledKey, jsonEncode(_disabledPoolSections));
  }
}
