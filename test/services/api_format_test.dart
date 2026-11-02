import 'dart:convert';
import 'dart:io';
import 'package:ai_chat/providers/api_provider.dart';
import 'package:ai_chat/services/llm_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _base = ApiModel(
    id: 'm', displayName: 'M', modelName: 'test-model', apiKey: 'test-key');
const _messages = [
  {'role': 'user', 'content': 'Hello'}
];

String _sse(Object event) => 'data: ${jsonEncode(event)}\n\n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    final previous = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previous);
    LLMService.thinkingLevel = ModelThinkingLevel.defaultLevel;
    addTearDown(
        () => LLMService.thinkingLevel = ModelThinkingLevel.defaultLevel);
  });

  group('completionUrl 按格式分派', () {
    test('openai-chat 保持既有行为', () {
      expect(
          LLMService.completionUrl(
              _base.copyWith(baseUrl: 'https://api.deepseek.com')),
          'https://api.deepseek.com/chat/completions');
    });

    test('anthropic 默认官方地址与 /v1 补全、末级路径剥离', () {
      expect(
          LLMService.completionUrl(
              _base.copyWith(apiFormat: ApiFormat.anthropic)),
          'https://api.anthropic.com/v1/messages');
      expect(
          LLMService.completionUrl(_base.copyWith(
              apiFormat: ApiFormat.anthropic,
              baseUrl: 'https://api.anthropic.com')),
          'https://api.anthropic.com/v1/messages');
      expect(
          LLMService.completionUrl(_base.copyWith(
              apiFormat: ApiFormat.anthropic,
              baseUrl: 'https://api.anthropic.com/v1/messages')),
          'https://api.anthropic.com/v1/messages');
    });

    test('openai-responses 后缀与 baseUrl 末级路径剥离', () {
      expect(
          LLMService.completionUrl(_base.copyWith(
              apiFormat: ApiFormat.openaiResponses,
              baseUrl: 'https://api.openai.com/v1')),
          'https://api.openai.com/v1/responses');
      expect(
          LLMService.completionUrl(_base.copyWith(
              apiFormat: ApiFormat.openaiResponses,
              baseUrl: 'https://proxy.test/custom/responses')),
          'https://proxy.test/custom/responses');
    });
  });

  group('buildChatBody 报文转换', () {
    final messages = <Map<String, Object>>[
      {'role': 'system', 'content': '你是助手'},
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': '这是什么颜色'},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/png;base64,AAAA'}
          },
        ],
      },
    ];

    test('anthropic：system 提顶层、图片转 base64 block、max_tokens 必填', () {
      final body = LLMService.buildChatBody(
        model: _base.copyWith(apiFormat: ApiFormat.anthropic),
        messages: messages,
        maxTokens: 64,
      );
      expect(body['system'], '你是助手');
      expect(body['max_tokens'], 64);
      expect(body.containsKey('max_output_tokens'), isFalse);
      expect(body.containsKey('enable_thinking'), isFalse);
      final converted = body['messages'] as List;
      expect(converted.length, 1);
      final msg = converted.first as Map;
      expect(msg['role'], 'user');
      final blocks = msg['content'] as List;
      expect(blocks[0], {'type': 'text', 'text': '这是什么颜色'});
      expect((blocks[1] as Map)['type'], 'image');
      expect((blocks[1] as Map)['source'], {
        'type': 'base64',
        'media_type': 'image/png',
        'data': 'AAAA'
      });
    });

    test('openai-responses：instructions 与 input_text/input_image', () {
      final body = LLMService.buildChatBody(
        model: _base.copyWith(apiFormat: ApiFormat.openaiResponses),
        messages: messages,
        maxTokens: 64,
        jsonMode: true,
      );
      expect(body['instructions'], '你是助手');
      expect(body['max_output_tokens'], 64);
      expect(body.containsKey('max_tokens'), isFalse);
      final input = body['input'] as List;
      final parts = (input.first as Map)['content'] as List;
      expect(parts[0], {'type': 'input_text', 'text': '这是什么颜色'});
      expect((parts[1] as Map)['type'], 'input_image');
      expect((parts[1] as Map)['image_url'], 'data:image/png;base64,AAAA');
      expect(body['text'], {'format': {'type': 'json_object'}});
    });

    test('openai-chat：原样透传且保留思考字段', () {
      LLMService.thinkingLevel = ModelThinkingLevel.high;
      final body = LLMService.buildChatBody(
        model: _base,
        messages: messages,
        maxTokens: 64,
      );
      expect(body['messages'], messages);
      expect(body['stream'], isFalse);
      expect(body.containsKey('system'), isFalse);
      expect(body['enable_thinking'], true);
    });
  });

  group('parseChatReply 三种响应容错解析', () {
    test('OpenAI Chat：choices.message.content', () {
      final reply = LLMService.parseChatReply(jsonEncode({
        'choices': [
          {
            'message': {'content': '你好', 'reasoning_content': '思考中'},
            'finish_reason': 'stop'
          }
        ]
      }));
      expect(reply.content, '你好');
      expect(reply.reasoning, '思考中');
      expect(reply.finishReason, 'stop');
    });

    test('Anthropic：thinking/text blocks 与 stop_reason 映射', () {
      final reply = LLMService.parseChatReply(jsonEncode({
        'content': [
          {'type': 'thinking', 'thinking': '想一想'},
          {'type': 'text', 'text': '答案'}
        ],
        'stop_reason': 'max_tokens',
      }));
      expect(reply.content, '答案');
      expect(reply.reasoning, '想一想');
      expect(reply.finishReason, 'length');
    });

    test('OpenAI Responses：reasoning 摘要与 output_text', () {
      final reply = LLMService.parseChatReply(jsonEncode({
        'output': [
          {
            'type': 'reasoning',
            'summary': [
              {'type': 'summary_text', 'text': '推理摘要'}
            ]
          },
          {
            'type': 'message',
            'content': [
              {'type': 'output_text', 'text': '最终答案'}
            ]
          }
        ],
        'status': 'incomplete',
      }));
      expect(reply.content, '最终答案');
      expect(reply.reasoning, '推理摘要');
      expect(reply.finishReason, 'length');
    });
  });

  group('parseStreamChunkFor 流式事件', () {
    test('anthropic：message_start / content_block_delta / message_delta', () {
      final start = LLMService.parseStreamChunkFor(
          ApiFormat.anthropic,
          jsonEncode({
            'type': 'message_start',
            'message': {
              'usage': {'input_tokens': 12, 'output_tokens': 1}
            }
          }));
      expect(start.usage.promptTokens, 12);
      final text = LLMService.parseStreamChunkFor(
          ApiFormat.anthropic,
          jsonEncode({
            'type': 'content_block_delta',
            'delta': {'type': 'text_delta', 'text': '你'}
          }));
      expect(text.content, '你');
      final think = LLMService.parseStreamChunkFor(
          ApiFormat.anthropic,
          jsonEncode({
            'type': 'content_block_delta',
            'delta': {'type': 'thinking_delta', 'thinking': '嗯'}
          }));
      expect(think.reasoning, '嗯');
      final end = LLMService.parseStreamChunkFor(
          ApiFormat.anthropic,
          jsonEncode({
            'type': 'message_delta',
            'usage': {'output_tokens': 8}
          }));
      expect(end.usage.completionTokens, 8);
    });

    test('openai-responses：delta 事件与 completed 用量', () {
      final text = LLMService.parseStreamChunkFor(
          ApiFormat.openaiResponses,
          jsonEncode(
              {'type': 'response.output_text.delta', 'delta': '好'}));
      expect(text.content, '好');
      final done = LLMService.parseStreamChunkFor(
          ApiFormat.openaiResponses,
          jsonEncode({
            'type': 'response.completed',
            'response': {
              'usage': {'input_tokens': 3, 'output_tokens': 5}
            }
          }));
      expect(done.usage.promptTokens, 3);
      expect(done.usage.completionTokens, 5);
      expect(done.usage.totalTokens, 8);
    });
  });

  test('anthropic 格式请求：x-api-key 鉴权与 /messages 报文', () async {
    var captured = <String, dynamic>{};
    final server = await _server((request, body) {
      captured = body;
      expect(request.uri.path, '/v1/messages');
      expect(request.headers.value('x-api-key'), 'test-key');
      expect(request.headers.value('anthropic-version'), '2023-06-01');
      request.response.write(jsonEncode({
        'content': [
          {'type': 'text', 'text': '红色'}
        ],
        'stop_reason': 'stop',
        'usage': {'input_tokens': 10, 'output_tokens': 4}
      }));
    });
    final model =
        _local(server).copyWith(apiFormat: ApiFormat.anthropic);
    final result = await LLMService.fetchCompletion(
      model: model,
      messages: [
        {'role': 'system', 'content': '系统'},
        {'role': 'user', 'content': '你好'}
      ],
      maxTokens: 64,
    );
    expect(result.content, '红色');
    expect(result.usage.promptTokens, 10);
    expect(result.usage.completionTokens, 4);
    expect(result.usage.totalTokens, 14);
    expect(result.finishReason, 'stop');
    expect(captured['system'], '系统');
    expect(captured.containsKey('messages'), isTrue);
    expect(captured['max_tokens'], 64);
    expect(captured.containsKey('stream'), isFalse);
  });

  test('openai-responses 格式请求：Bearer 鉴权与 /responses 报文', () async {
    var captured = <String, dynamic>{};
    final server = await _server((request, body) {
      captured = body;
      expect(request.uri.path, '/v1/responses');
      expect(request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer test-key');
      request.response.write(jsonEncode({
        'output': [
          {
            'type': 'message',
            'content': [
              {'type': 'output_text', 'text': '好的'}
            ]
          }
        ],
        'status': 'completed',
        'usage': {'input_tokens': 2, 'output_tokens': 3}
      }));
    });
    final model =
        _local(server).copyWith(apiFormat: ApiFormat.openaiResponses);
    final result = await LLMService.fetchCompletion(
      model: model,
      messages: [
        {'role': 'system', 'content': '指令'},
        {'role': 'user', 'content': '你好'}
      ],
      maxTokens: 32,
    );
    expect(result.content, '好的');
    expect(result.finishReason, 'stop');
    expect(captured['instructions'], '指令');
    expect(captured['max_output_tokens'], 32);
  });

  test('anthropic 流式输出按事件拼接正文', () async {
    final server = await _server((request, body) {
      request.response.headers.contentType =
          ContentType('text', 'event-stream', charset: 'utf-8');
      request.response.write(_sse({
        'type': 'message_start',
        'message': {
          'usage': {'input_tokens': 4, 'output_tokens': 0}
        }
      }));
      request.response.write(_sse({
        'type': 'content_block_delta',
        'delta': {'type': 'text_delta', 'text': '你好'}
      }));
      request.response.write(_sse({'type': 'message_stop'}));
    });
    final chunks = await streamCompletion(
      model: _local(server).copyWith(apiFormat: ApiFormat.anthropic),
      messages: _messages,
    ).toList();
    expect(chunks.map((c) => c.content).join(), '你好');
    expect(chunks.first.usage.promptTokens, 4);
  });

  test('ApiModel apiFormat 序列化往返与默认值', () {
    expect(_base.apiFormat, ApiFormat.openaiChat);
    final json = _base.copyWith(apiFormat: ApiFormat.anthropic).toJson();
    expect(json['api_format'], 'anthropic');
    expect(ApiModel.fromJson(json).apiFormat, ApiFormat.anthropic);
    expect(ApiModel.fromJson(const {'id': 'x'}).apiFormat,
        ApiFormat.openaiChat);
    expect(ApiFormat.normalize('unknown'), ApiFormat.openaiChat);
  });
}

Future<HttpServer> _server(
    void Function(HttpRequest, Map<String, dynamic>) handler) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  server.listen((request) async {
    final body = jsonDecode(await utf8.decoder.bind(request).join())
        as Map<String, dynamic>;
    request.response.headers.contentType = ContentType.json;
    handler(request, body);
    await request.response.close();
  });
  return server;
}

ApiModel _local(HttpServer server) => _base.copyWith(
    baseUrl: 'http://127.0.0.1:${server.port}/v1');
