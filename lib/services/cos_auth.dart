import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 对象储存私有读鉴权（访问密钥）
class CosAuth {
  final bool enabled;
  final String accessKeyId;
  final String secretAccessKey;

  const CosAuth({
    this.enabled = false,
    this.accessKeyId = '',
    this.secretAccessKey = '',
  });

  bool get isConfigured =>
      enabled && accessKeyId.trim().isNotEmpty && secretAccessKey.trim().isNotEmpty;

  CosAuth copyWith({
    bool? enabled,
    String? accessKeyId,
    String? secretAccessKey,
  }) {
    return CosAuth(
      enabled: enabled ?? this.enabled,
      accessKeyId: accessKeyId ?? this.accessKeyId,
      secretAccessKey: secretAccessKey ?? this.secretAccessKey,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'accessKeyId': accessKeyId,
        'secretAccessKey': secretAccessKey,
      };

  factory CosAuth.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const CosAuth();
    return CosAuth(
      enabled: json['enabled'] as bool? ?? false,
      accessKeyId: json['accessKeyId'] as String? ?? '',
      secretAccessKey: json['secretAccessKey'] as String? ?? '',
    );
  }
}

/// 按 host 识别对象储存厂商，用于选择签名算法。
enum CosVendor {
  tencent,
  aliyun,
  other,
}

CosVendor detectCosVendor(String host) {
  final h = host.toLowerCase();
  if (h.endsWith('myqcloud.com') ||
      h.contains('.cos.') ||
      h.contains('.cos-')) {
    return CosVendor.tencent;
  }
  if (h.endsWith('aliyuncs.com') ||
      h.contains('.oss-') ||
      h.contains('.oss.')) {
    return CosVendor.aliyun;
  }
  return CosVendor.other;
}

List<int> _hmacSha1(List<int> key, String data) {
  final mac = Hmac(sha1, key);
  return mac.convert(utf8.encode(data)).bytes;
}

String _sha1Hex(String data) => sha1.convert(utf8.encode(data)).toString();

String _base64(List<int> bytes) => base64Encode(bytes);

String _httpDate([DateTime? time]) {
  final t = time ?? DateTime.now().toUtc();
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  String two(int n) => n.toString().padLeft(2, '0');
  return '${days[t.weekday - 1]}, ${two(t.day)} ${months[t.month - 1]} '
      '${t.year} ${two(t.hour)}:${two(t.minute)}:${two(t.second)} GMT';
}

/// 为对象储存请求生成鉴权请求头。
/// 目前支持腾讯云 COS 与阿里云 OSS；其它厂商返回空 map（退回匿名）。
///
/// [contentType] / [contentMd5] 仅在请求实际携带对应头时传入：
/// 阿里云 OSS V1 会把它们纳入 StringToSign；腾讯云 q-sign 默认只签 host。
Map<String, String> buildCosAuthHeaders({
  required String method,
  required Uri uri,
  required String accessKeyId,
  required String secretAccessKey,
  DateTime? now,
  String? contentType,
  String? contentMd5,
  Map<String, String> extraHeaders = const {},
}) {
  final ak = accessKeyId.trim();
  final sk = secretAccessKey.trim();
  if (ak.isEmpty || sk.isEmpty) return const {};

  final vendor = detectCosVendor(uri.host);
  switch (vendor) {
    case CosVendor.tencent:
      return _signTencentCos(
        method: method,
        uri: uri,
        secretId: ak,
        secretKey: sk,
        now: now,
      );
    case CosVendor.aliyun:
      return _signAliyunOss(
        method: method,
        uri: uri,
        accessKeyId: ak,
        accessKeySecret: sk,
        now: now,
        contentType: contentType,
        contentMd5: contentMd5,
        extraHeaders: extraHeaders,
      );
    case CosVendor.other:
      return const {};
  }
}

