import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

import 'backup_crypto.dart';
import 'backup_service.dart';
import 'cos_auth.dart';

/// 云端对象列表项
class CloudBackupItem {
  final String key;
  final int size;
  final String lastModified;

  const CloudBackupItem({
    required this.key,
    required this.size,
    required this.lastModified,
  });

  String get fileName {
    final i = key.lastIndexOf('/');
    return i < 0 ? key : key.substring(i + 1);
  }
}

/// 云备份对象储存配置（腾讯云 COS / 阿里云 OSS）。
/// 密钥仅保存在本机 SharedPreferences。
class CloudBackupConfig {
  final String secretId;
  final String secretKey;

  /// 完整存储桶访问域名，如
  /// https://xxx-1250000000.cos.ap-guangzhou.myqcloud.com
  /// 或 https://xxx.oss-cn-hangzhou.aliyuncs.com
  final String bucketUrl;
  final String prefix;

  const CloudBackupConfig({
    this.secretId = '',
    this.secretKey = '',
    this.bucketUrl = '',
    this.prefix = 'backups/v1',
  });

  bool get isConfigured =>
      secretId.trim().isNotEmpty &&
      secretKey.trim().isNotEmpty &&
      host.isNotEmpty;

  String get host {
    var s = bucketUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (s.isEmpty) return '';
    s = s.replaceFirst(RegExp(r'^https?://'), '');
    return s.split('/').first.split('?').first.split('#').first;
  }

  String get scheme {
    final s = bucketUrl.trim().toLowerCase();
    return s.startsWith('http://') ? 'http' : 'https';
  }

  /// 用于状态展示的短标识
  String get bucketLabel {
    final h = host;
    final tencent = h.split('.cos.').first;
    if (tencent.isNotEmpty && tencent != h) return tencent;
    final oss = h.split('.oss-').first.split('.oss.').first;
    if (oss.isNotEmpty && oss != h) return oss;
    return h;
  }

  CosVendor get vendor => detectCosVendor(host);

  String get vendorLabel => switch (vendor) {
        CosVendor.tencent => '腾讯云 COS',
        CosVendor.aliyun => '阿里云 OSS',
        CosVendor.other => '对象储存',
      };

  String get normalizedPrefix {
    final p = prefix.trim();
    return p.isEmpty ? 'backups/v1' : p;
  }

  CloudBackupConfig copyWith({
    String? secretId,
    String? secretKey,
    String? bucketUrl,
    String? prefix,
  }) {
    return CloudBackupConfig(
      secretId: secretId ?? this.secretId,
      secretKey: secretKey ?? this.secretKey,
      bucketUrl: bucketUrl ?? this.bucketUrl,
      prefix: prefix ?? this.prefix,
    );
  }

  Map<String, dynamic> toJson() => {
        'secretId': secretId,
        'secretKey': secretKey,
        'bucketUrl': bucketUrl,
        'prefix': prefix,
      };

  factory CloudBackupConfig.fromJson(Map<String, dynamic> json) {
    return CloudBackupConfig(
      secretId: json['secretId'] as String? ?? '',
      secretKey: json['secretKey'] as String? ?? '',
      bucketUrl: json['bucketUrl'] as String? ?? '',
      prefix: json['prefix'] as String? ?? 'backups/v1',
    );
  }
}

/// 云端全量备份：上传 / 列表 / 下载恢复 / 删除。
/// 对齐 inkqilin-ledger 的云备份能力，同时支持腾讯云 COS 与阿里云 OSS。
class CloudBackupService {
  static const _secretIdKey = 'cloud_backup_secret_id';
  static const _secretKeyKey = 'cloud_backup_secret_key';
  static const _bucketUrlKey = 'cloud_backup_bucket_url';
  static const _prefixKey = 'cloud_backup_prefix';

