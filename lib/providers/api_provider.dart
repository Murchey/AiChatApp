import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// API 模型配置
class ApiModel {
  final String id;
  final String displayName; // 展示名称（界面显示）
  final String modelName; // 模型名称（API 调用使用）
  final String baseUrl; // API 请求地址
  final String apiKey; // API Key

  const ApiModel({
    required this.id,
    required this.displayName,
    required this.modelName,
    this.baseUrl = '',
    this.apiKey = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'display_name': displayName,
        'model_name': modelName,
        'base_url': baseUrl,
        'api_key': apiKey,
      };

  factory ApiModel.fromJson(Map<String, dynamic> json) => ApiModel(
        id: json['id'] as String? ?? '',
        displayName: json['display_name'] as String? ?? '',
        modelName: json['model_name'] as String? ?? '',
        baseUrl: json['base_url'] as String? ?? '',
        apiKey: json['api_key'] as String? ?? '',
      );

  ApiModel copyWith({
    String? displayName,
    String? modelName,
    String? baseUrl,
    String? apiKey,
  }) {
    return ApiModel(
      id: id,
      displayName: displayName ?? this.displayName,
      modelName: modelName ?? this.modelName,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
    );
  }
}

/// 管理用户配置的 API 模型列表（持久化到本地）
class ApiProvider extends ChangeNotifier {
  static const _storageKey = 'api_models_v1';
  List<ApiModel> _models = [];

  List<ApiModel> get models => List.unmodifiable(_models);

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
      } catch (_) {
        _models = [];
      }
    }
    notifyListeners();
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
  }) async {
    _models.add(ApiModel(
      id: const Uuid().v4(),
      displayName: displayName.trim(),
      modelName: modelName.trim(),
      baseUrl: baseUrl.trim(),
      apiKey: apiKey.trim(),
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
