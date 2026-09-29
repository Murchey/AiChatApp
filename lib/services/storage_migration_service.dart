import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/dao/character_dao.dart';
import '../data/dao/conversation_dao.dart';
import '../data/dao/message_dao.dart';
import '../data/db/app_database.dart';

/// SharedPreferences → SQLite 一次性迁移。
///
/// **升级不丢数据保证：**
/// 1. 迁移前把源 key 全量备份到 `db_migration_backup/`
/// 2. 导入过程任一步失败 → **不打标**，下次启动重试；prefs 始终保留
/// 3. 打标前校验「源有数据则库内必须有行」
/// 4. 已打标但库被清空/损坏且 prefs 仍有数据 → 自动修复重导
/// 5. 读取层（LocalDataStore）在 SQLite 为空时回退 prefs
class StorageMigrationService {
  StorageMigrationService._();

  static const migrationName = 'prefs_to_sqlite_v1';

  /// 首批迁移的源 key
  static const sourceKeys = [
    'characters_v1',
    'characters_deleted_v1',
    'visibility_groups_v1',
    'chat_conversations_v1',
    'chat_messages_v1',
    'chat_context_tokens_v1',
    'chat_system_tokens_v1',
    'chat_roleplay_choices_v1',
  ];

  static AppDatabase? _db;
  static bool _initialized = false;

  static AppDatabase get database {
    final db = _db;
    if (db == null) {
      throw StateError('StorageMigrationService.init() 尚未调用');
    }
    return db;
  }

  /// 启动时调用：打开库并按需执行迁移。
  static Future<void> init() async {
    if (_initialized) return;
    _db = AppDatabase();
    _initialized = true;
    try {
      await runIfNeeded();
    } catch (e, st) {
      debugPrint('[StorageMigration] init 迁移异常（已忽略，启动继续）: $e\n$st');
    }
  }

  static Future<bool> isMigrationDone() async {
    final row = await (database.select(database.migrationFlags)
          ..where((t) => t.name.equals(migrationName)))
        .getSingleOrNull();
    return row != null;
  }

  /// 若未迁移则执行；已完成但需要修复时也会执行。
  static Future<void> runIfNeeded() async {
    final done = await isMigrationDone();
    if (done) {
      if (await needsRepair()) {
        debugPrint(
          '[StorageMigration] 检测到库内数据缺失但 prefs 仍有数据，开始修复导入',
        );
        await runOnce();
      } else {
        debugPrint('[StorageMigration] 已完成，跳过');
      }
      return;
    }
    await runOnce();
  }

  /// 是否需要修复：已迁移，但某块「prefs 有、SQLite 无」。
  static Future<bool> needsRepair() async {
    final prefs = await SharedPreferences.getInstance();
    final characterDao = CharacterDao(database);
    final messageDao = MessageDao(database);
    final conversationDao = ConversationDao(database);

    final charsSqlite = (await characterDao.all()).length;
    final msgsSqlite = await messageDao.count();
    // 会话行数：用 DAO 同源统计
    final convsSqlite = (await conversationDao.all()).length;

    final charsPrefs =
        _decodeJsonObjectCount(prefs.getString('characters_v1'));
    final convsPrefs =
        _decodeJsonListCount(prefs.getString('chat_conversations_v1'));
    final msgsPrefs =
        _decodeMessageMapCount(prefs.getString('chat_messages_v1'));

    // prefs 明显有数据而库为空 → 需要修复
    if (charsPrefs > 0 && charsSqlite == 0) return true;
    if (convsPrefs > 0 && convsSqlite == 0) return true;
    if (msgsPrefs > 0 && msgsSqlite == 0) return true;
    return false;
  }

