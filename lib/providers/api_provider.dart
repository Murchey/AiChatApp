import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../services/llm_service.dart';

/// API 模型配置
class ApiModel {
  final String id;
  final String displayName; // 展示名称（界面显示）
  final String modelName; // 模型名称（API 调用使用）
  final String baseUrl; // API 请求地址
  final String apiKey; // API Key
  final int contextLength; // 模型上下文长度（token），用于会话压缩 70% 阈值

  const ApiModel({
    required this.id,
    required this.displayName,
    required this.modelName,
    this.baseUrl = '',
    this.apiKey = '',
    this.contextLength = 8000,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'display_name': displayName,
        'model_name': modelName,
        'base_url': baseUrl,
        'api_key': apiKey,
        'context_length': contextLength,
      };

  factory ApiModel.fromJson(Map<String, dynamic> json) => ApiModel(
        id: json['id'] as String? ?? '',
        displayName: json['display_name'] as String? ?? '',
        modelName: json['model_name'] as String? ?? '',
        baseUrl: json['base_url'] as String? ?? '',
        apiKey: json['api_key'] as String? ?? '',
        contextLength: json['context_length'] as int? ?? 8000,
      );

  ApiModel copyWith({
    String? displayName,
    String? modelName,
    String? baseUrl,
    String? apiKey,
    int? contextLength,
  }) {
    return ApiModel(
      id: id,
      displayName: displayName ?? this.displayName,
      modelName: modelName ?? this.modelName,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      contextLength: contextLength ?? this.contextLength,
    );
  }
}

/// 管理用户配置的 API 模型列表（持久化到本地）
class ApiProvider extends ChangeNotifier {
  static const _storageKey = 'api_models_v1';
  static const _compressModelKey = 'api_compress_model';
  List<ApiModel> _models = [];
  String? _compressionModelId; // 会话压缩专用模型（null 表示跟随聊天模型）

  List<ApiModel> get models => List.unmodifiable(_models);

  String? get compressionModelId => _compressionModelId;

  ApiModel? getModelById(String? id) {
    if (id == null) return null;
    try {
      return _models.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_storageKey);
    if (stored != null) {
      try {
        final list = jsonDecode(stored) as List<dynamic>;
        _models = list
            .map((e) => ApiModel.fromJson(e as Map<String, dynamic>))
            .toList();
        // 自动迁移：修正已保存模型
        // 1. deepseek-chat / deepseek-reasoner 已于 2026-07-24 下线，统一改为 deepseek-v4-flash
        // 2. 仍是默认 8000 的模型，用本地注册表里已知的上下文长度修正（低版本保存的新模型
        //    如 deepseek-v4-flash 也能自动获得准确值）
        var migrated = false;
        for (var i = 0; i < _models.length; i++) {
          final m = _models[i];
          var modelName = m.modelName.trim();
          if (modelName == 'deepseek-chat' || modelName == 'deepseek-reasoner') {
            modelName = 'deepseek-v4-flash';
          }
          var contextLength = m.contextLength;
          if (contextLength == 8000) {
            final local = LLMService.localContextLength(modelName);
            if (local != null) contextLength = local;
          }
          if (modelName != m.modelName.trim() ||
              contextLength != m.contextLength) {
            _models[i] = m.copyWith(
              modelName: modelName,
              contextLength: contextLength,
            );
            migrated = true;
          }
        }
        if (migrated) await _persist();
      } catch (_) {
        _models = [];
      }
    }
    _compressionModelId = prefs.getString(_compressModelKey);
    notifyListeners();
  }

  /// 设置会话压缩专用模型（null 表示跟随聊天模型）
  Future<void> setCompressionModel(String? modelId) async {
    _compressionModelId = modelId;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (modelId == null) {
      await prefs.remove(_compressModelKey);
    } else {
      await prefs.setString(_compressModelKey, modelId);
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(_models.map((m) => m.toJson()).toList()),
    );
  }

  Future<void> addModel({
    required String displayName,
    required String modelName,
    String baseUrl = '',
    String apiKey = '',
    int contextLength = 8000,
  }) async {
    _models.add(ApiModel(
      id: const Uuid().v4(),
      displayName: displayName.trim(),
      modelName: modelName.trim(),
      baseUrl: baseUrl.trim(),
      apiKey: apiKey.trim(),
      contextLength: contextLength,
    ));
    notifyListeners();
    await _persist();
  }

  Future<void> updateModel(ApiModel model) async {
    final index = _models.indexWhere((m) => m.id == model.id);
    if (index == -1) return;
    _models[index] = model;
    notifyListeners();
    await _persist();
  }

  Future<void> deleteModel(String id) async {
    _models.removeWhere((m) => m.id == id);
    notifyListeners();
    await _persist();
  }
}
