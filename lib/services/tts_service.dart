import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../providers/api_provider.dart';

enum TtsProtocol { openAi, mimo, minimax, qwen }

/// OpenAI、MiMo、MiniMax 与 Qwen 的非流式语音合成客户端。
///
/// 只负责协议请求与响应解码，返回音频字节；播放与排队由
/// [TtsPlaybackController] 统一管理。
class TtsService {
  TtsService._();

  static Future<void> stop() async {
    // 播放已上收到 TtsPlaybackController；保留方法以免调用方编译失败。
  }

  static TtsProtocol? protocolFor(ApiModel model) {
    final base = model.baseUrl.toLowerCase();
    final name = model.modelName.trim().toLowerCase();
    final isTtsModel = name.contains('tts') ||
        name.startsWith('speech-') ||
        name.contains('minimax-speech');
    if (!isTtsModel) return null;

    if (base.contains('xiaomimimo.com')) {
      return TtsProtocol.mimo;
    }
    if (base.contains('minimax.cn') || base.contains('minimaxi.com')) {
      return TtsProtocol.minimax;
    }
    if (base.contains('dashscope.aliyuncs.com') ||
        base.contains('qianwenaiapi.com')) {
      return TtsProtocol.qwen;
    }
    return TtsProtocol.openAi;
  }

  static bool isSupportedModel(ApiModel model) => protocolFor(model) != null;

  static String speechEndpoint(String baseUrl) {
    var value = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (value.endsWith('/audio/speech')) return value;
    if (value.endsWith('/chat/completions')) {
      value = value.substring(0, value.length - '/chat/completions'.length);
    }
    return '$value/audio/speech';
  }

  static String mimoEndpoint(String baseUrl) {
    var value = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (value.endsWith('/chat/completions')) return value;
    if (value.endsWith('/audio/speech')) {
      value = value.substring(0, value.length - '/audio/speech'.length);
    }
    return '$value/chat/completions';
  }

  static String minimaxEndpoint(String baseUrl) {
    var value = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (value.endsWith('/t2a_v2')) return value;
    if (value.endsWith('/v1')) return '$value/t2a_v2';
    return '$value/v1/t2a_v2';
  }

  static String qwenEndpoint(String baseUrl) {
    final value = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (value
        .endsWith('/api/v1/services/aigc/multimodal-generation/generation')) {
      return value;
    }
    final uri = Uri.parse(value);
    return uri
        .replace(
          path: '/api/v1/services/aigc/multimodal-generation/generation',
          query: null,
          fragment: null,
        )
        .toString();
  }

  static Map<String, dynamic> requestBody({
    required TtsProtocol protocol,
    required ApiModel model,
    required String text,
    String voice = '',
    String instructions = '',
  }) {
    final voiceId = voice.trim();
    final style = instructions.trim();
    switch (protocol) {
      case TtsProtocol.openAi:
        final modelName = model.modelName.trim();
        final supportsInstructions =
            modelName != 'tts-1' && modelName != 'tts-1-hd';
        return {
          'model': modelName,
          'input': text,
          'voice': voiceId.isEmpty ? 'alloy' : voiceId,
          'response_format': 'mp3',
          if (style.isNotEmpty && supportsInstructions) 'instructions': style,
        };
      case TtsProtocol.mimo:
        final isVoiceDesign =
            model.modelName.toLowerCase().contains('voicedesign');
        return {
          'model': model.modelName.trim(),
          'messages': [
            if (style.isNotEmpty) {'role': 'user', 'content': style},
            {'role': 'assistant', 'content': text},
          ],
          'audio': {
            'format': 'wav',
            if (!isVoiceDesign)
              'voice': voiceId.isEmpty ? 'mimo_default' : voiceId,
            if (isVoiceDesign) 'optimize_text_preview': true,
          },
        };
      case TtsProtocol.minimax:
        return {
          'model': model.modelName.trim(),
          'text': text,
          'stream': false,
          'voice_setting': {
            'voice_id': voiceId.isEmpty ? 'male-qn-qingse' : voiceId,
          },
          'audio_setting': {
            'sample_rate': 32000,
            'bitrate': 128000,
            'format': 'mp3',
            'channel': 1,
          },
          'output_format': 'hex',
        };
      case TtsProtocol.qwen:
        final supportsInstructions =
            model.modelName.toLowerCase().contains('instruct');
        return {
          'model': model.modelName.trim(),
          'input': {
            'text': text,
            'voice': voiceId.isEmpty ? 'Cherry' : voiceId,
            'language_type': 'Auto',
            if (style.isNotEmpty && supportsInstructions) 'instructions': style,
          },
        };
    }
  }

