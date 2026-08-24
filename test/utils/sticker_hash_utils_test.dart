import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat/utils/sticker_hash_utils.dart';

void main() {
  test('calculates a stable full SHA256 and short filename', () {
    final bytes = Uint8List.fromList(utf8.encode('sticker-data'));
    final hash = stickerSha256(bytes);

    expect(hash.length, 64);
    expect(stickerFileName(hash, r'C:\Pictures\sticker.PNG'),
        '${hash.substring(0, 16)}.png');
  });
}
