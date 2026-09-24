import 'dart:io';

import 'package:ai_chat/providers/api_provider.dart';
import 'package:ai_chat/services/tts_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds provider endpoints from configured base URLs', () {
    expect(
      TtsService.speechEndpoint('https://api.openai.com/v1'),
      'https://api.openai.com/v1/audio/speech',
    );
    expect(
      TtsService.mimoEndpoint('https://api.xiaomimimo.com/v1'),
      'https://api.xiaomimimo.com/v1/chat/completions',
    );
    expect(
      TtsService.minimaxEndpoint('https://api.minimax.cn'),
      'https://api.minimax.cn/v1/t2a_v2',
    );
    expect(
      TtsService.qwenEndpoint(
        'https://dashscope.aliyuncs.com/compatible-mode/v1',
      ),
      'https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation',
    );
    expect(
      TtsService.qwenEndpoint('https://maas.qianwenaiapi.com/api/v1'),
      'https://maas.qianwenaiapi.com/api/v1/services/aigc/multimodal-generation/generation',
    );
  });

  test('detects the four supported TTS protocols and rejects chat models', () {
    expect(TtsService.protocolFor(_openAiModel), TtsProtocol.openAi);
    expect(TtsService.protocolFor(_mimoModel), TtsProtocol.mimo);
    expect(TtsService.protocolFor(_minimaxModel), TtsProtocol.minimax);
    expect(TtsService.protocolFor(_qwenModel), TtsProtocol.qwen);
    expect(
      TtsService.protocolFor(const ApiModel(
        id: 'mimo-chat',
        displayName: 'MiMo Chat',
        modelName: 'mimo-v2.5-pro',
        baseUrl: 'https://api.xiaomimimo.com/v1',
      )),
      isNull,
    );
    expect(
      TtsService.protocolFor(const ApiModel(
        id: 'gpt-chat',
        displayName: 'GPT Chat',
        modelName: 'gpt-4o',
        baseUrl: 'https://api.openai.com/v1',
      )),
      isNull,
    );
    expect(
      TtsService.protocolFor(const ApiModel(
        id: 'proxy-qwen-tts',
        displayName: 'Proxy Qwen TTS',
        modelName: 'qwen3-tts-flash',
        baseUrl: 'https://proxy.example.com/v1',
      )),
      TtsProtocol.openAi,
    );
    expect(
      TtsService.protocolFor(const ApiModel(
        id: 'proxy-speech',
        displayName: 'Proxy Speech',
        modelName: 'speech-2.8-hd',
        baseUrl: 'https://proxy.example.com/v1',
      )),
      TtsProtocol.openAi,
    );
  });

  test('builds OpenAI audio speech request body', () {
    expect(
      TtsService.requestBody(
        protocol: TtsProtocol.openAi,
        model: _openAiModel,
        text: '你好',
        voice: 'alloy',
        instructions: '温柔地说',
      ),
      {
        'model': 'gpt-4o-mini-tts',
        'input': '你好',
        'voice': 'alloy',
        'response_format': 'mp3',
        'instructions': '温柔地说',
      },
    );
  });

  test('omits unsupported instructions for OpenAI tts-1', () {
    const model = ApiModel(
      id: 'tts-1',
      displayName: 'TTS 1',
      modelName: 'tts-1',
      baseUrl: 'https://api.openai.com/v1',
    );
    final body = TtsService.requestBody(
      protocol: TtsProtocol.openAi,
      model: model,
      text: '你好',
      instructions: '温柔地说',
    );

    expect(body, isNot(contains('instructions')));
  });

  test('builds MiMo chat completions audio request body', () {
    expect(
      TtsService.requestBody(
        protocol: TtsProtocol.mimo,
        model: _mimoModel,
        text: '你好',
        voice: '冰糖',
        instructions: '明亮、亲近',
      ),
      {
        'model': 'mimo-v2.5-tts',
        'messages': [
          {'role': 'user', 'content': '明亮、亲近'},
          {'role': 'assistant', 'content': '你好'},
        ],
        'audio': {'format': 'wav', 'voice': '冰糖'},
      },
    );
  });

  test('builds MiniMax synchronous T2A request body', () {
    expect(
      TtsService.requestBody(
        protocol: TtsProtocol.minimax,
        model: _minimaxModel,
        text: '你好',
        voice: 'male-qn-qingse',
      ),
      {
        'model': 'speech-2.8-hd',
        'text': '你好',
        'stream': false,
        'voice_setting': {'voice_id': 'male-qn-qingse'},
        'audio_setting': {
          'sample_rate': 32000,
          'bitrate': 128000,
          'format': 'mp3',
          'channel': 1,
        },
        'output_format': 'hex',
      },
    );
  });

  test('builds Qwen native multimodal request body', () {
    expect(
      TtsService.requestBody(
        protocol: TtsProtocol.qwen,
        model: _qwenModel,
        text: '你好',
        voice: 'Cherry',
        instructions: '快速、明亮',
      ),
      {
        'model': 'qwen3-tts-instruct-flash',
        'input': {
          'text': '你好',
          'voice': 'Cherry',
          'language_type': 'Auto',
          'instructions': '快速、明亮',
        },
      },
    );
  });

  test('decodes provider audio response formats', () {
    expect(
      TtsService.decodeMiMoAudio({
        'choices': [
          {
            'message': {
              'audio': {'data': 'AQID'},
            },
          },
        ],
      }),
      [1, 2, 3],
    );
    expect(
      TtsService.decodeMiniMaxAudio({
        'base_resp': {'status_code': 0, 'status_msg': 'success'},
        'data': {'audio': '494433'},
      }),
      [0x49, 0x44, 0x33],
    );
    expect(
      TtsService.decodeQwenAudio({
        'output': {
          'audio': {'data': 'AQID', 'url': ''},
        },
      }).bytes,
      [1, 2, 3],
    );
    expect(
      TtsService.decodeQwenAudio({
        'output': {
          'audio': {'data': '', 'url': 'https://example.com/audio.wav'},
        },
      }).url,
      'https://example.com/audio.wav',
    );
  });

  test('rejects malformed provider audio responses', () {
    expect(
      () => TtsService.decodeMiMoAudio({'choices': []}),
      throwsA(isA<TtsException>()),
    );
    expect(
      () => TtsService.decodeMiniMaxAudio({
        'base_resp': {'status_code': 1004, 'status_msg': '鉴权失败'},
      }),
      throwsA(
        isA<TtsException>().having(
          (error) => error.message,
          'message',
          contains('鉴权失败'),
        ),
      ),
    );
    expect(
      () => TtsService.decodeHexAudio('xyz'),
      throwsA(isA<TtsException>()),
    );
    expect(
      () => TtsService.decodeQwenAudio({
        'code': 'InvalidParameter',
        'message': 'voice is invalid',
      }),
      throwsA(
        isA<TtsException>().having(
          (error) => error.message,
          'message',
          contains('voice is invalid'),
        ),
      ),
    );
  });

  test('converts an HTML error response to a short message', () async {
    final server = await _errorServer(
      statusCode: HttpStatus.notFound,
      contentType: ContentType.html,
      body: '<!doctype html><html><body>not found</body></html>',
    );
    addTearDown(() => server.close(force: true));

    await expectLater(
      TtsService.synthesize(model: _localModel(server), text: 'hello'),
      throwsA(
        isA<TtsException>()
            .having((error) => error.message, 'message', contains('HTTP 404'))
            .having((error) => error.message, 'message', contains('网页错误页'))
            .having(
              (error) => error.message,
              'message',
              isNot(contains('<html>')),
            ),
      ),
    );
  });

  test('extracts error.message from a JSON error response', () async {
    final server = await _errorServer(
      statusCode: HttpStatus.badRequest,
      contentType: ContentType.json,
      body: '{"error":{"message":"voice is invalid"}}',
    );
    addTearDown(() => server.close(force: true));

    await expectLater(
      TtsService.synthesize(model: _localModel(server), text: 'hello'),
      throwsA(
        isA<TtsException>().having(
          (error) => error.message,
          'message',
          '语音请求失败：HTTP 400，voice is invalid',
        ),
      ),
    );
  });
}

