import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/backend_token_store.dart';
import '../services/storage_migration_service.dart';
import '../services/sync_crypto.dart';
import '../services/sync_outbox_store.dart';
import '../services/sync_service.dart';
import 'backend_provider.dart';
import 'settings_provider.dart';

/// Opt-in settings pilot. No chats, bubbles, credentials or file paths are read.
/// Merely constructing this provider does not open the database or send HTTP.
class SyncProvider extends ChangeNotifier {
  final BackendProvider backend;
  final SettingsProvider settings;
  final BackendTokenStore Function(String) keyStoreFactory;
  bool enabled = false;
  bool busy = false;
  String? error;
  String? _identity;
  Uint8List? _key;
  SyncOutboxStore? _outbox;
  Future<void> _writes = Future.value();
  bool _disposed = false;
  bool _applying = false;
  String? spaceId;
  String? lastJoinCode;
  String? _lastSnapshot;
  Object? _writeFailure;
  SyncProvider(
      {required this.backend,
      required this.settings,
      SyncOutboxStore? outbox,
      BackendTokenStore Function(String)? keyStoreFactory})
      : _outbox = outbox,
        keyStoreFactory =
            keyStoreFactory ?? ((key) => SecureBackendTokenStore(key: key)) {
    settings.addListener(_settingsChanged);
    backend.addListener(_backendChanged);
  }
  String get _scope =>
      '${backend.config.endpoint('')}|${backend.config.deviceId}';
  String get _storageKey => sha256.convert(utf8.encode(_scope)).toString();
  SyncService get _service =>
      SyncService(backend: backend, outbox: _outbox!, spaceId: spaceId);
  String _endpointScope(String endpoint) =>
      spaceId == null ? endpoint : '$endpoint|space:$spaceId';
  void _backendChanged() {
    if (_identity != null && _identity != _scope) {
      enabled = false;
      _key = null;
      _identity = null;
      _lastSnapshot = null;
      _notify();
    }
  }

  Future<void> init() async {
    await backend.init();
    final identity = _scope;
    if (_identity == identity) return;
    final prefs = await SharedPreferences.getInstance();
    spaceId = prefs.getString('sync_space_$_storageKey');
    final saved = await keyStoreFactory('sync_key_$_storageKey').read();
    if (identity != _scope) throw StateError('服务器配置已变化，请重试');
    _key = saved == null ? null : base64Decode(saved);
    enabled = prefs.getBool('sync_settings_$_storageKey') == true &&
        _key?.length == 32;
    _identity = identity;
    _outbox ??= SyncOutboxStore(StorageMigrationService.database);
    _notify();
  }

  Future<void> setEnabled(bool value) => _run(() async {
        await init();
        final identity = _scope;
        final storageKey = _storageKey;
        if (value && _key == null) {
          final key = SyncCrypto.generateKey();
          // No plaintext preference fallback if the platform keystore fails.
          await keyStoreFactory('sync_key_$storageKey')
              .write(base64Encode(key));
          if (identity != _scope) throw StateError('服务器配置已变化，请重试');
          _key = key;
        }
        await _service.enableDomain('settings', value);
        if (identity != _scope) throw StateError('服务器配置已变化，请重试');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('sync_settings_$storageKey', value);
        enabled = value;
        _lastSnapshot = null;
        if (value) {
          _settingsChanged();
          await _writes;
        }
      });
  Future<void> selectPrivateSpace() => _run(() async {
        spaceId = null;
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('sync_space_$_storageKey');
        _lastSnapshot = null;
        _notify();
      });
  Future<List<Map<String, dynamic>>> listSpaces() async {
    await init();
    return _service.listSpaces();
  }

