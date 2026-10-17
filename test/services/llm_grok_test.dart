import 'dart:convert';
import 'dart:io';
import 'package:ai_chat/providers/api_provider.dart';
import 'package:ai_chat/services/llm_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _grok = ApiModel(
    id: 'grok', displayName: 'Grok', modelName: 'grok-4', apiKey: 'test-key');
const _messages = [
  {'role': 'user', 'content': 'Hello'}
];

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

  test(
      'official xAI endpoints normalize and custom gateway prefixes stay intact',
      () {
    for (final base in [
      '',
      'https://api.x.ai',
      'https://api.x.ai/',
      'https://api.x.ai/v1/',
      'https://api.x.ai/v1/chat/completions/'
    ]) {
      expect(LLMService.completionUrl(_grok.copyWith(baseUrl: base)),
          'https://api.x.ai/v1/chat/completions');
    }
    expect(
        LLMService.completionUrl(
            _grok.copyWith(baseUrl: 'https://proxy.test/custom/v1?tenant=one')),
        'https://proxy.test/custom/v1/chat/completions?tenant=one');
    expect(LLMService.completionUrl(_grok.copyWith(modelName: 'deepseek-chat')),
        'https://api.deepseek.com/chat/completions');
  });

  test(
      'Grok thinking levels never emit Qwen flags or unsupported effort values',
      () {
    for (final modelName in [
      'grok-4',
      'grok-4-1-fast-reasoning',
      'grok-4.20-reasoning',
      'x-ai/grok-4',
      'grok-3',
      'grok-4-1-fast-non-reasoning'
    ]) {
      for (final level in ModelThinkingLevel.values) {
        expect(
            LLMService.thinkingRequestFields(
                model: _grok.copyWith(modelName: modelName), level: level),
            isEmpty);
      }
    }
    final mini = _grok.copyWith(modelName: 'grok-3-mini');
    expect(
        LLMService.thinkingRequestFields(
            model: mini, level: ModelThinkingLevel.xhigh),
        {'reasoning_effort': 'high'});
    expect(
        LLMService.thinkingRequestFields(
            model: mini, level: ModelThinkingLevel.off),
        {'reasoning_effort': 'low'});
    expect(
        LLMService.thinkingRequestFields(
            model: _grok.copyWith(modelName: 'qwen-plus'),
            level: ModelThinkingLevel.high),
        {'enable_thinking': true, 'reasoning_effort': 'high'});
  });

  test(
      'Grok text and vision requests succeed against a strict compatible endpoint',
      () async {
    var count = 0;
    final server = await _server((request, body) {
      count++;
      expect(request.uri.path, '/v1/chat/completions');
      expect(request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer test-key');
      expect(body.containsKey('enable_thinking'), false);
      expect(body.containsKey('reasoning_effort'), false);
      expect(body['max_tokens'], 4096);
      request.response.write(jsonEncode({
        'choices': [
          {
            'message': {'content': '红色'}
          }
        ],
        'usage': {
          'prompt_tokens': 10,
          'completion_tokens': 8,
          'total_tokens': 18
        }
      }));
    });
    final model = _local(server);
    for (final level in ModelThinkingLevel.values) {
      LLMService.thinkingLevel = level;
      final result = await LLMService.fetchCompletion(
          model: model, messages: _messages, maxTokens: 64);
      expect(result.content, '红色');
      expect(result.usage.totalTokens, 18);
    }
    expect(await LLMService.testImageSupport(model), true);
    expect(count, 6);
  });

  test('non-reasoning Grok keeps the requested output allowance', () async {
    final server = await _server((request, body) {
      expect(body['max_tokens'], 64);
      request.response.write(jsonEncode({
        'choices': [
          {
            'message': {'content': 'OK'}
          }
        ]
      }));
    });
    await LLMService.fetchCompletion(
        model:
            _local(server).copyWith(modelName: 'grok-4-1-fast-non-reasoning'),
        messages: _messages,
        maxTokens: 64);
  });

  test(
      'reasoning exhaustion is reported without charging for an identical retry',
      () async {
    var count = 0;
    final server = await _server((request, body) {
      count++;
      request.response.write(jsonEncode({
        'choices': [
          {
            'finish_reason': 'length',
            'message': {'content': '', 'reasoning_content': 'Thinking'}
          }
        ]
      }));
    });
    await expectLater(
        LLMService.fetchCompletion(model: _local(server), messages: _messages),
        throwsA(isA<LLMException>()
            .having((e) => e.message, 'reason', contains('输出额度'))));
    expect(count, 1);
  });

  test('streaming uses the same Grok compatibility and preserves usage',
      () async {
    final server = await _server((request, body) {
      expect(body['stream'], true);
      expect(body['enable_thinking'], isNull);
      expect(body['reasoning_effort'], isNull);
      expect(body['max_tokens'], 4096);
      request.response.headers.contentType =
          ContentType('text', 'event-stream');
      request.response.write('data: ${jsonEncode({
            'choices': [
              {
                'delta': {'reasoning_content': 'Thinking'}
              }
            ]
          })}\n\n'
          'data: ${jsonEncode({
            'choices': [
              {
                'delta': {'content': 'OK'}
              }
            ]
          })}\n\n'
          'data: ${jsonEncode({
            'choices': [],
            'usage': {'total_tokens': 25}
          })}\n\n'
          'data: [DONE]\n\n');
    });
    LLMService.thinkingLevel = ModelThinkingLevel.xhigh;
    final chunks =
        await streamCompletion(model: _local(server), messages: _messages)
            .toList();
    expect(chunks.map((c) => c.content).join(), 'OK');
    expect(chunks.last.usage.totalTokens, 25);
  });

  test(
      'API errors preserve HTTP status, redact credentials and do not blindly retry',
      () async {
    for (final status in [400, 401, 403, 404, 429, 503]) {
      var count = 0;
      final server = await _server((request, body) {
        count++;
        request.response.statusCode = status;
        request.response.write(
            jsonEncode({'error': 'unsupported parameter; Bearer test-key'}));
      });
      await expectLater(
          LLMService.fetchCompletion(
              model: _local(server), messages: _messages),
          throwsA(isA<LLMException>().having(
              (e) => e.message,
              'diagnostic',
              allOf(contains('HTTP $status'), contains('unsupported parameter'),
                  isNot(contains('test-key'))))));
      expect(count, 1);
    }
  });

  test('SSE error events and empty streams are not silently treated as success',
      () async {
    final server = await _server((request, body) {
      request.response.headers.contentType =
          ContentType('text', 'event-stream');
      request.response.write('data: ${jsonEncode({
            'error': {'message': 'rate limit test-key'}
          })}\n\n');
    });
    await expectLater(
        streamCompletion(model: _local(server), messages: _messages).toList(),
        throwsA(isA<LLMException>().having((e) => e.message, 'detail',
            allOf(contains('rate limit'), isNot(contains('test-key'))))));
    final empty = await _server(
        (request, body) => request.response.write('data: [DONE]\n\n'));
    await expectLater(
        streamCompletion(model: _local(empty), messages: _messages).toList(),
        throwsA(isA<LLMException>()));
  });

  test('model discovery reports actual server rejection instead of blaming KEY',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      expect(request.uri.path, '/v1/models');
      request.response
        ..statusCode = 429
        ..write(jsonEncode({
          'error': {'message': 'Quota exhausted'}
        }));
      await request.response.close();
    });
    await expectLater(
        LLMService.fetchAvailableModels(
            baseUrl: _local(server).baseUrl, apiKey: 'test-key'),
        throwsA(isA<LLMException>().having((e) => e.message, 'error',
            allOf(contains('HTTP 429'), contains('Quota exhausted')))));
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

ApiModel _local(HttpServer server) =>
    _grok.copyWith(baseUrl: 'http://127.0.0.1:${server.port}/v1');
