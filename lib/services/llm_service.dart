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
      '摘要不超过 600 字，直接输出摘要内容，不要任何前缀或解释。';

  /// 会话压缩：将较早的历史消息交给压缩模型生成一段摘要文本。
  ///
  /// [historyMessages] 为待压缩的 user/assistant 消息列表。
  /// 压缩失败（网络/API 异常）时抛出 [LLMException] 等异常，由调用方决定是否忽略。
  static Future<String> compressHistory({
    required ApiModel model,
    required List<Map<String, String>> historyMessages,
  }) async {
    final result = await fetchCompletion(
      model: model,
      messages: [
        {'role': 'system', 'content': kCompressSystemPrompt},
        ...historyMessages,
      ],
      temperature: 0.3,
      maxTokens: 800,
    );
    return result.content.trim();
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

  /// 聊天会话专用请求：kimi 模型（模型请求名含 kimi，忽略大小写）
  /// 首次请求尝试失败（网络/API 异常）时，第二次把 temperature 改为 1
  /// 再尝试一次（kimi 部分版本对默认温度偶发拒绝/报错），其余模型直接抛错。
  static Future<CompletionResult> _fetchWithKimiFallback({
    required ApiModel model,
    required List<Map<String, Object>> messages,
    required int maxTokens,
    double initialTemperature = 0.9,
  }) async {
    try {
      return await fetchCompletion(
        model: model,
        messages: messages,
        temperature: initialTemperature,
        maxTokens: maxTokens,
      );
    } catch (_) {
      if (model.modelName.toLowerCase().contains('kimi')) {
        debugPrint('[LLMService] ${model.modelName} 首次请求失败，'
            '改用 temperature=1 再次尝试');
        return fetchCompletion(
          model: model,
          messages: messages,
          temperature: 1.0,
          maxTokens: maxTokens,
        );
      }
      rethrow;
    }
  }

  /// 请求"角色主动发消息/回复"，返回解析后的消息数组（可能为空数组）。
  ///
  /// [historyMessages] 为最近的对话历史（user/assistant 交替），
  /// [outputInstruction] 为"输出格式"强指令，作为最后一条 user 消息追加，
  /// 让模型针对用户的消息分条回复且遵守 JSON 数组格式。
  /// 不使用 response_format 强制 JSON（DeepSeek json_object 模式官方承认
  /// 有概率返回空 content），改为 prompt 约束 + [parseMessages] 容错解析。
  /// API 层失败时抛出 [LLMException]；响应解析失败时返回兜底消息。
  static Future<ProactiveResult> generateMessages({
    required ApiModel model,
    required String systemPrompt,
    List<Map<String, Object>> historyMessages = const [],
    String outputInstruction = '',
  }) async {
    final completion = await _fetchWithKimiFallback(
      model: model,
      messages: [
        {'role': 'system', 'content': systemPrompt},
        ...historyMessages,
        if (outputInstruction.trim().isNotEmpty)
          {'role': 'user', 'content': outputInstruction.trim()},
      ],
      maxTokens: 1024,
    );
    final raw = completion.content;
    debugPrint('[LLMService] 模型原始响应: $raw');
    final result = parseMessages(raw);
    debugPrint('[LLMService] 解析结果(${result.length}条): $result');
    return ProactiveResult(result, completion.usage);
  }

  /// 发送图片消息：以 OpenAI 兼容的视觉消息格式，把用户选择的图片
  /// （转 base64 data URL）连同输出指令作为最后一条 user 消息发给模型，
  /// 让角色"看到"图片后按 JSON 数组格式回复。
  ///
  /// [historyMessages] 为最近的文本对话历史（不含本图片），
  /// [outputInstruction] 复用普通文本的格式强指令。
  /// 图片读取失败时抛出 [LLMException]（可读提示）。
  static Future<ProactiveResult> generateVisionReply({
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
    final completion = await _fetchWithKimiFallback(
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
      maxTokens: 1024,
    );
    final raw = completion.content;
    debugPrint('[LLMService] 模型原始响应: $raw');
    final result = parseMessages(raw);
    debugPrint('[LLMService] 解析结果(${result.length}条): $result');
    return ProactiveResult(result, completion.usage);
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

  /// 调用对话补全 API，返回回复内容与真实 token 用量（usage）。
  /// 失败抛出 [LLMException]。
  ///
  /// [messages] 的 content 既可以是字符串（普通文本消息），
  /// 也可以是 OpenAI 兼容的多模态 part 数组（[{type:text},{type:image_url}]），
  /// 由 jsonEncode 直接序列化。
  static Future<CompletionResult> fetchCompletion({
    required ApiModel model,
    required List<Map<String, Object>> messages,
    // null 表示不发送 temperature 字段（部分模型不支持自定义 temperature，
    // 让模型使用自身默认值），从第 5 次朋友圈互动重试起使用
    double? temperature = 0.9,
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

    // 部分模型（快速/推理模型）偶发返回 HTTP 200 但 content 为空，
    // 重发一次请求让模型重新生成，显著降低"API 返回内容为空"的出现频率。
    for (var attempt = 0; attempt < 2; attempt++) {
      final result = await _requestOnce(
        url: url,
        model: model,
        messages: messages,
        temperature: temperature,
        maxTokens: maxTokens,
        jsonMode: jsonMode,
      );
      if (result.content.trim().isNotEmpty) return result;
      debugPrint('[LLMService] 第 ${attempt + 1} 次响应 content 为空，自动重试');
    }
    throw const LLMException('API 返回内容为空，已自动重试一次仍无结果，请稍后重试或检查模型设置');
  }

  /// 发起一次对话补全请求，返回回复内容与真实 token 用量。
  /// 非 200 状态码或网络异常时抛出 [LLMException]。
  static Future<CompletionResult> _requestOnce({
    required String url,
    required ApiModel model,
    required List<Map<String, Object>> messages,
    required double? temperature,
    required int maxTokens,
    required bool jsonMode,
  }) async {
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
        if (temperature != null) 'temperature': temperature,
        if (jsonMode) 'response_format': {'type': 'json_object'},
      })));

      final response =
          await request.close().timeout(const Duration(seconds: 60));
      // 响应头到达后，正文读取同样设置超时，
      // 避免网关慢速传输时界面一直卡在"正在输入"
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        final choices = decoded['choices'] as List<dynamic>? ?? const [];
        if (choices.isEmpty) {
          throw const LLMException('API 返回异常：未包含任何回复内容');
        }
        final message =
            (choices.first as Map<String, dynamic>)['message']
                as Map<String, dynamic>?;
        return CompletionResult(
          message?['content'] as String? ?? '',
          _parseUsage(decoded),
        );
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
  /// 以 OpenAI 兼容的视觉消息格式发送一张测试图片并明确引导回复：
  /// - HTTP 200 且回复内容体现「能看到图片」→ 支持图片
  /// - 回复内容明确表示「看不到/不支持」→ 不支持
  /// - HTTP 非 200（API 拒绝图片内容等）→ 不支持
  /// - 200 但回复无法判定（部分非视觉模型会忽略图片直接回复）→ 按 200 放行
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
              {
                'type': 'text',
                'text': '这是功能检测。请回答：你是否能看到我发送的这张图片？'
                    '能看到请只回复一个字：能。不能看到请只回复两个字：不能。',
              },
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
      final body =
          await response.transform(utf8.decoder).join();
      debugPrint('[LLMService] 图片功能检测 HTTP ${response.statusCode}');
      if (response.statusCode != 200) return false;

      // HTTP 200：结合回复内容判定，避免「模型忽略图片直接回文本」的假阳性
      final reply = _extractReplyText(body);
      if (reply != null) return _judgeVisionByReply(reply) ?? true;
      return true;
    } finally {
      client.close(force: true);
    }
  }

  /// 从 OpenAI 兼容响应中提取回复文本（choices[0].message.content）
  static String? _extractReplyText(String body) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final choices = decoded['choices'] as List<dynamic>? ?? const [];
      if (choices.isEmpty) return null;
      final message = (choices.first as Map<String, dynamic>)['message']
          as Map<String, dynamic>?;
      return message?['content'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// 依据回复内容判定模型是否看到了图片。
  /// 明确否定优先；无关键词（模型忽略图片直接回答文本等）返回 null 由调用方兜底。
  static bool? _judgeVisionByReply(String reply) {
    final t = reply.trim().toLowerCase();
    // 明确否定（优先）：中文为主，兼顾常见英文否定
    const negativePatterns = [
      '不能',
      '看不到',
      '无法',
      '没有看到',
      '没看到',
      '无法识别',
      '不认识',
      '没有图片',
      'cannot see',
      "can't see",
      'can not see',
      'cannot',
      'no image',
    ];
    for (final p in negativePatterns) {
      if (t.contains(p)) return false;
    }
    // 明确肯定
    const positivePatterns = [
      '能看到',
      '可以看到',
      '看得见',
      '能',
      '看到',
      '可以',
      'yes',
      '能看见',
      '是',
    ];
    for (final p in positivePatterns) {
      if (t.contains(p)) return true;
    }
    return null;
  }

  /// 自动检测模型的上下文长度（token）。
  ///
  /// 采用「本地注册表优先 + API 探测兜底」的混合策略：
  /// 1. 本地硬编码注册表精确匹配模型名（即时、离线可用，主流模型无需联网）；
  /// 2. 未命中时按模型名家族启发式返回常见值；
  /// 3. 仍未命中才请求 `GET {base}/models` 探测（如 OpenRouter 的
  ///    `context_length`、部分供应商的 `context_window` / `max_model_len` /
  ///    `max_tokens`），接口不提供则返回 null，由调用方保留原值。
  static Future<int?> detectContextLength(ApiModel model) async {
    // 1. 本地注册表（精确匹配 + 家族启发式），离线可用、无需请求
    final local = localContextLength(model.modelName);
    if (local != null) return local;

    // 2. 请求 GET /models 探测（仅注册表未命中的模型）
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
        debugPrint('[LLMService] /models 返回 HTTP ${response.statusCode}，无法确定上下文长度');
      }
    } catch (e) {
      debugPrint('[LLMService] 请求 /models 失败: $e，无法确定上下文长度');
    } finally {
      client.close(force: true);
    }
    return null;
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

  /// 本地硬编码模型上下文注册表（精确模型名 → 上下文长度 token）。
  ///
  /// 采用「API 探测 + 本地注册表」混合策略：本地注册表优先（即时、离线可用），
  /// 覆盖主流与常见第三方模型；未命中的模型再走 /models 接口探测与家族启发式。
  static const Map<String, int> _exactModelContexts = {
    // OpenAI
    'gpt-4o': 128000,
    'gpt-4o-mini': 128000,
    'gpt-4.1': 1047576,
    'gpt-4.1-mini': 1047576,
    'gpt-4.1-nano': 1047576,
    'gpt-4-turbo': 128000,
    'gpt-4': 8192,
    'gpt-3.5-turbo': 16385,
    'o1': 200000,
    'o1-mini': 128000,
    'o3': 200000,
    'o3-mini': 200000,
    'o4-mini': 200000,
    // Anthropic Claude
    'claude-opus-4': 200000,
    'claude-sonnet-4': 200000,
    'claude-3-7-sonnet': 200000,
    'claude-3-5-sonnet': 200000,
    'claude-3-opus': 200000,
    'claude-3-haiku': 200000,
    // Google Gemini
    'gemini-2.5-pro': 1048576,
    'gemini-2.5-flash': 1048576,
    'gemini-2.5-flash-lite': 1048576,
    'gemini-3-flash-preview': 1048576,
    'gemini-2.0-flash': 1048576,
    'gemini-1.5-pro': 2097152,
    'gemini-1.5-flash': 1048576,
    // DeepSeek（deepseek-chat / deepseek-reasoner 已于 2026-07-24 下线，统一为 V4 系列）
    'deepseek-v4-flash': 1048576,
    'deepseek-v4-pro': 1048576,
    // 旧模型名仍路由到 V4-Flash（非思考/思考模式），保留以兼容老配置
    'deepseek-chat': 1048576,
    'deepseek-reasoner': 1048576,
    // 小米 MiMo
    'mimo-v2.5-pro': 1048576,
    'mimo-v2.5-omni': 1048576,
    'mimo-v2-flash': 57344,
    // xAI Grok
    'grok-4.5': 500000,
    'grok-4.20-reasoning': 2097152,
    'grok-4.20-non-reasoning': 2097152,
    'grok-4-1-fast-reasoning': 2097152,
    'grok-4-1-fast-non-reasoning': 2097152,
    // 通义千问
    'qwen-max': 32768,
    'qwen-plus': 131072,
    'qwen-turbo': 131072,
    'qwen-long': 10000000,
    'qwen-vl-max': 32768,
    // Kimi / Moonshot
    'moonshot-v1-8k': 8192,
    'moonshot-v1-32k': 32768,
    'moonshot-v1-128k': 128000,
    'kimi-k2': 128000,
    // 智谱 GLM
    'glm-4': 128000,
    'glm-4-plus': 128000,
    'glm-4-flash': 128000,
    'glm-4-long': 1000000,
    // 豆包
    'doubao-pro': 65536,
    'doubao-lite': 65536,
    // MiniMax
    'minimax-m2.7': 204800,
    'minimax-m2.7-highspeed': 204800,
    'minimax-m2.5': 204800,
    'minimax-m2.1': 204800,
    'minimax-m1': 1048576,
    'minimax-text-01': 1048576,
    'minimax-abab6.5': 24576,
    // 硅基流动 SiliconCloud（模型名为「组织/模型」格式）
    'qwen/qwen2.5-72b-instruct': 131072,
    'qwen/qwen3-8b': 131072,
    'deepseek-ai/deepseek-v3': 131072,
    'deepseek-ai/deepseek-r1': 131072,
    'thudm/glm-4-9b-0414': 131072,
    // 开源系
    'llama-3.1-405b': 128000,
    'llama-3.1-70b': 128000,
    'llama-3.3-70b': 128000,
    'mistral-large': 128000,
    'mistral-medium': 32768,
    'yi-large': 32768,
  };

  /// 常见模型上下文长度的家族启发式表（按模型名子串匹配，靠前的优先）。
  /// 仅作为注册表精确匹配未命中时的兜底。
  static const List<(String, int)> _contextHeuristics = [
    ('gemini', 1048576),
    ('claude', 200000),
    ('deepseek', 1048576),
    ('grok', 500000),
    ('mimo', 1048576),
    ('gpt-4o', 128000),
    ('gpt-4-turbo', 128000),
    ('gpt-4', 8192),
    ('gpt-3.5', 16385),
    ('o3', 200000),
    ('o1', 200000),
    ('glm', 128000),
    ('moonshot', 128000),
    ('kimi', 128000),
    ('qwen-long', 10000000),
    ('qwen', 32768),
    ('doubao', 65536),
    ('minimax', 204800),
    ('mistral', 32768),
    ('llama', 32768),
    ('yi-', 32768),
    ('baichuan', 32768),
    ('gemma', 8192),
    ('spark', 8192),
    ('ernie', 8192),
  ];

  /// 纯本地（不联网）按模型名查询上下文长度：
  /// 先精确匹配注册表，未命中再用家族启发式兜底。未命中返回 null。
  static int? localContextLength(String modelName) {
    final name = modelName.trim().toLowerCase();
    if (name.isEmpty) return null;
    final exact = _exactModelContexts[name];
    if (exact != null) return exact;
    return _heuristicContextLength(name);
  }

  static int? _heuristicContextLength(String modelName) {
    final name = modelName.toLowerCase();
    if (name.isEmpty) return null;
    for (final (key, value) in _contextHeuristics) {
      if (name.contains(key)) return value;
    }
    return null;
  }

  /// 获取 OpenAI 兼容服务商的可用模型 ID 列表（GET /models）。
  ///
  /// 请求失败或返回为空时抛出 [LLMException]（可读提示）。
  /// 返回结果仅含模型 ID，上下文长度需配合本地注册表 [localContextLength] 补全。
  static Future<List<String>> fetchAvailableModels({
    String baseUrl = '',
    String apiKey = '',
  }) async {
    var base = baseUrl.trim().isNotEmpty ? baseUrl.trim() : defaultBaseUrl;
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
      if (apiKey.isNotEmpty) {
        request.headers
            .set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      }
      final response =
          await request.close().timeout(const Duration(seconds: 30));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw LLMException('获取模型列表失败（HTTP ${response.statusCode}），请检查请求地址与 API Key');
      }
      final ids = _parseModelList(body);
      if (ids.isEmpty) {
        throw const LLMException('接口未返回可用的模型列表');
      }
      return ids;
    } catch (e) {
      if (e is LLMException) rethrow;
      debugPrint('[LLMService] 请求 /models 失败: $e');
      throw LLMException(describeException(e));
    } finally {
      client.close(force: true);
    }
  }

  /// 从 GET /models 响应中解析模型 ID 列表，兼容多种返回格式：
  /// - OpenAI 标准格式：{"data": [{"id": "gpt-4o"}, ...]}
  /// - 部分服务商：{"models": [...]} 或纯数组 ["gpt-4o", ...]
  static List<String> _parseModelList(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final data = decoded['data'] ?? decoded['models'];
        if (data is List) {
          return data
              .map((e) =>
                  e is Map<String, dynamic> ? e['id'] as String? : e as String?)
              .whereType<String>()
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
      } else if (decoded is List) {
        return decoded
            .whereType<String>()
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
    } catch (_) {
      debugPrint('[LLMService] 解析 /models 响应失败: $body');
    }
    return const [];
  }

  /// 本地分词估算一段文本的 token 数（API 未返回 usage 字段时的备用方案）。
  ///
  /// 中文的实际 Token 切分比"两字一 Token"要碎得多：
  /// - 汉字 / 全角字符（中文标点、假名、CJK 扩展等）：1 字 ≈ 2 Token（保守估算，避免低估）
  /// - 其余字符（英文、数字、半角标点、空格、换行）：约 4 字符 ≈ 1 Token
  static int estimateTokens(String text) {
    if (text.isEmpty) return 0;
    var cjk = 0;
    var other = 0;
    for (final rune in text.runes) {
      if (_isCjkRune(rune)) {
        cjk++;
      } else {
        other++;
      }
    }
    return (cjk * 2 + other * 0.25).ceil();
  }

  /// 是否为汉字 / 全角类字符（按 Unicode 区段判断）
  static bool _isCjkRune(int r) =>
      (r >= 0x2E80 && r <= 0x9FFF) || // CJK 部首/扩展 A/统一表意文字、中文标点、假名
      (r >= 0xF900 && r <= 0xFAFF) || // CJK 兼容表意文字
      (r >= 0xFF00 && r <= 0xFFEF); // 全角字符与全角标点

  /// 从对话补全响应中解析 token 用量（usage 字段，可能缺失）。
  /// 单次调用总消耗 = prompt_tokens（系统提示词 + 软件提示词 + 历史 + 本次提问）
  ///               + completion_tokens（AI 思考过程 + 最终回复）。
  static ChatUsage _parseUsage(Map<String, dynamic> decoded) {
    final usage = decoded['usage'];
    if (usage is! Map<String, dynamic>) return const ChatUsage();
    return ChatUsage(
      promptTokens: _usageInt(usage['prompt_tokens']),
      completionTokens: _usageInt(usage['completion_tokens']),
      totalTokens: _usageInt(usage['total_tokens']),
    );
  }

  static int? _usageInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
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

/// 一次对话补全的 token 用量（来自 API 响应 usage 字段；字段缺失为 null）
class ChatUsage {
  final int? promptTokens; // 输入：系统提示词 + 软件提示词 + 历史上下文 + 本次提问
  final int? completionTokens; // 输出：AI 思考过程 + 最终回复
  final int? totalTokens; // prompt + completion

  const ChatUsage({
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
  });

  bool get isEmpty =>
      promptTokens == null && completionTokens == null && totalTokens == null;
}

/// 对话补全结果：回复内容 + 真实 token 用量
class CompletionResult {
  final String content;
  final ChatUsage usage;
  const CompletionResult(this.content, this.usage);
}

/// 角色回复结果：解析出的消息列表 + 本次请求的 token 用量
class ProactiveResult {
  final List<String> messages;
  final ChatUsage usage;
  const ProactiveResult(this.messages, this.usage);
}