  /// 合成语音并返回音频字节与扩展名，不触发播放。
  static Future<TtsAudioData> synthesize({
    required ApiModel model,
    required String text,
    String voice = '',
    String instructions = '',
  }) async {
    if (model.modelName.trim().isEmpty) {
      throw const TtsException('语音模型未填写模型名称');
    }
    if (model.apiKey.trim().isEmpty) {
      throw const TtsException('语音模型未配置 API Key');
    }
    final protocol = protocolFor(model);
    if (protocol == null) {
      throw const TtsException('当前配置不是已支持的 TTS 模型，请检查模型名称与 API 地址。');
    }

    final client = HttpClient();
    try {
      switch (protocol) {
        case TtsProtocol.openAi:
          return await _synthesizeOpenAi(
            client,
            model: model,
            text: text,
            voice: voice,
            instructions: instructions,
          );
        case TtsProtocol.mimo:
          return await _synthesizeMiMo(
            client,
            model: model,
            text: text,
            voice: voice,
            instructions: instructions,
          );
        case TtsProtocol.minimax:
          return await _synthesizeMiniMax(
            client,
            model: model,
            text: text,
            voice: voice,
          );
        case TtsProtocol.qwen:
          return await _synthesizeQwen(
            client,
            model: model,
            text: text,
            voice: voice,
            instructions: instructions,
          );
      }
    } finally {
      client.close(force: true);
    }
  }

  static Future<TtsAudioData> _synthesizeOpenAi(
    HttpClient client, {
    required ApiModel model,
    required String text,
    required String voice,
    required String instructions,
  }) async {
    final base = model.baseUrl.trim().isEmpty
        ? 'https://api.openai.com/v1'
        : model.baseUrl.trim();
    final response = await _postJson(
      client,
      speechEndpoint(base),
      model.apiKey,
      requestBody(
        protocol: TtsProtocol.openAi,
        model: model,
        text: text,
        voice: voice,
        instructions: instructions,
      ),
    );
    return TtsAudioData(response, 'mp3');
  }

  static Future<TtsAudioData> _synthesizeMiMo(
    HttpClient client, {
    required ApiModel model,
    required String text,
    required String voice,
    required String instructions,
  }) async {
    final base = model.baseUrl.trim().isEmpty
        ? 'https://api.xiaomimimo.com/v1'
        : model.baseUrl.trim();
    final response = await _postJson(
      client,
      mimoEndpoint(base),
      model.apiKey,
      requestBody(
        protocol: TtsProtocol.mimo,
        model: model,
        text: text,
        voice: voice,
        instructions: instructions,
      ),
    );
    final json = _decodeJsonResponse(response, 'MiMo TTS');
    return TtsAudioData(decodeMiMoAudio(json), 'wav');
  }

  static Future<TtsAudioData> _synthesizeMiniMax(
    HttpClient client, {
    required ApiModel model,
    required String text,
    required String voice,
  }) async {
    final base = model.baseUrl.trim().isEmpty
        ? 'https://api.minimax.cn'
        : model.baseUrl.trim();
    final response = await _postJson(
      client,
      minimaxEndpoint(base),
      model.apiKey,
      requestBody(
        protocol: TtsProtocol.minimax,
        model: model,
        text: text,
        voice: voice,
      ),
    );
    final json = _decodeJsonResponse(response, 'MiniMax TTS');
    return TtsAudioData(decodeMiniMaxAudio(json), 'mp3');
  }

  static Future<TtsAudioData> _synthesizeQwen(
    HttpClient client, {
    required ApiModel model,
    required String text,
    required String voice,
    required String instructions,
  }) async {
    final base = model.baseUrl.trim().isEmpty
        ? 'https://maas.qianwenaiapi.com/api/v1'
        : model.baseUrl.trim();
    final response = await _postJson(
      client,
      qwenEndpoint(base),
      model.apiKey,
      requestBody(
        protocol: TtsProtocol.qwen,
        model: model,
        text: text,
        voice: voice,
        instructions: instructions,
      ),
    );
    final json = _decodeJsonResponse(response, 'Qwen TTS');
    final audio = decodeQwenAudio(json);
    if (audio.bytes != null) {
      return TtsAudioData(audio.bytes!, 'wav');
    }
    final bytes = await _downloadAudio(
      client,
      audio.url!,
      provider: 'Qwen TTS',
    );
    return TtsAudioData(bytes, 'wav');
  }

  static Uint8List decodeMiMoAudio(Map<String, dynamic> json) {
    final choices = json['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw const TtsException('MiMo TTS 返回中没有有效的 choices');
    }
    final choice = choices.first as Map;
    final message = choice['message'];
    final audio = message is Map ? message['audio'] : null;
    final data = audio is Map ? audio['data']?.toString() : null;
    if (data == null || data.isEmpty) {
      throw const TtsException('MiMo TTS 返回中没有音频数据');
    }
    try {
      return base64Decode(data);
    } on FormatException {
      throw const TtsException('MiMo TTS 返回了无效的 Base64 音频数据');
    }
  }

