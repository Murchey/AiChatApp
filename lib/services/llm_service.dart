import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../providers/api_provider.dart';

/// 主动消息系统 - LLM 服务层
///
/// 封装 API 调用与响应容错解析：
/// - temperature 0.8~1.0，提升回复多样性
/// - 支持 response_format 强制 JSON 输出（模型不支持时解析兜底处理）
/// - 解析失败时优先正则提取数组，再退回默认兜底消息
class LLMService {
  static const String defaultBaseUrl = 'https://api.deepseek.com';
  static const List<String> _fallbackMessages = ['（网络开小差了，等下再聊）'];

  /// API 调用异常（无 Key / 网络 / 非 200 等），带可读提示信息
  static String describeException(Object error) {
    if (error is LLMException) return error.message;
    if (error is TimeoutException) return '请求超时，请检查网络后重试';
    if (error is SocketException || error is HandshakeException) {
      return '网络连接失败，请检查网络与 API 地址';
    }
    return '请求出错：$error';
  }

  /// 请求"角色主动发消息/回复"，返回解析后的消息数组（可能为空数组）。
  ///
  /// [historyMessages] 为最近的对话历史（user/assistant 交替），
  /// [outputInstruction] 为"输出格式"强指令，作为最后一条 user 消息追加，
  /// 让模型针对用户的消息分条回复且遵守 JSON 数组格式。
  /// 不使用 response_format 强制 JSON（DeepSeek json_object 模式官方承认
  /// 有概率返回空 content），改为 prompt 约束 + [parseMessages] 容错解析。
  /// API 层失败时抛出 [LLMException]；响应解析失败时返回兜底消息。
  static Future<List<String>> generateMessages({
    required ApiModel model,
    required String systemPrompt,
    List<Map<String, String>> historyMessages = const [],
    String outputInstruction = '',
  }) async {
    final raw = await fetchCompletion(
      model: model,
      messages: [
        {'role': 'system', 'content': systemPrompt},
        ...historyMessages,
        if (outputInstruction.trim().isNotEmpty)
          {'role': 'user', 'content': outputInstruction.trim()},
      ],
      temperature: 0.9,
      maxTokens: 512,
    );
    debugPrint('[LLMService] 模型原始响应: $raw');
    final result = parseMessages(raw);
    debugPrint('[LLMService] 解析结果(${result.length}条): $result');
    return result;
  }

