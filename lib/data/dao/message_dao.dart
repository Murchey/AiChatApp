import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// 消息表 DAO（私聊）
class MessageDao {
  MessageDao(this._db);
  final AppDatabase _db;

  Future<void> upsert({
    required String id,
    required String conversationId,
    required String json,
    bool isFromUser = false,
    String type = 'text',
    DateTime? createdAt,
  }) async {
    await _db.into(_db.messages).insertOnConflictUpdate(
          MessagesCompanion(
            id: Value(id),
            conversationId: Value(conversationId),
            json: Value(json),
            isFromUser: Value(isFromUser),
            type: Value(type),
            createdAt: Value(createdAt ?? DateTime.now()),
          ),
        );
  }

  Future<void> upsertAll(List<MessagesCompanion> rows) async {
    // 分批写入，避免超大聊天记录单事务过大
    const batchSize = 200;
    for (var i = 0; i < rows.length; i += batchSize) {
      final end = (i + batchSize).clamp(0, rows.length);
      await _db.batch((b) {
        b.insertAllOnConflictUpdate(_db.messages, rows.sublist(i, end));
      });
    }
  }

  Future<List<Message>> forConversation(String conversationId) =>
      (_db.select(_db.messages)
            ..where((t) => t.conversationId.equals(conversationId))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();

  Future<int> count() async {
    final c = countAll();
    final q = _db.selectOnly(_db.messages)..addColumns([c]);
    final row = await q.getSingle();
    return row.read(c) ?? 0;
  }

  Future<void> deleteAll() => _db.delete(_db.messages).go();

  Future<void> deleteConversation(String conversationId) =>
      (_db.delete(_db.messages)
            ..where((t) => t.conversationId.equals(conversationId)))
          .go();
}
