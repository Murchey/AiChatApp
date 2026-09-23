import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import '../providers/api_provider.dart';

/// OpenAI-compatible speech API client.
/// Qwen compatible-mode and other providers such as MiMo can be configured
/// through the same base URL / model / key fields as chat models.
class TtsService {
  TtsService._();

  static final AudioPlayer _player = AudioPlayer();
  static String? _currentFile;

  static String speechEndpoint(String baseUrl) {
    var value = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (value.endsWith('/audio/speech')) return value;
    if (value.endsWith('/chat/completions')) {
      value = value.substring(0, value.length - '/chat/completions'.length);
    }
    return '$value/audio/speech';
  }

  static Future<void> stop() => _player.stop();

  /// MiMo TTS 使用 Chat Completions 返回音频，不走 /audio/speech。
  static bool isMiMoChatModel(ApiModel model) {
    final base = model.baseUrl.toLowerCase();
    final name = model.modelName.toLowerCase();
    return (base.contains('xiaomimimo.com') || name.startsWith('mimo-')) &&
        !name.contains('tts');
  }

  static bool isMiMoTtsModel(ApiModel model) {
    final base = model.baseUrl.toLowerCase();
    final name = model.modelName.toLowerCase();
    return (base.contains('xiaomimimo.com') || name.startsWith('mimo-')) &&
        name.contains('tts');
  }

  static bool isSupportedModel(ApiModel model) =>
      !isMiMoChatModel(model) && !isMiMoTtsModel(model);

  static Future<void> speak({
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
    if (!isSupportedModel(model)) {
      throw const TtsException(
        '当前未适配 MiMo TTS，请改用 Qwen DashScope 或 OpenAI 兼容的语音模型。',
      );
    }
    final base = model.baseUrl.trim().isEmpty
        ? 'https://api.openai.com/v1'
        : model.baseUrl.trim();
    final body = <String, dynamic>{
      'model': model.modelName.trim(),
      'input': text,
      'voice': voice.trim().isEmpty ? 'alloy' : voice.trim(),
      'response_format': 'mp3',
    };
    if (instructions.trim().isNotEmpty) body['instructions'] = instructions.trim();

    final client = HttpClient();
    try {
      if (_isDashScopeQwenTts(model)) {
        await _speakDashScopeQwen(
          client,
          model: model,
          text: text,
          voice: voice,
          instructions: instructions,
        );
        return;
      }
      final request = await client
          .postUrl(Uri.parse(speechEndpoint(base)))
          .timeout(const Duration(seconds: 20));
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${model.apiKey}');
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
        final message = _formatHttpError(response.statusCode, data);
        throw TtsException(message);
      }
      if (data.isEmpty) throw const TtsException('语音模型返回了空音频');

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/aichat_tts_${DateTime.now().microsecondsSinceEpoch}.mp3');
      await file.writeAsBytes(data, flush: true);
      await _player.stop();
      final previous = _currentFile;
      _currentFile = file.path;
      if (previous != null && previous != file.path) {
        try {
          await File(previous).delete();
        } catch (_) {}
      }
      await _player.play(DeviceFileSource(file.path));
    } finally {
      client.close(force: true);
    }
  }

  static String _formatHttpError(int statusCode, List<int> data) {
    final body = utf8.decode(data, allowMalformed: true).trim();
    final isHtml = RegExp(r'<\s*(html|!doctype|head|body)\b', caseSensitive: false)
        .hasMatch(body);
    if (isHtml) {
      return '语音请求失败：HTTP $statusCode。接口返回了网页错误页，请确认 API 地址和 TTS 接口协议。';
    }
    if (body.isEmpty) return '语音请求失败：HTTP $statusCode';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        final error = decoded['error'] as Map;
        final message = error['message']?.toString();
        if (message != null && message.isNotEmpty) {
          return '语音请求失败：HTTP $statusCode，$message';
        }
      }
    } catch (_) {}
    return '语音请求失败：HTTP $statusCode，$body';
  }

  static bool _isDashScopeQwenTts(ApiModel model) {
    final base = model.baseUrl.toLowerCase();
    final name = model.modelName.toLowerCase();
    return base.contains('dashscope.aliyuncs.com') && name.contains('tts');
  }

  /// Qwen-TTS 使用 DashScope 原生多模态生成接口，不是 /audio/speech。
  static Future<void> _speakDashScopeQwen(
    HttpClient client, {
    required ApiModel model,
    required String text,
    required String voice,
    required String instructions,
  }) async {
    final request = await client
        .postUrl(Uri.parse(
            'https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation'))
        .timeout(const Duration(seconds: 20));
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${model.apiKey}');
    final input = <String, dynamic>{
      'text': text,
      'voice': voice.trim().isEmpty ? 'Cherry' : voice.trim(),
      'language_type': 'Auto',
    };
    if (instructions.trim().isNotEmpty) input['instructions'] = instructions.trim();
    request.add(utf8.encode(jsonEncode({
      'model': model.modelName.trim(),
      'input': input,
    })));
    final response = await request.close().timeout(const Duration(seconds: 90));
    final raw = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TtsException(_formatHttpError(response.statusCode, utf8.encode(raw)));
    }
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final output = json['output'] as Map<String, dynamic>? ?? const {};
    final audio = output['audio'] as Map<String, dynamic>? ?? const {};
    final url = audio['url']?.toString();
    final base64Audio = audio['data']?.toString();
    Uint8List bytes;
    if (url != null && url.isNotEmpty) {
      final audioResponse = await client.getUrl(Uri.parse(url));
      final downloaded = await audioResponse.close();
      if (downloaded.statusCode != 200) {
        throw TtsException('Qwen TTS 音频下载失败：HTTP ${downloaded.statusCode}');
      }
      bytes = (await downloaded.fold<BytesBuilder>(BytesBuilder(), (b, c) {
        b.add(c);
        return b;
      })).takeBytes();
    } else if (base64Audio != null && base64Audio.isNotEmpty) {
      bytes = base64Decode(base64Audio);
    } else {
      throw const TtsException('Qwen TTS 返回中没有音频地址或音频数据');
    }
    await _playBytes(bytes);
  }

  static Future<void> _playBytes(Uint8List data) async {
    if (data.isEmpty) throw const TtsException('语音模型返回了空音频');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/aichat_tts_${DateTime.now().microsecondsSinceEpoch}.mp3');
    await file.writeAsBytes(data, flush: true);
    await _player.stop();
    final previous = _currentFile;
    _currentFile = file.path;
    if (previous != null && previous != file.path) {
      try {
        await File(previous).delete();
      } catch (_) {}
    }
    await _player.play(DeviceFileSource(file.path));
  }
}

class TtsException implements Exception {
  final String message;
  const TtsException(this.message);
  @override
  String toString() => message;
}
