import '../models/backend_config.dart';
import '../models/story_package.dart';
import 'backend_http_client.dart';
import 'package:uuid/uuid.dart';

class StoryBackendService {
  final BackendHttpClient client;
  final BackendConfig config;
  final Future<String?> Function()? refreshAccessToken;

  const StoryBackendService({
    required this.client,
    required this.config,
    this.refreshAccessToken,
  });

  Future<dynamic> loadCatalog(
      {String? query,
      String? tag,
      String? cursor,
      int limit = 20,
      BackendRequestScope? scope}) {
    final params = <String, String>{
      if (query?.trim().isNotEmpty == true) 'q': query!.trim(),
      if (tag?.trim().isNotEmpty == true) 'tag': tag!.trim(),
      if (cursor?.trim().isNotEmpty == true) 'cursor': cursor!.trim(),
      'limit': '$limit',
    };
    return client.getJson(
      config.endpoint('/api/stories', params),
      token: config.accessToken,
      onUnauthorized: refreshAccessToken,
      scope: scope,
    );
  }

  Future<StoryPackage> loadPackage(StoryCatalogEntry entry,
      {BackendRequestScope? scope}) async {
    final decoded = await client.getJson(
      config.endpoint(
          '/api/stories/${Uri.encodeComponent(entry.storyId)}/download',
          {'version': '${entry.version}'}),
      token: config.accessToken,
      onUnauthorized: refreshAccessToken,
      scope: scope,
      requestTimeout: const Duration(seconds: 20),
      headers: {'Idempotency-Key': const Uuid().v4()},
    );
    if (decoded is! Map) throw const FormatException('服务器故事详情格式无效');
    return StoryPackage.fromJson(decoded.cast<String, dynamic>());
  }

  Future<void> testConnection() async {
    await client.getJson(config.endpoint('/api/health'),
        token: config.accessToken, onUnauthorized: refreshAccessToken);
    await client.getJson(config.endpoint('/api/version'),
        token: config.accessToken, onUnauthorized: refreshAccessToken);
  }
}
