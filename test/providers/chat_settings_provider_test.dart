import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_chat/providers/chat_settings_provider.dart';

void main() {
  test('记忆点自动托管开关默认关闭并可持久化', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = ChatSettingsProvider();
    await provider.init();
    expect(provider.autoMemoryEnabled, isFalse);

    await provider.setAutoMemoryEnabled(true);
    expect(provider.autoMemoryEnabled, isTrue);
    expect(
      (await SharedPreferences.getInstance())
          .getBool('chat_auto_memory_enabled'),
      isTrue,
    );

    final reloaded = ChatSettingsProvider();
    await reloaded.init();
    expect(reloaded.autoMemoryEnabled, isTrue);

    await reloaded.setAutoMemoryEnabled(false);
    expect(
      (await SharedPreferences.getInstance())
          .getBool('chat_auto_memory_enabled'),
      isFalse,
    );
  });
}
