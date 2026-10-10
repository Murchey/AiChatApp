import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Non-secret metadata remains exportable in preferences. Credentials live in
/// the platform credential vault; legacy plaintext is migrated on first read.
class SecureConfigStorage {
  static const _vault = FlutterSecureStorage();
  static const _fields = {
    'apikey',
    'secretid',
    'secretkey',
    'accesskeyid',
    'secretaccesskey',
    'password',
    'token',
    'accesstoken',
    'refreshtoken',
  };
  static String _vaultKey(String key) => 'aichat_config_secrets_v1_$key';

  static dynamic _walk(dynamic value, String path,
      String Function(String path, String value) secret) {
    if (value is Map) {
      return value.map((k, v) {
        final p = '$path/${Uri.encodeComponent(k.toString())}';
        final sensitive =
            _fields.contains(k.toString().toLowerCase().replaceAll('_', ''));
        return MapEntry(k.toString(),
            sensitive && v is String ? secret(p, v) : _walk(v, p, secret));
      });
    }
    if (value is List) {
      return [
        for (var i = 0; i < value.length; i++)
          _walk(
              value[i],
              '$path/${value[i] is Map && value[i]['id'] != null ? Uri.encodeComponent(value[i]['id'].toString()) : i}',
              secret)
      ];
    }
    return value;
  }

  static Future<bool> writeJson(
      SharedPreferences prefs, String key, String text) async {
    final secrets = <String, String>{};
    final clean = _walk(jsonDecode(text), '', (path, value) {
      if (value.isNotEmpty) secrets[path] = value;
      return '';
    });
    await _vault.write(key: _vaultKey(key), value: jsonEncode(secrets));
    return prefs.setString(key, jsonEncode(clean));
  }

  static Future<String?> readJson(SharedPreferences prefs, String key) async {
    final text = prefs.getString(key);
    if (text == null) return null;
    final stored = await _vault.read(key: _vaultKey(key));
    final secrets =
        stored == null ? <String, dynamic>{} : jsonDecode(stored) as Map;
    var migrate = false;
    final restored = _walk(jsonDecode(text), '', (path, value) {
      if (value.isNotEmpty) {
        migrate = true;
        return value;
      }
      return secrets[path]?.toString() ?? '';
    });
    final result = jsonEncode(restored);
    if (migrate) await writeJson(prefs, key, result);
    return result;
  }

  static Future<String> readSecret(SharedPreferences prefs, String key) async {
    final legacy = prefs.getString(key);
    if (legacy != null && legacy.isNotEmpty) {
      await writeSecret(prefs, key, legacy);
      return legacy;
    }
    return await _vault.read(key: _vaultKey(key)) ?? '';
  }

  static Future<void> writeSecret(
      SharedPreferences prefs, String key, String value) async {
    if (value.isEmpty) {
      await _vault.delete(key: _vaultKey(key));
    } else {
      await _vault.write(key: _vaultKey(key), value: value);
    }
    await prefs.remove(key);
  }
}
