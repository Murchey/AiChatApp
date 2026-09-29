import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// 角色表 DAO
class CharacterDao {
  CharacterDao(this._db);
  final AppDatabase _db;

  Future<void> upsertCharacter({
    required String id,
    required String json,
    String name = '',
    String displayName = '',
  }) async {
    await _db.into(_db.characters).insertOnConflictUpdate(
          CharactersCompanion(
            id: Value(id),
            json: Value(json),
            name: Value(name),
            displayName: Value(displayName),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  Future<void> upsertAll(List<CharactersCompanion> rows) async {
    await _db.batch((b) {
      b.insertAllOnConflictUpdate(_db.characters, rows);
    });
  }

  Future<List<Character>> all() => _db.select(_db.characters).get();

  Future<String?> rawJson(String id) async {
    final row = await (_db.select(_db.characters)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row?.json;
  }

  Future<void> deleteAll() => _db.delete(_db.characters).go();

  Future<void> setMeta(String key, String value) async {
    await _db.into(_db.characterMetas).insertOnConflictUpdate(
          CharacterMetasCompanion(key: Value(key), value: Value(value)),
        );
  }

  Future<String?> meta(String key) async {
    final row = await (_db.select(_db.characterMetas)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }
}