  /// 执行迁移；失败抛异常且不打标。
  static Future<void> runOnce() async {
    final prefs = await SharedPreferences.getInstance();
    debugPrint('[StorageMigration] 开始导入 SharedPreferences → SQLite');

    await _backupRaw(prefs);

    final characterDao = CharacterDao(database);
    final conversationDao = ConversationDao(database);
    final messageDao = MessageDao(database);

    // ── 1. 角色 ─────────────────────────────────────
    final charactersRaw = prefs.getString('characters_v1');
    var characterCount = 0;
    var characterSourceCount = 0;
    if (charactersRaw != null && charactersRaw.isNotEmpty) {
      final decoded = jsonDecode(charactersRaw);
      final rows = <CharactersCompanion>[];
      if (decoded is Map<String, dynamic>) {
        characterSourceCount = decoded.length;
        decoded.forEach((id, value) {
          if (value is! Map) return;
          final map = Map<String, dynamic>.from(value);
          rows.add(
            CharactersCompanion(
              id: Value(id.toString()),
              json: Value(jsonEncode(map)),
              name: Value(map['name']?.toString() ?? ''),
              displayName: Value(
                (map['remark'] as String?)?.isNotEmpty == true
                    ? map['remark'].toString()
                    : map['name']?.toString() ?? '',
              ),
              updatedAt: Value(DateTime.now()),
            ),
          );
        });
      } else if (decoded is List) {
        characterSourceCount = decoded.length;
        for (final item in decoded) {
          if (item is! Map) continue;
          final map = Map<String, dynamic>.from(item);
          final id = map['id']?.toString() ?? '';
          if (id.isEmpty) continue;
          rows.add(
            CharactersCompanion(
              id: Value(id),
              json: Value(jsonEncode(map)),
              name: Value(map['name']?.toString() ?? ''),
              displayName: Value(map['name']?.toString() ?? ''),
              updatedAt: Value(DateTime.now()),
            ),
          );
        }
      }
      // 源有记录但一行都解析不出来 → 视为失败，不打标
      if (characterSourceCount > 0 && rows.isEmpty) {
        throw StateError('角色 JSON 无法解析，已中止迁移（prefs 未改动）');
      }
      await characterDao.deleteAll();
      await characterDao.upsertAll(rows);
      characterCount = rows.length;
    }

    final deletedIds = prefs.getStringList('characters_deleted_v1');
    if (deletedIds != null) {
      await characterDao.setMeta(
        'deleted_default_ids',
        jsonEncode(deletedIds),
      );
    }
    final visibility = prefs.getString('visibility_groups_v1');
    if (visibility != null && visibility.isNotEmpty) {
      await characterDao.setMeta('visibility_groups', visibility);
    }

    // ── 2. 会话 ─────────────────────────────────────
    final convRaw = prefs.getString('chat_conversations_v1');
    var conversationCount = 0;
    var conversationSourceCount = 0;
    if (convRaw != null && convRaw.isNotEmpty) {
      final list = jsonDecode(convRaw) as List<dynamic>;
      conversationSourceCount = list.length;
      final convRows = <ConversationsCompanion>[];
      for (final item in list) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final id = map['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final lastTime = DateTime.tryParse(
              map['last_message_time']?.toString() ?? '',
            ) ??
            DateTime.now();
        convRows.add(
          ConversationsCompanion(
            id: Value(id),
            json: Value(jsonEncode(map)),
            characterId: Value(map['character_id']?.toString() ?? ''),
            characterName: Value(map['character_name']?.toString() ?? ''),
            lastMessage: Value(map['last_message']?.toString() ?? ''),
            lastMessageTime: Value(lastTime),
            unreadCount: Value((map['unread_count'] as num?)?.toInt() ?? 0),
            pinned: Value(map['pinned'] == true),
          ),
        );
      }
      if (conversationSourceCount > 0 && convRows.isEmpty) {
        throw StateError('会话 JSON 无法解析，已中止迁移（prefs 未改动）');
      }
      await conversationDao.deleteAll();
      await conversationDao.upsertAll(convRows);
      conversationCount = convRows.length;
    }

    // ── 3. 消息 ─────────────────────────────────────
    final msgRaw = prefs.getString('chat_messages_v1');
    var messageCount = 0;
    var messageSourceCount = 0;
    if (msgRaw != null && msgRaw.isNotEmpty) {
      final map = jsonDecode(msgRaw) as Map<String, dynamic>;
      final rows = <MessagesCompanion>[];
      map.forEach((convId, msgs) {
        if (msgs is! List) return;
        messageSourceCount += msgs.length;
        for (final item in msgs) {
          if (item is! Map) continue;
          final m = Map<String, dynamic>.from(item);
          final id = m['id']?.toString() ?? '${convId}_${rows.length}';
          rows.add(
            MessagesCompanion(
              id: Value(id),
              conversationId: Value(convId),
              json: Value(jsonEncode(m)),
              isFromUser: Value(m['is_from_user'] == true),
              type: Value(m['type']?.toString() ?? 'text'),
              createdAt: Value(
                DateTime.tryParse(m['created_at']?.toString() ?? '') ??
                    DateTime.now(),
              ),
            ),
          );
        }
      });
      if (messageSourceCount > 0 && rows.isEmpty) {
        throw StateError('消息 JSON 无法解析，已中止迁移（prefs 未改动）');
      }
      await messageDao.deleteAll();
      await messageDao.upsertAll(rows);
      messageCount = rows.length;
    }

