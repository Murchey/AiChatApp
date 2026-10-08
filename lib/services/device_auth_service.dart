import '../models/backend_config.dart';
import 'backend_http_client.dart';

class DeviceTokenPair {
  final String accessToken;
  final String refreshToken;
  final DateTime? accessExpiresAt;
  final DateTime? refreshExpiresAt;

  const DeviceTokenPair({
    required this.accessToken,
    required this.refreshToken,
    this.accessExpiresAt,
    this.refreshExpiresAt,
  });

  factory DeviceTokenPair.fromJson(dynamic decoded) {
    final data = decoded is Map && decoded['data'] is Map
        ? decoded['data'] as Map
        : decoded;
    if (data is! Map ||
        data['accessToken'] == null ||
        data['refreshToken'] == null ||
        data['accessToken'].toString().isEmpty ||
        data['refreshToken'].toString().isEmpty) {
      throw const FormatException('服务器认证响应缺少令牌');
    }
    DateTime? parse(Object? value) =>
        value == null ? null : DateTime.tryParse(value.toString())?.toUtc();
    return DeviceTokenPair(
      accessToken: data['accessToken'].toString(),
      refreshToken: data['refreshToken'].toString(),
      accessExpiresAt:
          parse(data['accessExpiresAt'] ?? data['access_expires_at']),
      refreshExpiresAt:
          parse(data['refreshExpiresAt'] ?? data['refresh_expires_at']),
    );
  }
}

class DeviceAuthService {
  final BackendHttpClient client;

  const DeviceAuthService(this.client);

  Future<DeviceTokenPair> exchangeInvite(
    BackendConfig config,
    String inviteCode, {
    String label = 'AiChat device',
    BackendRequestScope? scope,
  }) async {
    final decoded = await client.postJson(
      config.endpoint('/api/invite/exchange'),
      scope: scope,
      body: {
        'inviteCode': inviteCode.trim(),
        'deviceId': config.deviceId,
        'label': label,
      },
    );
    return DeviceTokenPair.fromJson(decoded);
  }

  Future<DeviceTokenPair> refresh(BackendConfig config) async {
    if (config.refreshToken.trim().isEmpty) {
      throw const BackendException(
          statusCode: 401, code: 'REFRESH_REQUIRED', message: '请重新绑定服务器');
    }
    final decoded = await client.postJson(
      config.endpoint('/api/auth/refresh'),
      body: {'refreshToken': config.refreshToken},
    );
    return DeviceTokenPair.fromJson(decoded);
  }
}
