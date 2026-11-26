import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../data/dao/conversation_dao.dart';
import '../services/storage_migration_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/auto_memory_op.dart';
import '../models/memory_point.dart';
import '../models/story_package.dart';

/// 角色的持久化记忆点管理：每个角色独立一组记忆点，按角色 id 分 key 持久化。
///
/// 记忆点在生成系统提示词时由调用方取出并拼接（见 ChatProvider），
/// 长按聊天气泡进入多选可批量添加，会话详情「提示词设置」下方可管理。
class MemoryPointProvider extends ChangeNotifier {
  static const _prefix = 'memory_points_v1_';
  static const _storyInstallationsKey = 'story_installations_v1';

  final Map<String, List<MemoryPoint>> _pointsByCharacter = {};
  final Map<String, List<InstalledStory>> _installationsByCharacter = {};
  Map<String, List<MemoryPoint>> _publishedPoints = {};
  Map<String, List<InstalledStory>> _publishedInstallations = {};
  bool _loaded = false;
  Future<void>? _loading;

  int get generation => _generation;
  bool get isDisposed => _disposed;
  bool _disposed = false;
  int _generation = 0;
  Future<void> _mutationQueue = Future<void>.value();
  static Future<void>? _storageQueue;
  static const _transactionKey = 'auto_memory_transaction_v1';
  static const _cursorKey = 'auto_memory_cursors_v1';
  @visibleForTesting
  static Future<void> Function(String stage)? transactionTestHook;

  Future<void> synchronizePendingTransaction() => _mutate(() async {});

  /// Serializes every provider instance and backup capture globally.
  static Future<T> withBackupBarrier<T>(Future<T> Function() action) =>
      _runStorageMutation(() async {
        await _recoverTransaction();
        return action();
      });

  /// 等待已排队的持久化操作，供备份与恢复调用方建立写入屏障。
  Future<void> drain() => _mutationQueue;

  Future<void> _mutate(Future<void> Function() action) {
    final task = _mutationQueue.then((_) => _runStorageMutation(() async {
      if (_disposed) return;
      await _recoverTransaction();
      if (_loaded) {
        final prefs = await SharedPreferences.getInstance();
        final current = <String, List<MemoryPoint>>{};
        for (final key in prefs.getKeys().where((key) => key.startsWith(_prefix))) {
          final raw = prefs.getString(key);
          if (raw == null || raw.isEmpty) continue;
          final points = (jsonDecode(raw) as List)
              .map((item) => MemoryPoint.fromJson(Map<String, dynamic>.from(item as Map)))
              .toList();
          if (points.isNotEmpty) current[key.substring(_prefix.length)] = points;
        }
        _pointsByCharacter
          ..clear()
          ..addAll(current);
      }
      final pointsBefore = {
        for (final entry in _pointsByCharacter.entries)
          entry.key: List<MemoryPoint>.of(entry.value),
      };
      final installationsBefore = {
        for (final entry in _installationsByCharacter.entries)
          entry.key: List<InstalledStory>.of(entry.value),
      };
      final loadedBefore = _loaded;
      try {
        await action();
        _publishedPoints = {
          for (final entry in _pointsByCharacter.entries)
            entry.key: List<MemoryPoint>.of(entry.value),
        };
        _publishedInstallations = {
          for (final entry in _installationsByCharacter.entries)
            entry.key: List<InstalledStory>.of(entry.value),
        };
        _notifyChanged();
      } catch (_) {
        _pointsByCharacter
          ..clear()
          ..addAll(pointsBefore);
        _installationsByCharacter
          ..clear()
          ..addAll(installationsBefore);
        _loaded = loadedBefore;
        rethrow;
      }
    }));
    _mutationQueue =
        task.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return task;
  }

  static Future<T> _runStorageMutation<T>(Future<T> Function() action) async {
    final previous = _storageQueue;
    final released = Completer<void>();
    _storageQueue = released.future;
    try {
      if (previous != null) await previous;
      return await action();
    } finally {
      if (identical(_storageQueue, released.future)) {
        _storageQueue = null;
      }
      released.complete();
    }
  }

