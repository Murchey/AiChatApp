import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/storage_migration_service.dart';
import 'dao/character_dao.dart';
import 'dao/conversation_dao.dart';
import 'dao/message_dao.dart';
import 'db/app_database.dart';

/// 角色 / 会话 / 消息 的双存储读写桥。
///
/// - **读**：优先 SQLite；无数据时回退 SharedPreferences
/// - **写**：双写（SQLite + SharedPreferences），旧代码路径仍可用
class LocalDataStore {
  LocalDataStore._();

  static AppDatabase get _db => StorageMigrationService.database;

  static CharacterDao get _characters => CharacterDao(_db);
  static ConversationDao get _conversations => ConversationDao(_db);
  static MessageDao get _messages => MessageDao(_db);

  // ── 角色 ──────────────────────────────────────────────

  /// 旧格式：`{ id: Character.toJson(), ... }`
  static Future<String?> loadCharactersJson() async {
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString('characters_v1');
    try {
      final rows = await _characters.all();
      // A failed first-run migration can leave a partial SQLite import. Keep
      // using the complete legacy payload until SQLite has caught up.
      final legacyCount = _jsonCollectionCount(legacy);
      if (rows.isNotEmpty && rows.length >= legacyCount) {
        final map = <String, dynamic>{};
        for (final row in rows) {
          try {
            map[row.id] = jsonDecode(row.json);
          } catch (_) {}
        }
        return jsonEncode(map);
      }
    } catch (e) {
      debugPrint('[LocalDataStore] 读角色 SQLite 失败，回退 prefs: $e');
    }
    return legacy;
  }

