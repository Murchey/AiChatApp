import '../providers/backend_provider.dart';
import 'backend_http_client.dart';
import 'sync_outbox_store.dart';

/// Sync runs explicitly after the local transaction. No constructor sends HTTP.
class SyncService {
  final BackendProvider backend;
  final SyncOutboxStore outbox;
  Future<void>? _flush;
  final String? spaceId;
  SyncService({required this.backend, required this.outbox, this.spaceId});
  Map<String, String> get _headers =>
      spaceId == null ? const {} : {'X-Sync-Space': spaceId!};
  String _storageEndpoint(String endpoint) =>
      spaceId == null ? endpoint : '$endpoint|space:$spaceId';

  Future<void> enableDomain(String domain, bool enabled) async {
    _validateDomain(domain);
    await backend.requestModule('sync', '/api/sync/scopes/$domain',
        method: 'PUT', body: {'enabled': enabled}, headers: _headers);
  }

  Future<dynamic> manifest() =>
      backend.requestModule('sync', '/api/sync/manifest', headers: _headers);

  Future<Map<String, dynamic>> download(String domain) async {
    _validateDomain(domain);
    final result = await backend
        .requestModule('sync', '/api/sync/objects/$domain', headers: _headers);
    return _data(result);
  }

  Future<void> flush({BackendRequestScope? scope}) async {
    if (_flush != null) return _flush;
    final future = _uploadPending(scope);
    _flush = future;
    try {
      await future;
    } finally {
      if (identical(_flush, future)) _flush = null;
    }
  }

  Future<void> _uploadPending(BackendRequestScope? scope) async {
    await backend.init();
    if (!backend.isConfigured || !backend.isAuthenticated) return;
    final endpoint = backend.config.endpoint('').toString();
    final storageEndpoint = _storageEndpoint(endpoint);
    final device = backend.config.deviceId;
    for (var batch = 0; batch < 16; batch++) {
      final writes = await outbox.pending(storageEndpoint, device);
      if (writes.isEmpty) return;
      for (final write in writes) {
        scope?.check();
        if (endpoint != backend.config.endpoint('').toString() ||
            device != backend.config.deviceId) {
          throw const RequestCancelled();
        }
        _validateDomain(write.domain);
        try {
          final response = await backend.requestModule(
              'sync', '/api/sync/objects/${write.domain}',
              method: 'PUT',
              body: write.envelope,
              headers: {..._headers, 'Idempotency-Key': write.idempotencyKey},
              scope: scope);
          final data = _data(response);
          final revision = data['revision'];
          if (revision is! int ||
              revision != write.baseRevision + 1 ||
              data['sha256'] != write.envelope['sha256']) {
            throw const FormatException('服务器同步确认与本地对象不一致');
          }
          await outbox.acknowledge(write, revision);
        } on BackendException catch (error) {
          if (error.statusCode == 409) await outbox.conflict(write);
          rethrow;
        }
      }
    }
  }

  Future<List<Map<String, dynamic>>> listSpaces() async {
    final result = await backend.requestModule('sync', '/api/sync/spaces');
    final data = _data(result);
    return (data['items'] as List? ?? const [])
        .map((item) => (item as Map).cast<String, dynamic>())
        .toList();
  }

  Future<Map<String, dynamic>> createSpace() async {
    final result =
        await backend.requestModule('sync', '/api/sync/spaces', method: 'POST');
    return _data(result);
  }

  Future<Map<String, dynamic>> joinSpace(String code) async {
    final result = await backend.requestModule('sync', '/api/sync/spaces/join',
        method: 'POST', body: {'code': code});
    return _data(result);
  }

  Future<String> createInvite(String space) async {
    final result = await backend.requestModule(
        'sync', '/api/sync/spaces/$space/invites',
        method: 'POST');
    return _data(result)['joinCode'] as String;
  }

  Map<String, dynamic> _data(dynamic response) {
    final data = response is Map && response['data'] is Map
        ? response['data']
        : response;
    if (data is! Map) throw const FormatException('同步响应格式无效');
    return data.cast<String, dynamic>();
  }

  void _validateDomain(String domain) {
    if (!{'settings', 'characters', 'conversations', 'messages', 'memories'}
        .contains(domain)) {
      throw const FormatException('同步域不在白名单');
    }
  }
}
