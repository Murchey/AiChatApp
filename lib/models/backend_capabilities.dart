class BackendCapabilities {
  final String serverVersion;
  final String apiVersion;
  final String minClientVersion;
  final Map<String, bool> features;

  const BackendCapabilities({
    this.serverVersion = '',
    this.apiVersion = '',
    this.minClientVersion = '',
    this.features = const <String, bool>{},
  });

  bool get storiesEnabled => features['stories'] ?? false;

  Map<String, dynamic> toJson() => {
        'serverVersion': serverVersion,
        'apiVersion': apiVersion,
        'minClientVersion': minClientVersion,
        'features': features
      };

  factory BackendCapabilities.fromJson(dynamic decoded) {
    final raw =
        decoded is Map && decoded['data'] is Map ? decoded['data'] : decoded;
    if (raw is! Map) throw const FormatException('服务器版本响应格式无效');
    final flags = <String, bool>{};
    final rawFlags = raw['features'];
    if (rawFlags is Map) {
      rawFlags.forEach((key, value) {
        if (value is bool) flags[key.toString()] = value;
      });
    }
    return BackendCapabilities(
      serverVersion: raw['serverVersion']?.toString() ?? '',
      apiVersion: raw['apiVersion']?.toString() ?? '',
      minClientVersion: raw['minClientVersion']?.toString() ?? '',
      features: flags,
    );
  }
}