  static Future<void> saveCharactersJson(String encoded) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('characters_v1', encoded);
    try {
      final decoded = jsonDecode(encoded);
      final rows = <CharactersCompanion>[];
      if (decoded is Map<String, dynamic>) {
        decoded.forEach((id, value) {
          if (value is! Map) return;
          final map = Map<String, dynamic>.from(value);
          rows.add(
            CharactersCompanion(
              id: Value(id.toString()),
              json: Value(jsonEncode(map)),
              name: Value(map['name']?.toString() ?? ''),
              displayName: Value(map['name']?.toString() ?? ''),
              updatedAt: Value(DateTime.now()),
            ),
          );
        });
      }
      await _characters.deleteAll();
      if (rows.isNotEmpty) await _characters.upsertAll(rows);
    } catch (e) {
      debugPrint('[LocalDataStore] 写角色 SQLite 失败（prefs 已写入）: $e');
    }
  }

  static Future<List<String>> loadDeletedDefaultIds() async {
    try {
      final raw = await _characters.meta('deleted_default_ids');
      if (raw != null && raw.isNotEmpty) {
        return List<String>.from(jsonDecode(raw) as List<dynamic>);
      }
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('characters_deleted_v1') ?? const [];
  }

  static Future<void> saveDeletedDefaultIds(List<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('characters_deleted_v1', ids);
    await _characters.setMeta('deleted_default_ids', jsonEncode(ids));
  }

  static Future<String?> loadVisibilityGroupsJson() async {
    try {
      final raw = await _characters.meta('visibility_groups');
      if (raw != null && raw.isNotEmpty) return raw;
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('visibility_groups_v1');
  }

  static Future<void> saveVisibilityGroupsJson(String encoded) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('visibility_groups_v1', encoded);
    await _characters.setMeta('visibility_groups', encoded);
  }

  // ── 会话 / 消息 ───────────────────────────────────────

  static Future<String?> loadConversationsJson() async {
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString('chat_conversations_v1');
    try {
      final rows = await _conversations.pinnedFirst();
      if (rows.isNotEmpty && rows.length >= _jsonListCount(legacy)) {
        final list = rows.map((r) {
          try {
            return jsonDecode(r.json);
          } catch (_) {
            return <String, dynamic>{'id': r.id};
          }
        }).toList();
        return jsonEncode(list);
      }
    } catch (e) {
      debugPrint('[LocalDataStore] 读会话 SQLite 失败，回退 prefs: $e');
    }
    return legacy;
  }

  static Future<void> saveConversationsJson(String encoded) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('chat_conversations_v1', encoded);
    try {
      final list = jsonDecode(encoded) as List<dynamic>;
      final rows = <ConversationsCompanion>[];
      for (final item in list) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final id = map['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        rows.add(
          ConversationsCompanion(
            id: Value(id),
            json: Value(jsonEncode(map)),
            characterId: Value(map['character_id']?.toString() ?? ''),
            characterName: Value(map['character_name']?.toString() ?? ''),
            lastMessage: Value(map['last_message']?.toString() ?? ''),
            lastMessageTime: Value(
              DateTime.tryParse(map['last_message_time']?.toString() ?? '') ??
                  DateTime.now(),
            ),
            unreadCount: Value((map['unread_count'] as num?)?.toInt() ?? 0),
            pinned: Value(map['pinned'] == true),
          ),
        );
      }
      await _conversations.deleteAll();
      if (rows.isNotEmpty) await _conversations.upsertAll(rows);
    } catch (e) {
      debugPrint('[LocalDataStore] 写会话 SQLite 失败（prefs 已写入）: $e');
    }
  }

  /// 旧格式：`{ conversationId: [Message.toJson(), ...], ... }`
  static Future<String?> loadMessagesJson() async {
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString('chat_messages_v1');
    try {
      final count = await _messages.count();
      if (count > 0 && count >= _jsonMessageCount(legacy)) {
        final result = <String, dynamic>{};
        final all = await _db.select(_db.messages).get();
        for (final row in all) {
          final list =
              (result[row.conversationId] as List<dynamic>?) ?? <dynamic>[];
          try {
            list.add(jsonDecode(row.json));
          } catch (_) {}
          result[row.conversationId] = list;
        }
        return jsonEncode(result);
      }
    } catch (e) {
      debugPrint('[LocalDataStore] 读消息 SQLite 失败，回退 prefs: $e');
    }
    return legacy;
  }

  static int _jsonCollectionCount(String? raw) {
    if (raw == null || raw.isEmpty) return 0;
    try {
      final value = jsonDecode(raw);
      return value is Map || value is List ? value.length : 0;
    } catch (_) {
      return 0;
    }
  }

  static int _jsonListCount(String? raw) => _jsonCollectionCount(raw);

  static int _jsonMessageCount(String? raw) {
    if (raw == null || raw.isEmpty) return 0;
    try {
      final value = jsonDecode(raw);
      if (value is! Map) return 0;
      return value.values.fold<int>(
        0,
        (sum, messages) => sum + (messages is List ? messages.length : 0),
      );
    } catch (_) {
      return 0;
    }
  }

  static Future<void> saveMessagesJson(String encoded) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('chat_messages_v1', encoded);
    try {
      final map = jsonDecode(encoded) as Map<String, dynamic>;
      final rows = <MessagesCompanion>[];
      map.forEach((convId, msgs) {
        if (msgs is! List) return;
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
      await _messages.deleteAll();
      if (rows.isNotEmpty) await _messages.upsertAll(rows);
    } catch (e) {
      debugPrint('[LocalDataStore] 写消息 SQLite 失败（prefs 已写入）: $e');
    }
  }

  // ── 会话附属 meta ─────────────────────────────────────

  static Future<String?> loadChatMeta(String key, String prefsKey) async {
    try {
      final raw = await _conversations.meta(key);
      if (raw != null && raw.isNotEmpty) return raw;
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(prefsKey);
  }

  static Future<void> saveChatMeta(
    String key,
    String prefsKey,
    String encoded,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, encoded);
    await _conversations.setMeta(key, encoded);
  }

  // ── 清空三块数据 ──────────────────────────────────────

  static Future<void> clearCoreData() async {
    await _characters.deleteAll();
    await _conversations.deleteAll();
    await _messages.deleteAll();
  }
}
