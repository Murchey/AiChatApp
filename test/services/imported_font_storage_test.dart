import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat/services/imported_font_storage.dart';

void main() {
  test('accepts only ttf files and keeps a readable storage name', () {
    expect(isSupportedImportedFontFile('NotoSansSC-Regular.ttf'), isTrue);
    expect(isSupportedImportedFontFile('NotoSansSC-Regular.TTF'), isTrue);
    expect(isSupportedImportedFontFile('NotoSansSC-Regular.otf'), isFalse);
    expect(importedFontStorageName('Noto Sans SC-Regular.ttf'),
        'Noto Sans SC-Regular');
  });

  test('font family is deterministic and safe for runtime registration', () {
    final family = importedFontFamily('Noto Sans SC-Regular');

    expect(family, startsWith('AiChatFont_'));
    expect(family, matches(RegExp(r'^AiChatFont_[0-9a-f]+$')));
    expect(importedFontFamily('Noto Sans SC-Regular'), family);
  });
}
