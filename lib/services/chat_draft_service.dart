import 'dart:async';
import '../data/dao/conversation_dao.dart';
import 'storage_migration_service.dart';

/// Serialized SQLite writes; text stays verbatim and never enters chat history.
class ChatDraftService {
  ChatDraftService(
      {Future<String?> Function(String)? read,
      Future<void> Function(String, String)? write})
      : _read = read ??
            ((id) => ConversationDao(StorageMigrationService.database)
                .meta('draft:$id')),
        _write = write ??
            ((id, text) async {
              final db = StorageMigrationService.database;
              if (text.isEmpty) {
                await (db.delete(db.chatMetas)
                      ..where((t) => t.key.equals('draft:$id')))
                    .go();
              } else {
                await ConversationDao(db).setMeta('draft:$id', text);
              }
            });
  static final instance = ChatDraftService();
  final Future<String?> Function(String) _read;
  final Future<void> Function(String, String) _write;
  final Map<String, String> _values = {};
  final Map<String, String> _persisted = {};
  final Map<String, ({String text, Future<void> done})> _pending = {};
  final Map<String, Timer> _timers = {};
  Future<void> _tail = Future.value();
  Future<String> load(String id) async {
    if (_values.containsKey(id)) return _values[id]!;
    final text = await _read(id) ?? '';
    _persisted[id] = text;
    return _values.putIfAbsent(id, () => text);
  }

  void update(String id, String text) {
    if (_values[id] == text) return;
    _values[id] = text;
    _timers.remove(id)?.cancel();
    _timers[id] = Timer(const Duration(milliseconds: 300), () {
      flush(id).catchError((Object e) {/* Retry on leave/background. */});
    });
  }

  Future<void> flush(String id) {
    _timers.remove(id)?.cancel();
    if (!_values.containsKey(id)) return _tail;
    final text = _values[id]!;
    final pending = _pending[id];
    if (pending?.text == text) return pending!.done;
    if (pending == null && _persisted[id] == text) return Future.value();
    late final Future<void> next;
    next = _tail.catchError((Object _) {}).then((_) async {
      try {
        await _write(id, text);
        _persisted[id] = text;
      } finally {
        if (identical(_pending[id]?.done, next)) _pending.remove(id);
      }
    });
    _pending[id] = (text: text, done: next);
    _tail = next;
    return next;
  }

  Future<void> flushAll() async {
    for (final id in _values.keys.toList()) {
      await flush(id);
    }
  }

  Future<void> remove(String id) {
    update(id, '');
    return flush(id);
  }

  Future<void> clearIfUnchanged(String id, String text) async {
    if (_values[id] == text) await remove(id);
  }

  Future<void> clearAll() async {
    await flushAll();
    reset();
    await StorageMigrationService.database
        .customStatement("DELETE FROM chat_metas WHERE key LIKE 'draft:%'");
  }

  void reset() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _values.clear();
    _persisted.clear();
    _pending.clear();
  }
}
