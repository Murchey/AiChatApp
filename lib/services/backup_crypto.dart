import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// 备份包可选加密：AES-256-GCM + PBKDF2（对齐 inkqilin-ledger 的 BackupCrypto）。
///
/// 密文布局：
///   MAGIC(5) | SALT(16) | IV(12) | ciphertext+tag
class BackupCrypto {
  static const List<int> _magic = [0x41, 0x49, 0x42, 0x4B, 0x31]; // "AIBK1"
  static const int _saltLen = 16;
  static const int _ivLen = 12;
  static const int _keyBits = 256;
  static const int _pbkdf2Iterations = 120000;
  static const int _gcmTagBits = 128;

  static bool isEncrypted(Uint8List data) {
    if (data.length < _magic.length + _saltLen + _ivLen) return false;
    for (var i = 0; i < _magic.length; i++) {
      if (data[i] != _magic[i]) return false;
    }
    return true;
  }

  static Uint8List encrypt(Uint8List plain, String password) {
    if (password.isEmpty) {
      throw ArgumentError('密码不能为空');
    }
    final random = Random.secure();
    final salt = Uint8List.fromList(
      List<int>.generate(_saltLen, (_) => random.nextInt(256)),
    );
    final iv = Uint8List.fromList(
      List<int>.generate(_ivLen, (_) => random.nextInt(256)),
    );
    final key = _deriveKey(password, salt);
    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(
      true,
      AEADParameters(KeyParameter(key), _gcmTagBits, iv, Uint8List(0)),
    );
    final ct = cipher.process(plain);
    return Uint8List.fromList([..._magic, ...salt, ...iv, ...ct]);
  }

  /// 解密；密码错误或数据损坏时抛出 [ArgumentError]。
  static Uint8List decrypt(Uint8List data, String password) {
    if (!isEncrypted(data)) return data;
    if (password.isEmpty) {
      throw ArgumentError('请输入备份密码');
    }
    final offset = _magic.length;
    final salt = Uint8List.fromList(data.sublist(offset, offset + _saltLen));
    final iv = Uint8List.fromList(
      data.sublist(offset + _saltLen, offset + _saltLen + _ivLen),
    );
    final ct = Uint8List.fromList(
      data.sublist(offset + _saltLen + _ivLen),
    );
    final key = _deriveKey(password, salt);
    try {
      final cipher = GCMBlockCipher(AESEngine());
      cipher.init(
        false,
        AEADParameters(KeyParameter(key), _gcmTagBits, iv, Uint8List(0)),
      );
      return cipher.process(ct);
    } catch (_) {
      throw ArgumentError('密码错误或备份文件已损坏');
    }
  }

  static Uint8List _deriveKey(String password, Uint8List salt) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, _pbkdf2Iterations, _keyBits ~/ 8));
    return derivator.process(Uint8List.fromList(utf8.encode(password)));
  }
}
