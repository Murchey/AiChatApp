import 'dart:convert';

/// 记忆点自动托管：AI 剧情记录返回的操作项。
///
/// 模型输出 JSON 操作数组（见 AutoMemoryService 的记录指令）：
/// `[{"op":"add","content":"…"},{"op":"update","id":"…","content":"…"},{"op":"delete","id":"…"}]`
/// 解析后交给 MemoryPointProvider.applyAutoOperations 执行；
/// update/delete 仅允许指向 AI 托管（sourceType == 'auto'）条目，越权由 Provider 兜底忽略。
class AutoMemoryOp {
  static const String opAdd = 'add';
  static const String opUpdate = 'update';
  static const String opDelete = 'delete';

  /// 单次响应最多接受的操作条数（防止模型失控输出）。
  static const int maxOps = 12;

  /// 单条内容最大长度（字符）。
  static const int maxContentLength = 200;

  final String op;

  /// update/delete 的目标记忆点 id；add 时为空。
  final String? id;
  final String content;

  const AutoMemoryOp({required this.op, this.id, this.content = ''});

  bool get isAdd => op == opAdd;
  bool get isUpdate => op == opUpdate;
  bool get isDelete => op == opDelete;

  /// 从模型原始输出容错解析操作列表：
  /// - 剥离 ```json 代码围栏；
  /// - 截取首个 '[' 与末个 ']' 之间的 JSON 数组；
  /// - 忽略非法项（未知 op、add 无内容、update/delete 无 id）；
  /// - 最多保留 [maxOps] 条，内容 trim 并截断至 [maxContentLength] 字。
  static List<AutoMemoryOp> parseList(String raw) {
    final text = _stripFences(raw.trim());
    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start < 0 || end <= start) return const [];
    final arrayText = text.substring(start, end + 1);
    List<dynamic> decoded;
    try {
      decoded = jsonDecode(arrayText) as List<dynamic>;
    } catch (_) {
      return const [];
    }
    final ops = <AutoMemoryOp>[];
    for (final item in decoded) {
      if (ops.length >= maxOps) break;
      if (item is! Map) continue;
      final map = item.cast<String, dynamic>();
      final op = (map['op'] ?? map['action'] ?? '').toString().trim().toLowerCase();
      final id = map['id']?.toString().trim();
      final content = _clampContent(map['content']?.toString() ?? '');
      switch (op) {
        case opAdd:
          if (content.isEmpty) continue;
          ops.add(AutoMemoryOp(op: opAdd, content: content));
        case opUpdate:
          if (id == null || id.isEmpty || content.isEmpty) continue;
          ops.add(AutoMemoryOp(op: opUpdate, id: id, content: content));
        case opDelete:
          if (id == null || id.isEmpty) continue;
          ops.add(AutoMemoryOp(op: opDelete, id: id));
        default:
          continue;
      }
    }
    return ops;
  }

  static String _stripFences(String text) {
    // ```json ... ``` 或 ``` ... ```
    return text.replaceAll(RegExp(r'```(?:json)?', caseSensitive: false), ' ');
  }

  static String _clampContent(String content) {
    final trimmed = content.trim();
    if (trimmed.length <= maxContentLength) return trimmed;
    return trimmed.substring(0, maxContentLength);
  }
}
