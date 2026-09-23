import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat/services/tts_service.dart';
import 'package:ai_chat/providers/api_provider.dart';

void main() {
  test('builds OpenAI compatible speech endpoint from a provider v1 URL', () {
    expect(
      TtsService.speechEndpoint('https://dashscope.aliyuncs.com/compatible-mode/v1'),
      'https://dashscope.aliyuncs.com/compatible-mode/v1/audio/speech',
    );
  });

  test('accepts a complete audio speech endpoint unchanged', () {
    expect(
      TtsService.speechEndpoint('https://example.com/v1/audio/speech'),
      'https://example.com/v1/audio/speech',
    );
  });

  test('identifies MiMo chat models as non-TTS models', () {
    expect(
      TtsService.isMiMoChatModel(const ApiModel(
        id: 'mimo',
        displayName: 'MiMo',
        modelName: 'mimo-v2.5-pro',
        baseUrl: 'https://api.xiaomimimo.com/v1',
      )),
      isTrue,
    );
  });
}