  static Future<Map<String, dynamic>?> _recoverTransaction() async {
    late final ConversationDao dao;
    try {
      dao = ConversationDao(StorageMigrationService.database);
    } on StateError {
      return null;
    }
    final raw = await dao.meta(_transactionKey);
    if (raw == null || raw.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('Invalid memory transaction');
    final journal = Map<String, dynamic>.from(decoded);
    final characterId = journal['characterId']?.toString();
    final points = journal['points'];
    final cursor = journal['cursor'];
    if (characterId == null || characterId.isEmpty || points is! List || cursor is! Map) {
      throw const FormatException('Incomplete memory transaction');
    }
    final pointsJson = jsonEncode(points);
    final cursorJson = jsonEncode(cursor);
    if (!await prefs.setString('$_prefix$characterId', pointsJson)) {
      throw StateError('Failed to recover memory points');
    }
    await transactionTestHook?.call('points');
    if (!await prefs.setString(_cursorKey, cursorJson)) {
      throw StateError('Failed to recover memory cursor');
    }
    await transactionTestHook?.call('cursor');
    await dao.setMeta(_transactionKey, '');
    return journal;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }

  void _notifyChanged() {
    if (!_disposed) notifyListeners();
  }

  /// 某个角色的全部记忆点（按创建时间倒序，最新的在前）
  List<MemoryPoint> pointsFor(String characterId) =>
      List.unmodifiable(_publishedPoints[characterId] ?? const []);

  /// 全部已启用记忆点的角色 id
  Iterable<String> get characterIds => _publishedPoints.keys;

  List<InstalledStory> installedStoriesFor(String characterId) =>
      List.unmodifiable(_publishedInstallations[characterId] ?? const []);

  bool get loaded => _loaded;

  Future<void> init() {
    if (_loaded) return Future<void>.value();
    return _loading ??= reload().whenComplete(() => _loading = null);
  }

  /// 备份恢复后强制从磁盘重新加载。
  Future<void> reload() {
    _generation++;
    return _mutate(() async {
      _pointsByCharacter.clear();
      _installationsByCharacter.clear();
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
      for (final key in keys) {
        final characterId = key.substring(_prefix.length);
        final raw = prefs.getString(key);
        if (raw == null || raw.isEmpty) continue;
        try {
          final list = (jsonDecode(raw) as List)
              .map((e) => MemoryPoint.fromJson(e as Map<String, dynamic>))
              .toList();
          if (list.isNotEmpty) _pointsByCharacter[characterId] = list;
        } catch (e) {
          debugPrint('[MemoryPoint] 解析失败 $characterId: $e');
        }
      }
      final installationRaw = prefs.getString(_storyInstallationsKey);
      if (installationRaw != null && installationRaw.isNotEmpty) {
        try {
          final decoded = jsonDecode(installationRaw) as Map;
          for (final entry in decoded.entries) {
            final list = (entry.value as List<dynamic>)
                .whereType<Map>()
                .map((value) =>
                    InstalledStory.fromJson(value.cast<String, dynamic>()))
                .toList();
            if (list.isNotEmpty) {
              _installationsByCharacter[entry.key.toString()] = list;
            }
          }
        } catch (e) {
          debugPrint('[MemoryPoint] 故事安装记录解析失败: $e');
        }
      }
      _loaded = true;
    });
  }

  /// 为角色添加一条记忆点（批量去重：内容相同的只保留一条）
  Future<void> addPoints(String characterId, List<String> contents) =>
      _mutate(() async {
        final clean =
            contents.map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
        if (clean.isEmpty) return;
        final existing = _pointsByCharacter[characterId] ?? [];
        final seen = existing.map((p) => p.content).toSet();
        final news = clean.where((c) => !seen.contains(c)).toList();
        if (news.isEmpty) return;
        // 新记忆点插到最前（最新优先展示）
        final updated = [
          ...news.map((c) => MemoryPoint(content: c)),
          ...existing,
        ];
        _pointsByCharacter[characterId] = updated;
        await _persist(characterId);
      });

  /// 用角色包的记忆点整体替换某角色的记忆点（内容去重、保留原创建时间）。
  /// 空列表等价于清空该角色的全部记忆点。
  Future<void> replacePoints(String characterId, List<MemoryPoint> points) =>
      _mutate(() async {
        final seen = <String>{};
        final clean = <MemoryPoint>[];
        final previousById = {
          for (final point
              in _pointsByCharacter[characterId] ?? <MemoryPoint>[])
            point.id: point,
        };
        for (final p in points) {
          final content = p.content.trim();
          if (content.isEmpty || !seen.add(content)) continue;
          final previous = previousById[p.id];
          final revision = previous == null
              ? p.revision
              : (previous.content == content &&
                      previous.sourceType == p.sourceType
                  ? (p.revision > previous.revision
                      ? p.revision
                      : previous.revision)
                  : (p.revision > previous.revision
                      ? p.revision
                      : previous.revision + 1));
          clean.add(MemoryPoint(
            id: p.id,
            content: content,
            createdAt: p.createdAt,
            revision: revision,
            sourceType: p.sourceType,
            sourceId: p.sourceId,
            sourceVersion: p.sourceVersion,
            sourceTitle: p.sourceTitle,
            chapterId: p.chapterId,
          ));
        }
        if (clean.isEmpty) {
          _pointsByCharacter.remove(characterId);
        } else {
          _pointsByCharacter[characterId] = clean;
        }
        await _persist(characterId);
      });

  /// 更新一条记忆点内容（空内容视为删除）
  Future<void> updatePoint(
          String characterId, String pointId, String content) =>
      _mutate(() async {
        final list = _pointsByCharacter[characterId];
        if (list == null) return;
        final trimmed = content.trim();
        if (trimmed.isEmpty) {
          await _removePoint(characterId, pointId);
          return;
        }
        final index = list.indexWhere((p) => p.id == pointId);
        if (index < 0) return;
        list[index] = list[index].copyWith(
          content: trimmed,
          revision: list[index].revision + 1,
        );
        await _persist(characterId);
      });

  /// 删除一条记忆点
  Future<void> removePoint(String characterId, String pointId) =>
      _mutate(() => _removePoint(characterId, pointId));

  Future<void> _removePoint(String characterId, String pointId) async {
    final list = _pointsByCharacter[characterId];
    if (list == null) return;
    list.removeWhere((p) => p.id == pointId);
    if (list.isEmpty) {
      _pointsByCharacter.remove(characterId);
    }
    await _persist(characterId);
  }

  /// 安装或更新一条故事线：仅替换同一 storyId 产生的记忆，不碰普通记忆。
  Future<void> installStory(String characterId, StoryPackage story) =>
      _mutate(() async {
        final previousList =
            (_installationsByCharacter[characterId] ?? const [])
                .where((item) => item.storyId == story.storyId)
                .toList(growable: false);
        // Re-importing the same version is idempotent. A newer published version
        // is a deliberate user import and may replace the old package.
        if (previousList.isNotEmpty &&
            previousList.first.version >= story.version) {
          return;
        }
        final existing = _pointsByCharacter[characterId] ?? <MemoryPoint>[];
        final retained = existing
            .where((point) =>
                point.sourceType != 'story' || point.sourceId != story.storyId)
            .toList();
        final storyPoints = <MemoryPoint>[];
        for (var index = 0; index < story.memories.length; index++) {
          final content = story.memories[index].content.trim();
          if (content.isEmpty) continue;
          storyPoints.add(MemoryPoint(
            content: content,
            sourceType: 'story',
            sourceId: story.storyId,
            sourceVersion: story.version,
            sourceTitle: story.title,
            chapterId: 'memory_${index + 1}',
          ));
        }
        _pointsByCharacter[characterId] = [...storyPoints, ...retained];
        final installed = List<InstalledStory>.from(
          _installationsByCharacter[characterId] ?? const [],
        )..removeWhere((item) => item.storyId == story.storyId);
        installed.add(InstalledStory(
          storyId: story.storyId,
          title: story.title,
          version: story.version,
          characterId: characterId,
        ));
        _installationsByCharacter[characterId] = installed;
        await _persist(characterId);
        await _persistInstallations();
      });

  Future<void> removeStory(String characterId, String storyId) =>
      _mutate(() async {
        final points = _pointsByCharacter[characterId];
        if (points != null) {
          points.removeWhere((point) =>
              point.sourceType == 'story' && point.sourceId == storyId);
          if (points.isEmpty) _pointsByCharacter.remove(characterId);
          await _persist(characterId);
        }
        final installations = _installationsByCharacter[characterId];
        installations?.removeWhere((item) => item.storyId == storyId);
        if (installations != null && installations.isEmpty) {
          _installationsByCharacter.remove(characterId);
        }
        await _persistInstallations();
      });

  List<MemoryPoint> storyPointsFor(String characterId) => pointsFor(characterId)
      .where((point) => point.sourceType == 'story')
      .toList(growable: false);

  /// AI 托管的剧情记录条目（sourceType == 'auto'，最新在前）。
  List<MemoryPoint> autoPointsFor(String characterId) => pointsFor(characterId)
      .where((point) => point.isAutoManaged)
      .toList(growable: false);

  /// 执行 AI 剧情记录返回的操作（记忆点自动托管）。
  ///
  /// 安全约束：update/delete 仅作用于 AI 托管（sourceType == 'auto'）条目，
  /// 指向用户记忆或故事线记忆的请求一律忽略；add 内容与现有记忆重复时跳过。
  /// 每次调用只持久化并通知一次。
  Future<void> applyAutoOperations(
    String characterId,
    List<AutoMemoryOp> ops, {
    Map<String, int>? expectedRevisions,
    bool Function()? isCurrent,
    String? conversationId,
    int? cursorCount,
    String? cursorLastId,
  }) =>
      _mutate(() async {
        if (isCurrent != null && !isCurrent()) {
          throw StateError('Auto memory request cancelled');
        }
        final list = List<MemoryPoint>.from(
          _pointsByCharacter[characterId] ?? const <MemoryPoint>[],
        );
        var changed = false;
        for (final op in ops) {
          switch (op.op) {
            case AutoMemoryOp.opAdd:
              final content = op.content.trim();
              if (content.isEmpty) break;
              if (list.any((p) => p.content.trim() == content)) break;
              list.insert(
                0,
                MemoryPoint(
                  content: content,
                  sourceType: MemoryPoint.sourceTypeAuto,
                ),
              );
              changed = true;
            case AutoMemoryOp.opUpdate:
              final index = list.indexWhere((p) => p.id == op.id);
              if (index < 0 || !list[index].isAutoManaged) break;
              final expected = expectedRevisions?[op.id] ?? op.expectedRevision;
              if (expectedRevisions != null &&
                  !expectedRevisions.containsKey(op.id)) {
                break;
              }
              if (expected != null && list[index].revision != expected) break;
              final content = op.content.trim();
              if (content.isEmpty) break;
              if (list[index].content.trim() == content) break;
              list[index] = list[index].copyWith(
                content: content,
                revision: list[index].revision + 1,
              );
              changed = true;
            case AutoMemoryOp.opDelete:
              final index = list.indexWhere((p) => p.id == op.id);
              if (index < 0 || !list[index].isAutoManaged) break;
              final expected = expectedRevisions?[op.id] ?? op.expectedRevision;
              if (expectedRevisions != null &&
                  !expectedRevisions.containsKey(op.id)) {
                break;
              }
              if (expected != null && list[index].revision != expected) break;
              list.removeAt(index);
              changed = true;
            default:
              break;
          }
        }
        if (changed) {
          if (list.isEmpty) {
            _pointsByCharacter.remove(characterId);
          } else {
            _pointsByCharacter[characterId] = list;
          }
        }
        if (conversationId == null) {
          if (changed) await _persist(characterId);
          return;
        }
        if (cursorCount == null || cursorLastId == null) {
          throw ArgumentError('A complete cursor is required');
        }
        final db = StorageMigrationService.database;
        final dao = ConversationDao(db);
        final prefs = await SharedPreferences.getInstance();
        final raw = await dao.meta('auto_memory_cursors') ?? prefs.getString(_cursorKey);
        final cursors = raw == null || raw.isEmpty
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(jsonDecode(raw) as Map);
        cursors[conversationId] = {'count': cursorCount, 'lastId': cursorLastId};
        final journal = jsonEncode({
          'characterId': characterId,
          'points': list.map((point) => point.toJson()).toList(),
          'cursor': cursors,
        });
        if (isCurrent != null && !isCurrent()) {
          throw StateError('Auto memory request cancelled');
        }
        await db.transaction(() async {
          await dao.setMeta(_transactionKey, journal);
          await transactionTestHook?.call('journal');
          await dao.setMeta('auto_memory_cursors', jsonEncode(cursors));
        });
        await transactionTestHook?.call('committed');
        await _recoverTransaction();
      });

  /// 批量删除记忆点（记忆点管理页多选批量删除）。
  Future<void> removePoints(String characterId, List<String> pointIds) =>
      _mutate(() async {
        if (pointIds.isEmpty) return;
        final list = _pointsByCharacter[characterId];
        if (list == null) return;
        final ids = pointIds.toSet();
        final before = list.length;
        list.removeWhere((p) => ids.contains(p.id));
        if (list.length == before) return;
        if (list.isEmpty) {
          _pointsByCharacter.remove(characterId);
        }
        await _persist(characterId);
      });

  Future<void> _persist(String characterId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = _pointsByCharacter[characterId];
    if (list == null || list.isEmpty) {
      if (!await prefs.remove('$_prefix$characterId')) {
        throw StateError('Failed to persist memory points');
      }
      return;
    }
    final success = await prefs.setString(
      '$_prefix$characterId',
      jsonEncode(list.map((p) => p.toJson()).toList()),
    );
    if (!success) throw StateError('Failed to persist memory points');
  }

  Future<void> _persistInstallations() async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, dynamic>{};
    for (final entry in _installationsByCharacter.entries) {
      map[entry.key] = entry.value.map((value) => value.toJson()).toList();
    }
    await prefs.setString(_storyInstallationsKey, jsonEncode(map));
  }
}
