import 'dart:convert';
import 'dart:io';

import 'package:ai_chat/providers/api_provider.dart';
import 'package:ai_chat/services/llm_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    final previous = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previous);
  });

  test('Anthropic cache input counts merge with output-only stream snapshots', () {
    final start = LLMService.parseStreamChunkFor(ApiFormat.anthropic, jsonEncode({
      'type': 'message_start',
      'message': {'usage': {'input_tokens': 10, 'output_tokens': 0,
        'cache_read_input_tokens': 20, 'cache_creation_input_tokens': 30}},
    }));
    final end = LLMService.parseStreamChunkFor(ApiFormat.anthropic, jsonEncode({
      'type': 'message_delta', 'usage': {'output_tokens': 7},
    }));
    final merged = start.usage.merge(end.usage);
    expect(merged.promptTokens, 60);
    expect(merged.completionTokens, 7);
    expect(merged.totalTokens, 67);
    expect(merged.cacheReadTokens, 20);
    expect(merged.cacheCreationTokens, 30);
  });

  test('OpenAI and Responses cache details are subsets of input', () {
    for (final inputKey in ['prompt_tokens', 'input_tokens']) {
      final chunk = LLMService.parseStreamChunk(jsonEncode({'usage': {
        inputKey: 60, 'completion_tokens': 7,
        inputKey == 'prompt_tokens' ? 'prompt_tokens_details' : 'input_tokens_details':
          {'cached_tokens': 20},
      }}));
      expect(chunk.usage.promptTokens, 60);
      expect(chunk.usage.cacheReadTokens, 20);
      expect(chunk.usage.totalTokens, 67);
    }
  });

  test('empty response retries report each attempt and return accumulated usage', () async {
    var requests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await request.drain<void>();
      requests++;
      request.response.write(jsonEncode({'choices': [
        {'message': {'content': requests == 1 ? '' : 'answer'}}
      ], 'usage': {'prompt_tokens': 10, 'completion_tokens': requests}}));
      await request.response.close();
    });
    final recorded = <ChatUsage>[];
    final model = ApiModel(id: 'test', displayName: 'test', modelName: 'test',
      apiKey: 'test-key', baseUrl: 'http://127.0.0.1:${server.port}');
    final result = await LLMService.fetchCompletion(model: model,
      messages: const [{'role': 'user', 'content': 'hello'}],
      onUsage: recorded.add);
    expect(requests, 2);
    expect(recorded.length, 2);
    expect(result.usage.promptTokens, 20);
    expect(result.usage.completionTokens, 3);
  });

  test('final empty failure still reports billed usage', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await request.drain<void>();
      request.response.write(jsonEncode({'choices': [
        {'message': {'content': ''}, 'finish_reason': 'length'}
      ], 'usage': {'prompt_tokens': 10, 'completion_tokens': 50}}));
      await request.response.close();
    });
    final recorded = <ChatUsage>[];
    await expectLater(LLMService.fetchCompletion(
      model: ApiModel(id: 'test', displayName: 'test', modelName: 'test',
        apiKey: 'key', baseUrl: 'http://127.0.0.1:${server.port}'),
      messages: const [{'role': 'user', 'content': 'hello'}],
      onUsage: recorded.add), throwsA(isA<LLMException>()));
    expect(recorded.single.completionTokens, 50);
  });
}
