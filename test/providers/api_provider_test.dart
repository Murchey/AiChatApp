import 'dart:convert';

import 'package:ai_chat/providers/api_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('voice purpose model selections persist independently', () async {
    const model = ApiModel(
      id: 'voice-1',
      displayName: 'MiMo Voice',
      modelName: 'mimo-v2.5-tts',
      ttsProtocol: 'mimo',
      ttsCapabilities: [TtsCapabilities.speech, TtsCapabilities.design],
    );
    SharedPreferences.setMockInitialValues({
      'api_models_v1': jsonEncode([model.toJson()]),
    });
    final provider = ApiProvider();
    await provider.init();
    await provider.setTtsModel(model.id);
    await provider.setTtsDesignModel(model.id);
    expect(provider.ttsModelId, model.id);
    expect(provider.ttsDesignModelId, model.id);
    expect(provider.ttsCloneModelId, isNull);

    final restored = ApiProvider();
    await restored.init();
    expect(restored.ttsModelId, model.id);
    expect(restored.ttsDesignModelId, model.id);
    expect(restored.ttsCloneModelId, isNull);
  });

  test('deleting a model clears all voice purpose selections', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = ApiProvider();
    await provider.init();
    final model = await provider.addModel(
      displayName: 'Voice',
      modelName: 'tts-custom',
      ttsProtocol: 'openai',
    );
    await provider.setTtsModel(model.id);
    await provider.setTtsDesignModel(model.id);
    await provider.setTtsCloneModel(model.id);
    await provider.deleteModel(model.id);
    expect(provider.ttsModelId, isNull);
    expect(provider.ttsDesignModelId, isNull);
    expect(provider.ttsCloneModelId, isNull);
  });
}
