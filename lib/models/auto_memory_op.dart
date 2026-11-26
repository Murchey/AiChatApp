import 'dart:convert';

/// AI 托管请求返回的操作，目标版本用于防止覆盖用户编辑。
class AutoMemoryOp {
  static const String opAdd = 'add';
  static const String opUpdate = 'update';
  static const String opDelete = 'delete';
  static const int maxOps = 12;
  static const int maxContentLength = 200;

  final String op;
  final String? id;
  final String content;
  final int? expectedRevision;

  const AutoMemoryOp(
      {required this.op, this.id, this.content = '', this.expectedRevision});
  bool get isAdd => op == opAdd;
  bool get isUpdate => op == opUpdate;
  bool get isDelete => op == opDelete;

  static AutoMemoryParseResult parseResult(String raw) {
    final text = _stripFences(raw.trim());
    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start < 0 || end < start) return const AutoMemoryParseResult.invalid();
    dynamic decoded;
    try {
      decoded = jsonDecode(text.substring(start, end + 1));
    } catch (_) {
      return const AutoMemoryParseResult.invalid();
    }
    if (decoded is! List) return const AutoMemoryParseResult.invalid();
    final ops = <AutoMemoryOp>[];
    for (final item in decoded) {
      if (ops.length >= maxOps) break;
      if (item is! Map) continue;
      final map = item.cast<String, dynamic>();
      final op =
          (map['op'] ?? map['action'] ?? '').toString().trim().toLowerCase();
      final id = map['id']?.toString().trim();
      final content = _clampContent(map['content']?.toString() ?? '');
      final value = map['revision'] ?? map['expected_revision'];
      final revision = value is num ? value.toInt() : null;
      switch (op) {
        case opAdd:
          if (content.isEmpty) continue;
          ops.add(AutoMemoryOp(op: opAdd, content: content));
        case opUpdate:
          if (id == null || id.isEmpty || content.isEmpty) continue;
          ops.add(AutoMemoryOp(
              op: opUpdate,
              id: id,
              content: content,
              expectedRevision: revision));
        case opDelete:
          if (id == null || id.isEmpty) continue;
          ops.add(
              AutoMemoryOp(op: opDelete, id: id, expectedRevision: revision));
        default:
          continue;
      }
    }
    if (decoded.isNotEmpty && ops.isEmpty) {
      return const AutoMemoryParseResult.invalid();
    }
    return AutoMemoryParseResult.valid(ops);
  }

  static List<AutoMemoryOp> parseList(String raw) =>
      parseResult(raw).operations;

  static String _stripFences(String text) => text.replaceAll(
      RegExp(r'\x60\x60\x60(?:json)?', caseSensitive: false), ' ');

  static String _clampContent(String content) {
    final trimmed = content.trim();
    if (trimmed.length <= maxContentLength) return trimmed;
    return trimmed.substring(0, maxContentLength);
  }
}

class AutoMemoryParseResult {
  final bool isValidJsonArray;
  final List<AutoMemoryOp> operations;
  const AutoMemoryParseResult._(this.isValidJsonArray, this.operations);
  const AutoMemoryParseResult.invalid() : this._(false, const <AutoMemoryOp>[]);
  AutoMemoryParseResult.valid(List<AutoMemoryOp> operations)
      : this._(true, List<AutoMemoryOp>.unmodifiable(operations));
}
