import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat/services/backup_crypto.dart';

void main() {
  group('BackupCrypto', () {
    test('encrypt/decrypt roundtrip with password', () {
      final plain = Uint8List.fromList(utf8.encode('Hello AiChat 备份数据 🎉'));
      final enc = BackupCrypto.encrypt(plain, 'secret-password');
      expect(BackupCrypto.isEncrypted(enc), isTrue);
      final dec = BackupCrypto.decrypt(enc, 'secret-password');
      expect(utf8.decode(dec), equals('Hello AiChat 备份数据 🎉'));
    });

    test('reject empty password on encrypt', () {
      final plain = Uint8List.fromList([1, 2, 3]);
      expect(
        () => BackupCrypto.encrypt(plain, ''),
        throwsArgumentError,
      );
    });

    test('wrong password throws', () {
      final plain = Uint8List.fromList([1, 2, 3, 4, 5]);
      final enc = BackupCrypto.encrypt(plain, 'right');
      expect(
        () => BackupCrypto.decrypt(enc, 'wrong'),
        throwsArgumentError,
      );
    });

    test('plaintext passthrough when not encrypted', () {
      final plain = Uint8List.fromList(utf8.encode('raw-zip-bytes'));
      expect(BackupCrypto.isEncrypted(plain), isFalse);
      final dec = BackupCrypto.decrypt(plain, '');
      expect(dec, equals(plain));
    });

    test('empty password on encrypted payload throws', () {
      final plain = Uint8List.fromList([9, 9, 9]);
      final enc = BackupCrypto.encrypt(plain, 'pwd');
      expect(
        () => BackupCrypto.decrypt(enc, ''),
        throwsArgumentError,
      );
    });
  });
}
