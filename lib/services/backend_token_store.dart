import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class BackendTokenStore {
  Future<String?> read();
  Future<void> write(String session);
  Future<void> clear();
}

class SecureBackendTokenStore implements BackendTokenStore {
  final String key;
  final FlutterSecureStorage storage;
  const SecureBackendTokenStore(
      {this.storage = const FlutterSecureStorage(),
      this.key = 'aichat_backend_session_v1'});
  @override
  Future<String?> read() => storage.read(key: key);
  @override
  Future<void> write(String session) => storage.write(key: key, value: session);
  @override
  Future<void> clear() => storage.delete(key: key);
}
