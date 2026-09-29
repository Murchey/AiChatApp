import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// 应用本地库（drift / SQLite）。
///
/// 首批表：角色、会话、消息 + 附属元数据 + 迁移标记。
/// 旧 SharedPreferences 仍保留读写，迁移只做一次性导入。
@DriftDatabase(tables: [
  Characters,
  CharacterMetas,
  Conversations,
  Messages,
  ChatMetas,
  MigrationFlags,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // 消息按会话 + 时间检索
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_messages_conv_time '
            'ON messages (conversation_id, created_at);',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_conversations_updated '
            'ON conversations (last_message_time);',
          );
        },
        onUpgrade: (m, from, to) async {
          // 后续 schema 升级在此处理
        },
      );
}

QueryExecutor _openConnection() {
  return driftDatabase(name: 'ai_chat_core');
}
