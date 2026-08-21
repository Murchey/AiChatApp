import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/token_usage.dart';
import '../services/llm_service.dart';
import '../services/widget_sync_service.dart';

/// 各会话（私聊 / 群聊）累计 token 消耗统计。
///
/// 在每次真实 LLM 调用成功后累加该轮的实际用量：
/// - 输入 tokens = API usage.prompt_tokens（系统提示词 + 历史上下文回传 + 本次提问，
///   即每轮真正发送给 API 的完整 prompt；多轮对话中逐轮递增）
/// - 输出 tokens = API usage.completion_tokens（AI 回复）
///
/// 数据按会话 id（私聊 conversationId / 群聊 groupId）存储并持久化，
/// 展示页可随时读取、一键重置。
/// 单例（应用级共享），同时在 Provider 树中注册供 UI 监听刷新。
class TokenUsageProvider extends ChangeNotifier {
  TokenUsageProvider._();
  static final TokenUsageProvider instance = TokenUsageProvider._();

  static const _storageKey = 'chat_token_usage_v1';
  static const _maxEntries = 500; // 防止会话无限增长导致存储膨胀

  /// 朋友圈互动（浏览点赞/评论回复/自动发帖）的聚合统计 id，
  /// 朋友圈不归属某个私聊/群聊会话，统一归入该固定 id 便于展示页分类。
  static const kMomentUsageId = 'moment_interactions';

  Map<String, TokenUsage> _usages = {};
  bool _loaded = false;
  Future<void>? _loading; // 正在进行的加载 Future：并发调用共享，避免重复/漏加载

  /// 读取持久化数据（首次调用时；重复调用无副作用）。
  ///
  /// 加载采用单飞（single-flight）：并发的多次调用等待同一个加载 Future，
  /// 确保任何写入都发生在数据就绪之后，不会用空数据覆盖已持久化的统计
  /// （此前 _loaded 先置 true、未等真正加载完就放行后续写入，更新后首次
  /// 聊天时会用空统计覆盖磁盘数据，导致累计消耗被"重置"）。
  Future<void> init() {
    if (_loaded) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _usages = decoded.map((k, v) {
          if (v is! Map<String, dynamic>) {
            return MapEntry(k, const TokenUsage());
          }
          return MapEntry(k, TokenUsage.fromJson(v));
        });
      }
    } catch (_) {
      // 数据损坏/解析失败按空数据启动（下次写入会覆盖），不影响应用使用
      _usages = {};
    } finally {
      _loaded = true;
      _loading = null;
      // 加载完成后通知监听者重建界面：否则统计页在 init 完成前先渲染一次
      // 空数据，数据就绪后没有重建通知，页面会一直停留在"暂无记录"的假清零状态。
      notifyListeners();
    }
  }

  /// 记录一次真实 token 用量（API 未返回 usage 时忽略）。
  /// 返回累计后的该会话用量（供调用方决定是否展示）。
  Future<TokenUsage> addUsage(String conversationId, ChatUsage usage) async {
    if (usage.isEmpty) return usageFor(conversationId);
    await init();
    final prev = _usages[conversationId] ?? const TokenUsage();
    final next = TokenUsage(
      sentTokens: prev.sentTokens + (usage.promptTokens ?? 0),
      receivedTokens: prev.receivedTokens + (usage.completionTokens ?? 0),
    );
    _usages[conversationId] = next;
    if (_usages.length > _maxEntries) {
      // 只保留消耗最大的会话，避免无限膨胀
      final entries = _usages.entries.toList()
        ..sort((a, b) => b.value.totalTokens.compareTo(a.value.totalTokens));
      _usages = Map.fromEntries(entries.take(_maxEntries));
    }
    notifyListeners();
    await _persist();
    _syncToWidget();
    return next;
  }
  
  /// 同步数据到小组件
  void _syncToWidget() {
    // 异步同步，不阻塞主流程
    Future.microtask(() async {
      try {
        // 计算各分类统计
        int privateChat = 0, groupChat = 0, moment = 0;
        _usages.forEach((id, usage) {
          if (id == kMomentUsageId) {
            moment = usage.totalTokens;
          } else if (id.startsWith('group_')) {
            groupChat += usage.totalTokens;
          } else {
            privateChat += usage.totalTokens;
          }
        });
        
        await WidgetSyncService.syncTokenUsage(
          total: total,
          sent: sentTotal,
          received: receivedTotal,
          privateChat: privateChat,
          groupChat: groupChat,
          moment: moment,
        );
      } catch (e) {
        debugPrint('[TokenUsageProvider] Widget sync failed: $e');
      }
    });
  }

  /// 某会话的累计用量（无记录返回空用量）
  TokenUsage usageFor(String conversationId) =>
      _usages[conversationId] ?? const TokenUsage();

  /// 全部会话用量快照（会话 id → 用量）
  Map<String, TokenUsage> get allUsages => Map.unmodifiable(_usages);

  /// 全部会话累计发送的 token
  int get sentTotal =>
      _usages.values.fold<int>(0, (sum, u) => sum + u.sentTokens);

  /// 全部会话累计接收的 token
  int get receivedTotal =>
      _usages.values.fold<int>(0, (sum, u) => sum + u.receivedTokens);

  /// 全部会话累计消耗（发送 + 接收）
  int get total => sentTotal + receivedTotal;

  /// 是否有任何会话有消耗记录
  bool get hasAny => _usages.values.any((u) => !u.isEmpty);

  /// 一键重置全部会话的 token 计数
  Future<void> resetAll() async {
    await init();
    if (_usages.isEmpty) return;
    _usages = {};
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode(_usages.map((k, v) => MapEntry(k, v.toJson()))),
      );
    } catch (_) {
      // 持久化失败不影响内存统计
    }
  }
}