    // ── 4. meta ─────────────────────────────────────
    final ctx = prefs.getString('chat_context_tokens_v1');
    if (ctx != null && ctx.isNotEmpty) {
      await conversationDao.setMeta('context_tokens', ctx);
    }
    final sys = prefs.getString('chat_system_tokens_v1');
    if (sys != null && sys.isNotEmpty) {
      await conversationDao.setMeta('system_tokens', sys);
    }
    final choices = prefs.getString('chat_roleplay_choices_v1');
    if (choices != null && choices.isNotEmpty) {
      await conversationDao.setMeta('roleplay_choices', choices);
    }

    // ── 5. 校验后打标 ───────────────────────────────
    final verifyChars = (await characterDao.all()).length;
    final verifyConvs =
        (await database.select(database.conversations).get()).length;
    final verifyMsgs = await messageDao.count();

    if (characterSourceCount > 0 && verifyChars < characterSourceCount) {
      throw StateError(
        '角色迁移校验失败：源 $characterSourceCount 行，库 $verifyChars 行',
      );
    }
    if (conversationSourceCount > 0 && verifyConvs < conversationSourceCount) {
      throw StateError(
        '会话迁移校验失败：源 $conversationSourceCount 行，库 $verifyConvs 行',
      );
    }
    if (messageSourceCount > 0 && verifyMsgs < messageSourceCount) {
      throw StateError(
        '消息迁移校验失败：源 $messageSourceCount 行，库 $verifyMsgs 行',
      );
    }

    await database.into(database.migrationFlags).insertOnConflictUpdate(
          MigrationFlagsCompanion(
            name: const Value(migrationName),
            completedAt: Value(DateTime.now()),
          ),
        );

    debugPrint(
      '[StorageMigration] 完成并校验通过：'
      '角色 $characterCount/$characterSourceCount · '
      '会话 $conversationCount/$conversationSourceCount · '
      '消息 $messageCount/$messageSourceCount（SharedPreferences 保留）',
    );
  }

  static int _decodeJsonObjectCount(String? raw) {
    if (raw == null || raw.isEmpty) return 0;
    try {
      final d = jsonDecode(raw);
      if (d is Map) return d.length;
      if (d is List) return d.length;
    } catch (_) {}
    return 0;
  }

  static int _decodeJsonListCount(String? raw) {
    if (raw == null || raw.isEmpty) return 0;
    try {
      final d = jsonDecode(raw);
      if (d is List) return d.length;
    } catch (_) {}
    return 0;
  }

  static int _decodeMessageMapCount(String? raw) {
    if (raw == null || raw.isEmpty) return 0;
    try {
      final d = jsonDecode(raw);
      if (d is! Map) return 0;
      var n = 0;
      d.forEach((_, v) {
        if (v is List) n += v.length;
      });
      return n;
    } catch (_) {}
    return 0;
  }

  /// 迁移前备份源 key 原始值。
  static Future<void> _backupRaw(SharedPreferences prefs) async {
    try {
      final doc = await getApplicationDocumentsDirectory();
      final dir = Directory('${doc.path}/db_migration_backup');
      if (!await dir.exists()) await dir.create(recursive: true);
      final payload = <String, dynamic>{
        'exported_at': DateTime.now().toIso8601String(),
        'keys': {
          for (final key in sourceKeys)
            if (prefs.containsKey(key)) key: prefs.get(key),
        },
      };
      final file = File(
        '${dir.path}/prefs_migration_${DateTime.now().millisecondsSinceEpoch}.json',
      );
      await file.writeAsString(jsonEncode(payload), flush: true);
      debugPrint('[StorageMigration] 已备份旧数据 → ${file.path}');
    } catch (e) {
      debugPrint('[StorageMigration] 备份旧数据失败（继续迁移）: $e');
    }
  }
}
