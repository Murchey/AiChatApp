import 'dart:convert';

import 'package:ai_chat/models/token_usage.dart';
import 'package:ai_chat/providers/token_usage_provider.dart';
import 'package:ai_chat/services/llm_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final provider = TokenUsageProvider.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await provider.reload();
  });

  test('add reset add is serialized and cache counters persist', () async {
    final first = provider.addUsage('a', const ChatUsage(promptTokens: 9));
    final reset = provider.resetAll();
    final last = provider.addUsage('b', const ChatUsage(promptTokens: 20,
      completionTokens: 3, cacheReadTokens: 10, cacheCreationTokens: 5),
      kind: TokenUsageKind.groupChat);
    await Future.wait([first, reset, last]);
    expect(provider.usageFor('a').totalTokens, 0);
    expect(provider.total, 23);
    await provider.reload();
    expect(provider.total, 23);
    expect(provider.cacheReadTotal, 10);
    expect(provider.cacheCreationTotal, 5);
    expect(provider.usageFor('b').kind, TokenUsageKind.groupChat);
  });

  test('reload clears memory when restored backup has no usage key', () async {
    await provider.addUsage('old', const ChatUsage(promptTokens: 10));
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('chat_token_usage_v1');
    await provider.reload();
    expect(provider.total, 0);
  });

  test('more than 500 conversations retain all billed tokens after reload', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('chat_token_usage_v1', jsonEncode({
      for (var i = 0; i < 501; i++) '$i': {'sent': 1, 'received': 1}
    }));
    await provider.reload();
    await provider.addUsage('new', const ChatUsage(promptTokens: 2));
    expect(provider.allUsages.length, 502);
    expect(provider.total, 1004);
    await provider.reload();
    expect(provider.total, 1004);
  });

  test('legacy malformed counters do not erase healthy restored entries', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('chat_token_usage_v1', jsonEncode({
      'good': {'sent': 10, 'received': 3},
      'legacy': {'sent': '7', 'received': -4, 'reasoning': 2.0}
    }));
    await provider.reload();
    expect(provider.total, 20);
    expect(provider.reasoningTotal, 2);
  });
}