  static Future<CloudBackupConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return CloudBackupConfig(
      secretId: prefs.getString(_secretIdKey) ?? '',
      secretKey: prefs.getString(_secretKeyKey) ?? '',
      bucketUrl: prefs.getString(_bucketUrlKey) ?? '',
      prefix: prefs.getString(_prefixKey) ?? 'backups/v1',
    );
  }

  static Future<void> saveConfig(CloudBackupConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    final id = config.secretId.trim();
    final key = config.secretKey.trim();
    final url = config.bucketUrl.trim();
    final prefix = config.normalizedPrefix;
    if (id.isEmpty) {
      await prefs.remove(_secretIdKey);
    } else {
      await prefs.setString(_secretIdKey, id);
    }
    if (key.isEmpty) {
      await prefs.remove(_secretKeyKey);
    } else {
      await prefs.setString(_secretKeyKey, key);
    }
    if (url.isEmpty) {
      await prefs.remove(_bucketUrlKey);
    } else {
      await prefs.setString(_bucketUrlKey, url);
    }
    await prefs.setString(_prefixKey, prefix);
  }

  static String _objectPrefix(CloudBackupConfig config) {
    final p = config.normalizedPrefix.replaceAll(RegExp(r'^/+|/+$'), '');
    return p.isEmpty ? 'backups/v1' : p;
  }

  /// 对象完整 key：`backups/v1/aichat_xxx.zip`
  static String objectKey(CloudBackupConfig config, String fileName) {
    return '${_objectPrefix(config)}/$fileName';
  }

  static Uri _objectUri(CloudBackupConfig config, String key) {
    final segments = key
        .split('/')
        .where((s) => s.isNotEmpty)
        .map(Uri.encodeComponent)
        .toList();
    return Uri(
      scheme: config.scheme,
      host: config.host,
      pathSegments: segments,
    );
  }

  static Map<String, String> _authHeaders({
    required CloudBackupConfig config,
    required String method,
    required Uri uri,
    String? contentType,
  }) {
    return buildCosAuthHeaders(
      method: method,
      uri: uri,
      accessKeyId: config.secretId,
      secretAccessKey: config.secretKey,
      contentType: contentType,
    );
  }

  static Never _throwStatus(
    int status,
    String body,
    String action,
    CloudBackupConfig config,
  ) {
    final code = _errorCode(body);
    if (status == 403) {
      throw HttpException(
        '$action被拒绝（HTTP 403${code.isEmpty ? '' : ' / $code'}）。'
        '请检查 SecretId/SecretKey 是否配对、密钥是否有效，'
        '以及子账号是否有该存储桶的读写权限。',
      );
    }
    if (status == 404) {
      throw HttpException('$action失败：对象不存在（HTTP 404）');
    }
    throw HttpException(
      '$action失败（HTTP $status${code.isEmpty ? '' : ' / $code'}）',
    );
  }

  static String _errorCode(String body) {
    try {
      final doc = XmlDocument.parse(body);
      for (final e in doc.descendantElements) {
        if (e.name.local == 'Code') return e.innerText.trim();
      }
    } catch (_) {}
    return body.length > 200 ? body.substring(0, 200) : body;
  }

  /// 上传备份到云端；[password] 非空则加密整包。
  static Future<CloudBackupItem> uploadBackup(
    CloudBackupConfig config, {
    String? password,
  }) async {
    if (!config.isConfigured) {
      throw StateError('请先配置对象储存（SecretId / SecretKey / 存储桶 URL）');
    }
    final export = await BackupService.exportBackupZip(password: password);
    final key = objectKey(config, export.fileName);
    final uri = _objectUri(config, key);
    const contentType = 'application/octet-stream';
    final headers = {
      ..._authHeaders(
        config: config,
        method: 'PUT',
        uri: uri,
        contentType: contentType,
      ),
      'Content-Type': contentType,
    };
    final resp = await http
        .put(uri, headers: headers, body: export.bytes)
        .timeout(const Duration(minutes: 5));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      _throwStatus(
        resp.statusCode,
        utf8.decode(resp.bodyBytes, allowMalformed: true),
        '上传',
        config,
      );
    }
    return CloudBackupItem(
      key: key,
      size: export.size,
      lastModified: DateTime.now().toUtc().toIso8601String(),
    );
  }

  /// 列出云端备份（按前缀过滤 zip / 加密包）。
  static Future<List<CloudBackupItem>> listBackups(
    CloudBackupConfig config,
  ) async {
    if (!config.isConfigured) {
      throw StateError('请先配置对象储存');
    }
    final prefix = '${_objectPrefix(config)}/';
    final listUri = Uri(
      scheme: config.scheme,
      host: config.host,
      path: '/',
      queryParameters: {
        'list-type': '2',
        'prefix': prefix,
        'max-keys': '1000',
      },
    );
    final resp = await http
        .get(
          listUri,
          headers: _authHeaders(config: config, method: 'GET', uri: listUri),
        )
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      _throwStatus(
        resp.statusCode,
        utf8.decode(resp.bodyBytes, allowMalformed: true),
        '列表',
        config,
      );
    }
    final body = utf8.decode(resp.bodyBytes, allowMalformed: true);
    final items = _parseListXml(body)
        .where((e) =>
            e.key.endsWith('.zip') || e.key.toLowerCase().endsWith('.aibackup'))
        .toList()
      ..sort((a, b) => b.lastModified.compareTo(a.lastModified));
    return items;
  }

  static List<CloudBackupItem> _parseListXml(String xml) {
    if (xml.trim().isEmpty) return const [];
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xml);
    } catch (_) {
      return const [];
    }
    final result = <CloudBackupItem>[];
    for (final content in doc.descendantElements) {
      if (content.name.local != 'Contents') continue;
      String? key;
      var size = 0;
      var lastModified = '';
      for (final child in content.childElements) {
        switch (child.name.local) {
          case 'Key':
            key = child.innerText.trim();
          case 'Size':
            size = int.tryParse(child.innerText.trim()) ?? 0;
          case 'LastModified':
            lastModified = child.innerText.trim();
        }
      }
      if (key == null || key.isEmpty) continue;
      result.add(CloudBackupItem(
        key: key,
        size: size,
        lastModified: lastModified,
      ));
    }
    return result;
  }

  /// 下载云端备份字节（不解密）。
  static Future<Uint8List> downloadObject(
    CloudBackupConfig config,
    String key,
  ) async {
    if (!config.isConfigured) {
      throw StateError('请先配置对象储存');
    }
    final uri = _objectUri(config, key);
    final resp = await http
        .get(uri, headers: _authHeaders(config: config, method: 'GET', uri: uri))
        .timeout(const Duration(minutes: 5));
    if (resp.statusCode != 200) {
      _throwStatus(
        resp.statusCode,
        utf8.decode(resp.bodyBytes, allowMalformed: true),
        '下载',
        config,
      );
    }
    return resp.bodyBytes;
  }

  /// 下载并恢复到本地；加密包需提供 [password]。
  static Future<void> downloadAndRestore(
    CloudBackupConfig config,
    String key, {
    String? password,
  }) async {
    final raw = await downloadObject(config, key);
    final zipBytes = BackupCrypto.isEncrypted(raw)
        ? BackupCrypto.decrypt(raw, password ?? '')
        : raw;
    await BackupService.restoreZipBytes(zipBytes);
  }

  /// 删除云端备份，并确认远端已不存在。
  static Future<void> deleteBackup(
    CloudBackupConfig config,
    String key,
  ) async {
    if (!config.isConfigured) {
      throw StateError('请先配置对象储存');
    }
    final uri = _objectUri(config, key);
    final resp = await http
        .delete(
          uri,
          headers: _authHeaders(config: config, method: 'DELETE', uri: uri),
        )
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      _throwStatus(
        resp.statusCode,
        utf8.decode(resp.bodyBytes, allowMalformed: true),
        '删除',
        config,
      );
    }
    if (await objectExists(config, key)) {
      throw StateError('云端对象删除后仍存在，请检查存储桶是否开启了版本控制');
    }
  }

  /// HEAD 探测对象是否存在。
  static Future<bool> objectExists(
    CloudBackupConfig config,
    String key,
  ) async {
    if (!config.isConfigured) {
      throw StateError('请先配置对象储存');
    }
    final uri = _objectUri(config, key);
    final resp = await http
        .head(uri, headers: _authHeaders(config: config, method: 'HEAD', uri: uri))
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode == 200) return true;
    if (resp.statusCode == 404) return false;
    _throwStatus(
      resp.statusCode,
      '',
      '探测对象',
      config,
    );
  }

  /// 归一化存储桶 URL：自动补 https://，去掉尾斜杠。
  static String normalizeBucketUrl(String input) {
    var s = input.trim();
    if (s.isEmpty) return '';
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'https://$s';
    }
    return s.replaceAll(RegExp(r'/+$'), '');
  }
}
