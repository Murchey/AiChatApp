import 'dart:convert';

/// Local configuration for the optional AiChat server.
///
/// Tokens exist in memory; ordinary JSON serialization excludes secrets.
class BackendConfig {
  final String baseUrl;
  final String port;
  final String scheme;
  final String deviceId;
  final String accessToken;
  final String refreshToken;
  final DateTime? accessExpiresAt;
  final DateTime? refreshExpiresAt;
  final Map<String, bool> featureFlags;
  final DateTime? lastSuccessfulAt;

  const BackendConfig({
    this.baseUrl = '',
    this.port = '',
    this.scheme = 'https',
    this.deviceId = '',
    this.accessToken = '',
    this.refreshToken = '',
    this.accessExpiresAt,
    this.refreshExpiresAt,
    this.featureFlags = const <String, bool>{},
    this.lastSuccessfulAt,
  });

  bool get hasEndpoint => baseUrl.trim().isNotEmpty;
  bool get hasSession => accessToken.trim().isNotEmpty;

  bool get accessExpired {
    final expiry = accessExpiresAt;
    return accessToken.trim().isEmpty ||
        (expiry != null &&
            !expiry.isAfter(
                DateTime.now().toUtc().add(const Duration(seconds: 30))));
  }

  Uri endpoint(String path, [Map<String, String>? query]) {
    var raw = baseUrl.trim();
    if (raw.isEmpty) throw const FormatException('请先填写服务器地址');
    if (!raw.contains('://')) {
      raw = '${scheme.trim().isEmpty ? 'https' : scheme.trim()}://$raw';
    }
    final parsed = Uri.tryParse(raw);
    if (parsed == null ||
        parsed.host.isEmpty ||
        !['http', 'https'].contains(parsed.scheme) ||
        parsed.userInfo.isNotEmpty ||
        parsed.hasQuery ||
        parsed.hasFragment) {
      throw const FormatException('服务器地址无效');
    }
    var uri = parsed;
    if (port.trim().isNotEmpty) {
      final value = int.tryParse(port.trim());
      if (value == null || value < 1 || value > 65535) {
        throw const FormatException('端口号无效');
      }
      if (uri.hasPort && uri.port != value) {
        throw const FormatException('地址中的端口与端口设置不一致');
      }
      uri = uri.replace(port: value);
    }
    final basePath =
        uri.path.replaceAll(RegExp(r'/+'), '/').replaceAll(RegExp(r'/+$'), '');
    return uri.replace(
      path: '$basePath/${path.replaceFirst(RegExp(r'^/+'), '')}',
      queryParameters: query == null || query.isEmpty ? null : query,
    );
  }

  BackendConfig copyWith({
    String? baseUrl,
    String? port,
    String? scheme,
    String? deviceId,
    String? accessToken,
    String? refreshToken,
    DateTime? accessExpiresAt,
    DateTime? refreshExpiresAt,
    Map<String, bool>? featureFlags,
    DateTime? lastSuccessfulAt,
    bool clearAccessExpiry = false,
    bool clearRefreshExpiry = false,
    bool clearLastSuccessfulAt = false,
  }) {
    return BackendConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      port: port ?? this.port,
      scheme: scheme ?? this.scheme,
      deviceId: deviceId ?? this.deviceId,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      accessExpiresAt:
          clearAccessExpiry ? null : (accessExpiresAt ?? this.accessExpiresAt),
      refreshExpiresAt: clearRefreshExpiry
          ? null
          : (refreshExpiresAt ?? this.refreshExpiresAt),
      featureFlags: featureFlags ?? this.featureFlags,
      lastSuccessfulAt: clearLastSuccessfulAt
          ? null
          : (lastSuccessfulAt ?? this.lastSuccessfulAt),
    );
  }

  Map<String, dynamic> toJson({bool includeSecrets = false}) => {
        'base_url': baseUrl,
        'port': port,
        'scheme': scheme,
        'device_id': deviceId,
        if (includeSecrets) 'access_token': accessToken,
        if (includeSecrets) 'refresh_token': refreshToken,
        if (accessExpiresAt != null)
          'access_expires_at': accessExpiresAt!.toIso8601String(),
        if (refreshExpiresAt != null)
          'refresh_expires_at': refreshExpiresAt!.toIso8601String(),
        'feature_flags': featureFlags,
        if (lastSuccessfulAt != null)
          'last_successful_at': lastSuccessfulAt!.toIso8601String(),
      };

  factory BackendConfig.fromJson(Map<String, dynamic> json) {
    DateTime? parse(Object? value) =>
        value == null ? null : DateTime.tryParse(value.toString())?.toUtc();
    final flags = <String, bool>{};
    final rawFlags = json['feature_flags'];
    if (rawFlags is Map) {
      rawFlags.forEach((key, value) {
        if (value is bool) flags[key.toString()] = value;
      });
    }
    return BackendConfig(
      baseUrl: json['base_url']?.toString() ?? '',
      port: json['port']?.toString() ?? '',
      scheme: json['scheme']?.toString() ?? 'https',
      deviceId: json['device_id']?.toString() ?? '',
      accessToken: json['access_token']?.toString() ?? '',
      refreshToken: json['refresh_token']?.toString() ?? '',
      accessExpiresAt: parse(json['access_expires_at']),
      refreshExpiresAt: parse(json['refresh_expires_at']),
      featureFlags: flags,
      lastSuccessfulAt: parse(json['last_successful_at']),
    );
  }

  String encode() => jsonEncode(toJson());
}
