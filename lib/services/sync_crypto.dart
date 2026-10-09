import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';
import 'backup_crypto.dart';

/// Keys stay on the client. Nonces are fresh for each object revision.
class SyncCrypto {
  static Uint8List generateKey() => _random(32);

  /// Password-wrapped key bundle. The server never sees this bundle unless the
  /// user chooses to transfer it through another channel.
  static String exportKey(Uint8List key, String password) {
    if (key.length != 32 || password.length < 8) {
      throw ArgumentError('同步密钥或导出密码无效');
    }
    final encrypted = BackupCrypto.encrypt(
        Uint8List.fromList(utf8.encode(
            jsonEncode({'schemaVersion': 1, 'key': base64Encode(key)}))),
        password);
    return jsonEncode({
      'type': 'aichat-sync-key',
      'version': 1,
      'payload': base64Encode(encrypted)
    });
  }

  static Uint8List importKey(String bundle, String password) {
    try {
      final decoded = jsonDecode(bundle) as Map;
      if (decoded['type'] != 'aichat-sync-key' || decoded['version'] != 1)
        throw const FormatException('同步密钥格式无效');
      final plain = BackupCrypto.decrypt(
          base64Decode(decoded['payload'] as String), password);
      final data = jsonDecode(utf8.decode(plain)) as Map;
      final key = base64Decode(data['key'] as String);
      if (data['schemaVersion'] != 1 || key.length != 32)
        throw const FormatException('同步密钥格式无效');
      return Uint8List.fromList(key);
    } catch (error) {
      if (error is FormatException) rethrow;
      throw const FormatException('同步密钥错误、密码错误或内容已损坏');
    }
  }

  static Map<String, Object> encrypt(
      Map<String, Object?> payload, Uint8List key, int baseRevision) {
    if (key.length != 32) throw ArgumentError('同步密钥必须为32字节');
    final nonce = _random(12);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    final encrypted =
        cipher.process(Uint8List.fromList(utf8.encode(jsonEncode(payload))));
    return {
      'baseRevision': baseRevision,
      'algorithm': 'AES-256-GCM',
      'nonce': base64Encode(nonce),
      'ciphertext': base64Encode(encrypted),
      'sha256': sha256.convert(encrypted).toString(),
    };
  }

  static Map<String, dynamic> decrypt(
      Map<String, dynamic> envelope, Uint8List key) {
    if (key.length != 32 || envelope['algorithm'] != 'AES-256-GCM') {
      throw const FormatException('同步加密格式无效');
    }
    final nonce = base64Decode(envelope['nonce'] as String);
    final encrypted = base64Decode(envelope['ciphertext'] as String);
    if (nonce.length != 12 ||
        sha256.convert(encrypted).toString() != envelope['sha256']) {
      throw const FormatException('同步对象已损坏');
    }
    try {
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
            false, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
      return (jsonDecode(utf8.decode(cipher.process(encrypted))) as Map)
          .cast<String, dynamic>();
    } catch (_) {
      throw const FormatException('同步密钥错误或认证标签无效');
    }
  }

  static Uint8List _random(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
        List.generate(length, (_) => random.nextInt(256)));
  }
}
