import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// 会话表 DAO
class ConversationDao {
  ConversationDao(this._db);
  final AppDatabase _db;

  Future<void> upsert({
    required String id,
    required String json,
    String characterId = '',
    String characterName = '',
    String lastMessage = '',
    DateTime? lastMessageTime,
    int unreadCount = 0,
    bool pinned = false,
  }) async {
    await _db.into(_db.conversations).insertOnConflictUpdate(
          ConversationsCompanion(
            id: Value(id),
            json: Value(json),
            characterId: Value(characterId),
            characterName: Value(characterName),
            lastMessage: Value(lastMessage),
            lastMessageTime: Value(lastMessageTime ?? DateTime.now()),
            unreadCount: Value(unreadCount),
            pinned: Value(pinned),
          ),
        );
  }

  Future<void> upsertAll(List<ConversationsCompanion> rows) async {
    await _db.batch((b) {
      b.insertAllOnConflictUpdate(_db.conversations, rows);
    });
  }

  Future<List<Conversation>> all() =>
      (_db.select(_db.conversations)
            ..orderBy([(t) => OrderingTerm.desc(t.lastMessageTime)]))
          .get();

  Future<List<Conversation>> pinnedFirst() =>
      (_db.select(_db.conversations)
            ..orderBy([
              (t) => OrderingTerm.desc(t.pinned),
              (t) => OrderingTerm.desc(t.lastMessageTime),
            ]))
          .get();

  Future<void> deleteAll() => _db.delete(_db.conversations).go();

  Future<void> deleteById(String id) =>
      (_db.delete(_db.conversations)..where((t) => t.id.equals(id))).go();

  Future<void> setMeta(String key, String value) async {
    await _db.into(_db.chatMetas).insertOnConflictUpdate(
          ChatMetasCompanion(key: Value(key), value: Value(value)),
        );
  }

  Future<String?> meta(String key) async {
    final row = await (_db.select(_db.chatMetas)..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }
}