  static Uint8List decodeMiniMaxAudio(Map<String, dynamic> json) {
    final baseResponse = json['base_resp'];
    if (baseResponse is! Map || baseResponse['status_code'] == null) {
      throw const TtsException('MiniMax TTS 返回中缺少状态信息');
    }
    final code = baseResponse['status_code'];
    if (code != 0) {
      final message = baseResponse['status_msg']?.toString() ?? '未知错误';
      throw TtsException('MiniMax TTS 请求失败：$code，$message');
    }
    final data = json['data'];
    final audio = data is Map ? data['audio']?.toString() : null;
    if (audio == null || audio.isEmpty) {
      throw const TtsException('MiniMax TTS 返回中没有音频数据');
    }
    return decodeHexAudio(audio);
  }

  static ({Uint8List? bytes, String? url}) decodeQwenAudio(
    Map<String, dynamic> json,
  ) {
    final code = json['code']?.toString();
    if (code != null && code.isNotEmpty) {
      final message = json['message']?.toString() ?? '未知错误';
      throw TtsException('Qwen TTS 请求失败：$code，$message');
    }
    final output = json['output'];
    final audio = output is Map ? output['audio'] : null;
    if (audio is! Map) {
      throw const TtsException('Qwen TTS 返回中没有音频信息');
    }
    final data = audio['data']?.toString();
    if (data != null && data.isNotEmpty) {
      try {
        return (bytes: base64Decode(data), url: null);
      } on FormatException {
        throw const TtsException('Qwen TTS 返回了无效的 Base64 音频数据');
      }
    }
    final url = audio['url']?.toString();
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const TtsException('Qwen TTS 返回中没有有效的音频地址或音频数据');
    }
    return (bytes: null, url: url);
  }

  static Future<Uint8List> _postJson(
    HttpClient client,
    String endpoint,
    String apiKey,
    Map<String, dynamic> body,
  ) async {
    final request = await client
        .postUrl(Uri.parse(endpoint))
        .timeout(const Duration(seconds: 20));
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
    request.add(utf8.encode(jsonEncode(body)));
    final response = await request.close().timeout(const Duration(seconds: 90));
    final bytes = await response.fold<BytesBuilder>(
      BytesBuilder(),
      (builder, chunk) {
        builder.add(chunk);
        return builder;
      },
    );
    final data = bytes.takeBytes();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TtsException(_formatHttpError(response.statusCode, data));
    }
    if (data.isEmpty) throw const TtsException('语音模型返回了空响应');
    return data;
  }

  static Map<String, dynamic> _decodeJsonResponse(
    Uint8List data,
    String provider,
  ) {
    try {
      return jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
    } catch (_) {
      throw TtsException('$provider 返回了无法解析的 JSON');
    }
  }

  static Future<Uint8List> _downloadAudio(
    HttpClient client,
    String url, {
    required String provider,
  }) async {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close().timeout(const Duration(seconds: 90));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TtsException('$provider 音频下载失败：HTTP ${response.statusCode}');
    }
    final bytes = await response.fold<BytesBuilder>(
      BytesBuilder(),
      (builder, chunk) {
        builder.add(chunk);
        return builder;
      },
    );
    return bytes.takeBytes();
  }

  static Uint8List decodeHexAudio(String value) {
    final hex = value.trim();
    if (hex.length.isOdd || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) {
      throw const TtsException('MiniMax TTS 返回了无效的十六进制音频数据');
    }
    return Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
  }

  static String _formatHttpError(int statusCode, List<int> data) {
    final body = utf8.decode(data, allowMalformed: true).trim();
    final isHtml =
        RegExp(r'<\s*(html|!doctype|head|body)\b', caseSensitive: false)
            .hasMatch(body);
    if (isHtml) {
      return '语音请求失败：HTTP $statusCode。接口返回了网页错误页，请确认 API 地址和 TTS 接口协议。';
    }
    if (body.isEmpty) return '语音请求失败：HTTP $statusCode';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] != null) {
          return '语音请求失败：HTTP $statusCode，${error['message']}';
        }
        final message = decoded['message']?.toString();
        if (message != null && message.isNotEmpty) {
          return '语音请求失败：HTTP $statusCode，$message';
        }
        final baseResponse = decoded['base_resp'];
        if (baseResponse is Map && baseResponse['status_msg'] != null) {
          return '语音请求失败：HTTP $statusCode，${baseResponse['status_msg']}';
        }
      }
    } catch (_) {}
    return '语音请求失败：HTTP $statusCode，$body';
  }
}

/// 合成结果：音频字节与文件扩展名。
class TtsAudioData {
  const TtsAudioData(this.bytes, this.extension);
  final Uint8List bytes;
  final String extension;
}

class TtsException implements Exception {
  final String message;
  const TtsException(this.message);

  @override
  String toString() => message;
}