  /// 调用对话补全 API，返回原始回复文本。失败抛出 [LLMException]。
  static Future<String> fetchCompletion({
    required ApiModel model,
    required List<Map<String, String>> messages,
    double temperature = 0.9,
    int maxTokens = 512,
    bool jsonMode = false,
  }) async {
    if (model.modelName.isEmpty) {
      throw const LLMException('所选模型未填写模型名称，请到「API 设置」中检查');
    }
    if (model.apiKey.isEmpty) {
      throw const LLMException('所选模型未配置 API Key，请到「API 设置」中填写');
    }

    // 拼接请求地址：baseUrl 留空使用官方地址，兼容结尾 /v1 或 /chat/completions
    var base = model.baseUrl.trim().isNotEmpty
        ? model.baseUrl.trim()
        : defaultBaseUrl;
    base = base.replaceAll(RegExp(r'/+$'), '');
    final url = base.endsWith('/chat/completions') ? base : '$base/chat/completions';

    final client = HttpClient();
    try {
      final request = await client
          .postUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      request.headers
          .set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers
          .set(HttpHeaders.authorizationHeader, 'Bearer ${model.apiKey}');
      request.add(utf8.encode(jsonEncode({
        'model': model.modelName,
        'messages': messages,
        'stream': false,
        'max_tokens': maxTokens,
        'temperature': temperature,
        if (jsonMode) 'response_format': {'type': 'json_object'},
      })));

      final response =
          await request.close().timeout(const Duration(seconds: 60));
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        final choices = decoded['choices'] as List<dynamic>? ?? const [];
        if (choices.isEmpty) {
          throw const LLMException('API 返回异常：未包含任何回复内容');
        }
        final message =
            (choices.first as Map<String, dynamic>)['message']
                as Map<String, dynamic>?;
        final content = message?['content'] as String? ?? '';
        if (content.trim().isEmpty) {
          throw const LLMException('API 返回内容为空');
        }
        return content;
      }

      // 非 200：尽量解析官方错误信息 {"error":{"message":...}}
      var errorMessage = 'HTTP ${response.statusCode}';
      try {
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        final err = decoded['error'] as Map<String, dynamic>?;
        final msg = err?['message'];
        if (msg != null) errorMessage = '$msg';
      } catch (_) {}
      throw LLMException('API 请求失败：$errorMessage');
    } finally {
      client.close(force: true);
    }
  }

  /// 功能检测：测试当前模型是否支持图片（多模态）发送。
  ///
  /// 以 OpenAI 兼容的视觉消息格式发送一个 1x1 透明 PNG：
  /// - HTTP 200 → 视为支持图片，可开启相册/拍照
  /// - 其他状态码 → 视为不支持（或 API 拒绝图片内容）
  /// 网络/鉴权等异常向上抛出（LLMException / SocketException），由调用方提示。
  static Future<bool> testImageSupport(ApiModel model) async {
    if (model.modelName.isEmpty) {
      throw const LLMException('所选模型未填写模型名称，请到「API 设置」中检查');
    }
    if (model.apiKey.isEmpty) {
      throw const LLMException('所选模型未配置 API Key，请到「API 设置」中填写');
    }

    var base = model.baseUrl.trim().isNotEmpty
        ? model.baseUrl.trim()
        : defaultBaseUrl;
    base = base.replaceAll(RegExp(r'/+$'), '');
    final url =
        base.endsWith('/chat/completions') ? base : '$base/chat/completions';

    // 1x1 透明 PNG（极小测试图片）
    const tinyPngBase64 =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

    final client = HttpClient();
    try {
      final request = await client
          .postUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      request.headers
          .set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers
          .set(HttpHeaders.authorizationHeader, 'Bearer ${model.apiKey}');
      request.add(utf8.encode(jsonEncode({
        'model': model.modelName,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': '请描述这张图片的内容（功能检测）'},
              {
                'type': 'image_url',
                'image_url': {'url': 'data:image/png;base64,$tinyPngBase64'},
              },
            ],
          },
        ],
        'stream': false,
        'max_tokens': 16,
        'temperature': 0,
      })));

      final response =
          await request.close().timeout(const Duration(seconds: 60));
      await response.transform(utf8.decoder).join();
      debugPrint('[LLMService] 图片功能检测 HTTP ${response.statusCode}');
      return response.statusCode == 200;
    } finally {
      client.close(force: true);
    }
  }

  /// 容错解析 LLM 返回的消息数组：
  /// 1. 直接 JSON.parse
  /// 2. 失败则用正则提取 `[...]` 片段再解析（LLM 偶尔带 ```json 标签或对象包裹）
  /// 3. 仍失败时：若原文是句人话（非 JSON），直接作为单条消息返回；否则用兜底消息
  static List<String> parseMessages(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      debugPrint('[LLMService] 响应为空，使用兜底消息');
      return List.of(_fallbackMessages);
    }

    // 1. 直接解析
    final direct = _tryParse(trimmed);
    if (direct != null) return direct;

    // 2. 正则提取 [...] 片段
    final match = RegExp(r'\[(.*?)\]', dotAll: true).firstMatch(trimmed);
    if (match != null) {
      final extracted = _tryParse(match.group(0)!);
      if (extracted != null) return extracted;
    }

    // 3. 模型未按 JSON 输出：清洗后按换行拆分为多条消息，避免"点击后完全无反应"。
    //    即使模型输出的是长段文本，也要展示出来，而不是直接退回兜底消息。
    final cleaned = _cleanSingleMessage(trimmed);
    var fallback = cleaned
        .split(RegExp(r'\r?\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    // 若整段是单条长文本（模型把多条消息拼成一段），再按中文/英文句读切分，
    // 尽量还原"分条"体验，而不是一整段糊在一条气泡里。
    if (fallback.length == 1 && fallback.first.length > 30) {
      fallback = fallback.first
          .split(RegExp(r'(?<=[。！？!?；;])'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (fallback.isNotEmpty) {
      return fallback;
    }

    debugPrint('[LLMService] 无法解析为 JSON 数组，原文：$trimmed');
    return List.of(_fallbackMessages);
  }

  /// 清洗单条文本消息：去掉 ```json 代码块包裹与首尾引号
  static String _cleanSingleMessage(String text) {
    var t = text
        .replaceAll(RegExp(r'```(json)?', caseSensitive: false), '')
        .trim();
    if (t.startsWith('"') && t.endsWith('"') && t.length >= 2) {
      t = t.substring(1, t.length - 1);
    }
    return t.trim();
  }

  static List<String>? _tryParse(String text) {
    try {
      final decoded = jsonDecode(text);
      final rawList = decoded is List
          ? decoded
          : decoded is Map ? decoded['messages'] : null;
      if (rawList is List) {
        final list = rawList
            .whereType<String>()
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        return list;
      }
    } catch (_) {
      // 解析失败，继续下一级兜底
    }
    return null;
  }
}

/// LLM 服务异常
class LLMException implements Exception {
  final String message;
  const LLMException(this.message);

  @override
  String toString() => message;
}
