import 'dart:async';

import 'package:ai_chat/providers/story_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('empty story source stays offline until configured', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = StoryProvider();
    await provider.init();

    expect(provider.isConfigured, isFalse);
    await provider.loadCatalog();
    expect(provider.loading, isFalse);
    expect(provider.entries, isEmpty);
    expect(provider.error, isNull);
  });

  test('story source errors are converted to readable messages', () {
    SharedPreferences.setMockInitialValues({});
    final provider = StoryProvider();

    expect(
      provider.readableError(
        TimeoutException('Future not completed', const Duration(seconds: 8)),
      ),
      '故事来源请求超时，请检查地址、端口或网络',
    );
  });
}
