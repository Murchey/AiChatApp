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

  /// 会话压缩的 System Prompt：将较早的聊天记录压缩为一段摘要
  static const String kCompressSystemPrompt = '你是一个对话压缩助手。请将以下聊天记录压缩为一段简洁连贯的中文摘要，'
      '保留关键信息：用户的身份与偏好、对方（角色）的人设特征、重要话题与结论、未完成的事项。'
      '摘要不超过 300 字，直接输出摘要内容，不要任何前缀或解释。';

  /// 会话压缩：将较早的历史消息交给压缩模型生成一段摘要文本。
  ///
  /// [historyMessages] 为待压缩的 user/assistant 消息列表。
  /// 压缩失败（网络/API 异常）时抛出 [LLMException] 等异常，由调用方决定是否忽略。
  static Future<String> compressHistory({
    required ApiModel model,
    required List<Map<String, String>> historyMessages,
  }) async {
    final raw = await fetchCompletion(
      model: model,
      messages: [
        {'role': 'system', 'content': kCompressSystemPrompt},
        ...historyMessages,
      ],
      temperature: 0.3,
      maxTokens: 800,
    );
    return raw.trim();
  }

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
    List<Map<String, Object>> historyMessages = const [],
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

  /// 发送图片消息：以 OpenAI 兼容的视觉消息格式，把用户选择的图片
  /// （转 base64 data URL）连同输出指令作为最后一条 user 消息发给模型，
  /// 让角色"看到"图片后按 JSON 数组格式回复。
  ///
  /// [historyMessages] 为最近的文本对话历史（不含本图片），
  /// [outputInstruction] 复用普通文本的格式强指令。
  /// 图片读取失败时抛出 [LLMException]（可读提示）。
  static Future<List<String>> generateVisionReply({
    required ApiModel model,
    required String systemPrompt,
    required List<Map<String, Object>> historyMessages,
    required String imagePath,
    required String outputInstruction,
  }) async {
    String base64;
    try {
      final bytes = await File(imagePath).readAsBytes();
      base64 = base64Encode(bytes);
    } catch (_) {
      throw const LLMException('无法读取图片，请重新选择图片后重试');
    }
    final raw = await fetchCompletion(
      model: model,
      messages: [
        {'role': 'system', 'content': systemPrompt},
        ...historyMessages,
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': outputInstruction.trim()},
            {
              'type': 'image_url',
              'image_url': {
                'url': 'data:${_imageMime(imagePath)};base64,$base64',
              },
            },
          ],
        },
      ],
      temperature: 0.9,
      maxTokens: 512,
    );
    debugPrint('[LLMService] 模型原始响应: $raw');
    final result = parseMessages(raw);
    debugPrint('[LLMService] 解析结果(${result.length}条): $result');
    return result;
  }

  /// 按文件扩展名推断图片 MIME（OpenAI 视觉格式要求 data URL 带类型）
  static String _imageMime(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'image/jpeg';
    }
  }

  /// 调用对话补全 API，返回原始回复文本。失败抛出 [LLMException]。
  ///
  /// [messages] 的 content 既可以是字符串（普通文本消息），
  /// 也可以是 OpenAI 兼容的多模态 part 数组（[{type:text},{type:image_url}]），
  /// 由 jsonEncode 直接序列化。
  static Future<String> fetchCompletion({
    required ApiModel model,
    required List<Map<String, Object>> messages,
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
          throw const LLMException('API 返回内容为空，请重新点击对话完成按钮');
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

  /// 自动检测模型的上下文长度（token）。
  ///
  /// 1. 优先请求 `GET {base}/models`，从服务商返回中解析上下文字段
  ///   （如 OpenRouter 的 `context_length`、部分供应商的 `context_window` /
  ///   `max_model_len` / `max_tokens`）；
  /// 2. 接口不提供或未实现时，按模型名启发式返回常见值；
  /// 3. 两者都无法确定时返回 null，由调用方保留原值。
  static Future<int?> detectContextLength(ApiModel model) async {
    // 1. 请求 GET /models
    var base = model.baseUrl.trim().isNotEmpty
        ? model.baseUrl.trim()
        : defaultBaseUrl;
    base = base.replaceAll(RegExp(r'/+$'), '');
    if (base.endsWith('/chat/completions')) {
      base = base.substring(0, base.length - '/chat/completions'.length);
    }
    final url = '$base/models';

    final client = HttpClient();
    try {
      final request = await client
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 15));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (model.apiKey.isNotEmpty) {
        request.headers
            .set(HttpHeaders.authorizationHeader, 'Bearer ${model.apiKey}');
      }
      final response =
          await request.close().timeout(const Duration(seconds: 30));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode == 200) {
        final found = _parseContextFromModelsResponse(body, model.modelName);
        if (found != null) return found;
      } else {
        debugPrint('[LLMService] /models 返回 HTTP ${response.statusCode}，改用启发式');
      }
    } catch (e) {
      debugPrint('[LLMService] 请求 /models 失败: $e，改用启发式');
    } finally {
      client.close(force: true);
    }

    // 2. 模型名启发式
    return _heuristicContextLength(model.modelName);
  }

  /// 从 GET /models 的响应中解析与 [modelName] 匹配的模型上下文长度。
  /// 解析不到返回 null。
  static int? _parseContextFromModelsResponse(String body, String modelName) {
    try {
      final decoded = jsonDecode(body);
      final data = decoded is Map<String, dynamic> ? decoded['data'] : null;
      if (data is! List || data.isEmpty) return null;

      final target = modelName.toLowerCase();
      Map<String, dynamic>? best;
      var bestScore = -1;
      for (final item in data) {
        if (item is! Map<String, dynamic>) continue;
        final id = (item['id'] as String? ?? '').toLowerCase();
        // 匹配分：完全相等最高，其次是配置名是 id 的子串（兼容 OpenRouter 的 provider/model），再其次 id 是配置名的子串
        var score = -1;
        if (id.isNotEmpty && id == target) {
          score = 3;
        } else if (id.isNotEmpty && id.contains(target)) {
          score = 2;
        } else if (target.isNotEmpty && target.contains(id)) {
          score = 1;
        }
        if (score > bestScore) {
          bestScore = score;
          best = item;
        }
      }
      // 匹配到模型后从常见字段取值
      if (best != null && bestScore > 0) {
        final length = _readContextField(best);
        if (length != null) return length;
      }
      // 列表只有一个模型（部分供应商 /models 仅返回当前模型）且未匹配到时直接取该条
      if (data.length == 1 && data.first is Map<String, dynamic>) {
        final length = _readContextField(data.first as Map<String, dynamic>);
        if (length != null) return length;
      }
    } catch (_) {}
    return null;
  }

  /// 从单个模型条目中读取上下文长度字段
  static int? _readContextField(Map<String, dynamic> item) {
    for (final key in [
      'context_length',
      'context_window',
      'max_model_len',
      'max_tokens',
    ]) {
      final v = item[key];
      if (v is int && v > 0) return v;
      if (v is String) {
        final n = int.tryParse(v.trim());
        if (n != null && n > 0) return n;
      }
    }
    return null;
  }

  /// 常见模型上下文长度的启发式表（按模型名子串匹配，靠前的优先）
  static const List<(String, int)> _contextHeuristics = [
    ('gemini', 1048576),
    ('claude', 200000),
    ('deepseek', 65536),
    ('gpt-4o', 128000),
    ('gpt-4-turbo', 128000),
    ('gpt-4', 8192),
    ('gpt-3.5', 16385),
    ('glm', 128000),
    ('moonshot', 128000),
    ('kimi', 128000),
    ('qwen-long', 10000000),
    ('qwen', 32768),
    ('doubao', 65536),
    ('minimax', 24576),
    ('mistral', 32768),
    ('llama', 32768),
    ('yi-', 32768),
    ('baichuan', 32768),
    ('gemma', 8192),
    ('spark', 8192),
    ('ernie', 8192),
  ];

  static int? _heuristicContextLength(String modelName) {
    final name = modelName.toLowerCase();
    if (name.isEmpty) return null;
    for (final (key, value) in _contextHeuristics) {
      if (name.contains(key)) return value;
    }
    return null;
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