  Future<void> createSpace() => _run(() async {
        final data = await _service.createSpace();
        spaceId = (data['space'] as Map)['spaceId'] as String;
        lastJoinCode = data['joinCode'] as String?;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('sync_space_$_storageKey', spaceId!);
        _lastSnapshot = null;
        _notify();
      });
  Future<void> joinSpace(String code) => _run(() async {
        final data = await _service.joinSpace(code.trim());
        spaceId = data['spaceId'] as String;
        lastJoinCode = null;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('sync_space_$_storageKey', spaceId!);
        _lastSnapshot = null;
        _notify();
      });
  Map<String, Object?> _snapshot() => {
        'schemaVersion': 1,
        'themeMode': settings.themeMode.name,
        'homeNavigationStyle': settings.homeNavigationStyle.name,
      };
  void _settingsChanged() {
    if (!enabled || _applying || _key == null || _identity != _scope) return;
    final endpoint = _endpointScope(backend.config.endpoint('').toString());
    final device = backend.config.deviceId;
    final snapshot = _snapshot();
    final serialized = jsonEncode(snapshot);
    if (_lastSnapshot == serialized && _writeFailure == null) return;
    _lastSnapshot = serialized;
    final envelope = SyncCrypto.encrypt(snapshot, _key!, 0);
    _writes = _writes.then((_) async {
      await _outbox!.writeLocal(endpoint, device, 'settings', envelope);
      _writeFailure = null;
    }).catchError((Object failure) {
      error = '本地同步记录保存失败：$failure';
      _writeFailure = failure;
      _notify();
    });
  }

  String exportKey(String password) {
    if (_key == null) throw StateError('请先开启设置同步');
    return SyncCrypto.exportKey(_key!, password);
  }

  Future<void> importKey(String bundle, String password) => _run(() async {
        await init();
        final imported = SyncCrypto.importKey(bundle, password);
        await keyStoreFactory('sync_key_$_storageKey')
            .write(base64Encode(imported));
        _key = imported;
        enabled = true;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('sync_settings_$_storageKey', true);
        _notify();
      });

  Future<void> upload() => _run(() async {
        await init();
        if (!enabled) throw StateError('请先开启设置同步');
        _settingsChanged();
        await _writes;
        if (_writeFailure != null) throw StateError('本地同步记录保存失败，请重试');
        await _service.flush();
      });
  Future<void> restore() => _run(() async {
        await init();
        if (!enabled || _key == null) throw StateError('请先开启设置同步');
        final identity = _scope;
        final endpoint = _endpointScope(backend.config.endpoint('').toString());
        final device = backend.config.deviceId;
        final remote = await _service.download('settings');
        if (identity != _scope) throw StateError('服务器配置已变化，请重试');
        final payload = SyncCrypto.decrypt(remote, _key!);
        if (payload['schemaVersion'] != 1) {
          throw const FormatException('不支持的设置同步版本');
        }
        final theme =
            AppThemeMode.values.byName(payload['themeMode'] as String);
        final navigation = HomeNavigationStyle.values
            .byName(payload['homeNavigationStyle'] as String);
        _applying = true;
        try {
          await _writes;
          await settings.setThemeMode(theme);
          await settings.setHomeNavigationStyle(navigation);
          await _outbox!.acceptRemote(
              endpoint, device, 'settings', remote['revision'] as int, remote);
          _lastSnapshot = jsonEncode(_snapshot());
          _writeFailure = null;
        } finally {
          _applying = false;
        }
      });
  Future<void> keepLocal() => _run(() async {
        await init();
        if (!enabled) throw StateError('请先开启设置同步');
        final endpoint = _endpointScope(backend.config.endpoint('').toString());
        final device = backend.config.deviceId;
        final remote = await _service.download('settings');
        if (endpoint != backend.config.endpoint('').toString() ||
            device != backend.config.deviceId) {
          throw StateError('服务器配置已变化，请重试');
        }
        _settingsChanged();
        await _writes;
        await _outbox!.resolveWithLocal(
            endpoint, device, 'settings', remote['revision'] as int);
        await _service.flush();
      });
  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    error = null;
    _notify();
    try {
      await action();
    } catch (failure) {
      error = backend.errorMessage(failure);
    } finally {
      busy = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    settings.removeListener(_settingsChanged);
    backend.removeListener(_backendChanged);
    super.dispose();
  }
}