const _openAiModel = ApiModel(
  id: 'openai-tts',
  displayName: 'OpenAI TTS',
  modelName: 'gpt-4o-mini-tts',
  baseUrl: 'https://api.openai.com/v1',
);

const _mimoModel = ApiModel(
  id: 'mimo-tts',
  displayName: 'MiMo TTS',
  modelName: 'mimo-v2.5-tts',
  baseUrl: 'https://api.xiaomimimo.com/v1',
);

const _minimaxModel = ApiModel(
  id: 'minimax-tts',
  displayName: 'MiniMax TTS',
  modelName: 'speech-2.8-hd',
  baseUrl: 'https://api.minimax.cn',
);

const _qwenModel = ApiModel(
  id: 'qwen-tts',
  displayName: 'Qwen TTS',
  modelName: 'qwen3-tts-instruct-flash',
  baseUrl: 'https://maas.qianwenaiapi.com/api/v1',
);

Future<HttpServer> _errorServer({
  required int statusCode,
  required ContentType contentType,
  required String body,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    request.response
      ..statusCode = statusCode
      ..headers.contentType = contentType
      ..write(body);
    await request.response.close();
  });
  return server;
}

ApiModel _localModel(HttpServer server) => ApiModel(
      id: 'local',
      displayName: 'Local',
      modelName: 'tts-test',
      baseUrl: 'http://${server.address.address}:${server.port}/v1',
      apiKey: 'test-key',
    );