/// 腾讯云 COS：q-sign-algorithm=sha1 头部签名
/// 算法见 https://cloud.tencent.com/document/product/436/7778
Map<String, String> _signTencentCos({
  required String method,
  required Uri uri,
  required String secretId,
  required String secretKey,
  DateTime? now,
}) {
  final start = (now ?? DateTime.now().toUtc()).millisecondsSinceEpoch ~/ 1000;
  final end = start + 3600;
  final keyTime = '$start;$end';

  // SignKey = hex(HMAC-SHA1(SecretKey, KeyTime))
  final signKeyHex = _hex(_hmacSha1(utf8.encode(secretKey), keyTime));

  // UriPathname：COS 官方示例中 HttpString 使用「解码后」的路径
  // （请求行是 %E8%85%BE...，签名串是 腾讯云）。
  // Dart Uri.path 保留百分号编码，必须用 pathSegments 还原。
  final pathname = uri.pathSegments.isEmpty
      ? '/'
      : '/${uri.pathSegments.join('/')}';

  // UrlParamList / HttpParameters：key 小写并 UrlEncode，value UrlEncode，再按字典序排序
  final params = uri.queryParameters;
  final encoded = <String, String>{};
  for (final e in params.entries) {
    encoded[Uri.encodeComponent(e.key.toLowerCase())] =
        Uri.encodeComponent(e.value);
  }
  final sortedKeys = encoded.keys.toList()..sort();
  final httpParameters =
      sortedKeys.map((k) => '$k=${encoded[k]}').join('&');
  final urlParamList = sortedKeys.join(';');

  // 仅签名 host 头
  final hostHeader = 'host=${Uri.encodeComponent(uri.host.toLowerCase())}\n';

  // HttpMethod 必须小写；HttpString 末尾保留换行
  final httpString =
      '${method.toLowerCase()}\n$pathname\n$httpParameters\n$hostHeader';
  final stringToSign = 'sha1\n$keyTime\n${_sha1Hex(httpString)}\n';

  // Signature = HMAC-SHA1(SignKey 的十六进制字符串, StringToSign)
  final signature = _hex(_hmacSha1(utf8.encode(signKeyHex), stringToSign));

  final authorization = 'q-sign-algorithm=sha1'
      '&q-ak=$secretId'
      '&q-sign-time=$keyTime'
      '&q-key-time=$keyTime'
      '&q-header-list=host'
      '&q-url-param-list=$urlParamList'
      '&q-signature=$signature';

  return {
    'Authorization': authorization,
  };
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// 阿里云 OSS V1：Authorization: OSS {ak}:{base64(hmac-sha1)}
/// 规则见 https://help.aliyun.com/document_detail/31951.html
Map<String, String> _signAliyunOss({
  required String method,
  required Uri uri,
  required String accessKeyId,
  required String accessKeySecret,
  DateTime? now,
  String? contentType,
  String? contentMd5,
  Map<String, String> extraHeaders = const {},
}) {
  final date = _httpDate(now);
  // 虚拟主机风格：host 第一段为 bucket 名
  final host = uri.host.toLowerCase();
  final bucket = host.split('.').first;
  // OSS CanonicalizedResource 使用原始 Object Key（解码后的中文/括号），
  // 与腾讯云「用请求行里已编码的 path」不同。
  final objectKey = uri.pathSegments.isEmpty
      ? '/'
      : '/${uri.pathSegments.join('/')}';

  // 仅「子资源」参与 CanonicalizedResource；list 相关参数需纳入签名
  final params = uri.queryParameters;
  final signedKeys = params.keys
      .where((k) => k.startsWith('x-oss-') || _ossSignedSubResources.contains(k))
      .toList()
    ..sort();
  final sub = signedKeys.isEmpty
      ? ''
      : '?${signedKeys.map((k) => '$k=${params[k] ?? ''}').join('&')}';
  // 仅 bucket 时资源为 /bucket/，有 object 时为 /bucket/object
  final canonicalizedResource = '/$bucket$objectKey$sub';

  // CanonicalizedOSSHeaders：x-oss-* 头按字典序参与签名
  final ossHeaders = <String, String>{};
  for (final e in extraHeaders.entries) {
    final k = e.key.toLowerCase();
    if (k.startsWith('x-oss-')) {
      ossHeaders[k] = e.value.trim();
    }
  }
  final sortedHeaderKeys = ossHeaders.keys.toList()..sort();
  final canonicalizedOssHeaders = sortedHeaderKeys.isEmpty
      ? ''
      : sortedHeaderKeys.map((k) => '$k:${ossHeaders[k]}\n').join();

  // 官方公式：
  // VERB\nContent-MD5\nContent-Type\nDate\nCanonicalizedOSSHeadersCanonicalizedResource
  // CanonicalizedOSSHeaders 为空时直接拼接 Resource，中间不能多出 \n
  final stringToSign = '${method.toUpperCase()}\n'
      '${contentMd5 ?? ''}\n'
      '${contentType ?? ''}\n'
      '$date\n'
      '$canonicalizedOssHeaders'
      '$canonicalizedResource';

  final sig = _base64(_hmacSha1(utf8.encode(accessKeySecret), stringToSign));

  return {
    'Date': date,
    'Authorization': 'OSS $accessKeyId:$sig',
  };
}

/// OSS V1 签名时需纳入 CanonicalizedResource 的子资源参数
const Set<String> _ossSignedSubResources = {
  'acl',
  'uploads',
  'uploadId',
  'partNumber',
  'security-token',
  'position',
  'append',
  'location',
  'cors',
  'logging',
  'website',
  'referer',
  'lifecycle',
  'delete',
  'tagging',
  'objectMeta',
  'versioning',
  'versionId',
  'versions',
  'restore',
  'policy',
  'stat',
  'encryption',
  'inventory',
  'inventoryId',
  'continuation-token',
  'start-after',
  'fetch-owner',
  // ListObjects / ListObjectsV2
  'list-type',
  'prefix',
  'delimiter',
  'marker',
  'max-keys',
  'encoding-type',
  // GetObject 响应头覆写
  'response-content-type',
  'response-content-language',
  'response-expires',
  'response-cache-control',
  'response-content-disposition',
  'response-content-encoding',
};
