import 'package:drift/drift.dart';

/// 角色列表：整卡 JSON 持久化（与 SharedPreferences `characters_v1` 同构），
/// 另建索引列便于后续查询；本阶段不拆字段。
class Characters extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get displayName => text().withDefault(const Constant(''))();

  /// Character.toJson() 完整 JSON
  TextColumn get json => text()();

  /// 冗余创建/更新时间（毫秒时间戳）
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// 角色附属元数据（删除的默认角色 id、可见性分组）
class CharacterMetas extends Table {
  /// `deleted_default_ids` | `visibility_groups`
  TextColumn get key => text()();

  /// JSON 字符串
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// 会话列表
class Conversations extends Table {
  TextColumn get id => text()();
  TextColumn get characterId => text().withDefault(const Constant(''))();
  TextColumn get characterName => text().withDefault(const Constant(''))();

  /// Conversation.toJson() 完整 JSON
  TextColumn get json => text()();
  TextColumn get lastMessage => text().withDefault(const Constant(''))();
  DateTimeColumn get lastMessageTime =>
      dateTime().withDefault(currentDateAndTime)();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 消息（私聊）
class Messages extends Table {
  TextColumn get id => text()();
  TextColumn get conversationId => text()();

  /// Message.toJson() 完整 JSON
  TextColumn get json => text()();
  BoolColumn get isFromUser => boolean().withDefault(const Constant(false))();
  TextColumn get type => text().withDefault(const Constant('text'))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// 会话级附属 JSON（上下文 token / 系统 token / 语C候选）
class ChatMetas extends Table {
  /// `context_tokens` | `system_tokens` | `roleplay_choices`
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// 迁移完成标记（防止重复导入 SharedPreferences）
class MigrationFlags extends Table {
  /// 如 `prefs_to_sqlite_v1`
  TextColumn get name => text()();
  DateTimeColumn get completedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {name};
}
