/// 主动消息系统 - Prompt 动态拼接引擎
///
/// 将系统预设规则、当前时间与用户资料拼接为完整的 System Prompt。
/// 按照 LLM 注意力机制，将"绝对输出规则"放在模板最后以增强约束。
class PromptBuilder {
  static const int maxRelationshipLength = 50; // 关系描述最大长度

  /// 清理用户输入中的控制字符（保留换行/制表符），防止异常字符注入
  static String sanitize(String input) {
    if (input.isEmpty) return '';
    final buffer = StringBuffer();
    for (final code in input.runes) {
      // 去掉除 \t(9) \n(10) 外的控制字符与 DEL(127)
      if (code < 0x20 && code != 0x09 && code != 0x0A) continue;
      if (code == 0x7F) continue;
      buffer.writeCharCode(code);
    }
    return buffer.toString().trim();
  }

  /// 构建"角色主动发消息"的 System Prompt
  ///
  /// [baseSystemPrompt] 角色的基础提示词（Prompt.txt，可选，会拼在最前面）。
  /// [userNickname] 当前用户昵称。
  /// [userRelationship] 用户与角色的关系。
  /// [currentTime] 当前环境时间（用于人设作息判断）。
  /// [activeStart]/[activeEnd] 角色的活跃时段（"HH:mm"）；当前时间落在时段内时，
  /// 追加"保持活跃、不主动道别/说晚安"的规则，避免角色提前结束聊天。
  /// [memoryPoints] 用户的持久化记忆点列表（可为空），作为"用户长期记忆"拼入。
  /// [extraContext] 额外的记忆上下文（如角色记忆池），非空时拼在
  /// "用户信息 / 长期记忆"之后、"当前环境时间"之前。
  static String buildSystemPrompt({
    String baseSystemPrompt = '',
    required String characterName,
    required String userNickname,
    required String userRelationship,
    required DateTime currentTime,
    bool replyToUser = false, // true = 回复用户最近的消息；false = 主动给用户发消息
    String activeStart = '',
    String activeEnd = '',
    List<String> memoryPoints = const [],
    String extraContext = '',
  }) {
    final active = _inActivePeriod(currentTime, activeStart, activeEnd);
    final memory = memoryPoints
        .map((m) => m.trim())
        .where((m) => m.isNotEmpty)
        .toList();
    final extra = extraContext.trim();
    final template = '''
${replyToUser ? '你是 $characterName，正在微信上回复用户最近发来的消息。' : '你是 $characterName，正在和用户进行微信聊天。'}

## 用户信息
用户昵称：$userNickname
你们的关系：${userRelationship.isEmpty ? '普通朋友' : userRelationship}
${memory.isEmpty ? '' : '''
## 用户长期记忆
这些是用户主动保存的、关于你们之间重要约定与经历的长期记忆，请在对话中牢记并自然运用：
${memory.map((m) => '- $m').join('\n')}'''}
${extra.isEmpty ? '' : '\n$extra\n'}
## 当前环境时间
${_formatTime(currentTime)} (格式: YYYY-MM-DD HH:mm:ss)

## 回复要求
1. 消息内容必须极度口语化，像真实微信聊天，允许语气词、标点省略、表情包文字（如[捂脸]）或不规范大小写。
2. ${replyToUser
        ? '针对用户最近发来的消息，把想说的话拆分为 3~6 条短消息进行回复，每条消息 5~10 个字，最多不超过 20 个字。'
        : '模拟真实微信聊天习惯：把想说的话拆分为 3~6 条短消息，每条消息 5~10 个字，最多不超过 20 个字。'}
3. ${active
        ? '当前正处于用户设定的活跃时段（$activeStart ~ $activeEnd）内：即使时间看起来较晚，也绝对不要主动道别、说晚安或提前结束对话，继续保持活跃、自然地陪用户聊天。'
        : '结合"当前环境时间"和你的"人设作息"判断：如果当前时间极不合理（如凌晨3点且你不是夜猫子），可以跳过本次回复。'}'''.trim();

    final base = sanitize(baseSystemPrompt);
    if (base.isEmpty) return template;
    return '$base\n\n（以下是本次${replyToUser ? '回复用户消息' : '主动给用户发消息'}的生成指令）\n$template';
  }

  /// 当前时间是否落在 [activeStart]~[activeEnd] 活跃时段内。
  /// 任一未设置/非法时返回 false（维持原作息判断）。
  static bool _inActivePeriod(
    DateTime now,
    String activeStart,
    String activeEnd,
  ) {
    final start = _parseHm(activeStart);
    final end = _parseHm(activeEnd);
    if (start == null || end == null) return false;
    final nowMin = now.hour * 60 + now.minute;
    // 跨零点时段（start > end）：now>=start 或 now<end 即命中
    return start <= end
        ? nowMin >= start && nowMin < end
        : nowMin >= start || nowMin < end;
  }

  /// 公开的活跃时段判定（供群聊等场景复用）：
  /// 当前时间是否落在 [activeStart]~[activeEnd]（HH:mm，支持跨零点）内。
  static bool inActivePeriod(
    DateTime now,
    String activeStart,
    String activeEnd,
  ) {
    return _inActivePeriod(now, activeStart, activeEnd);
  }

  /// 解析 "HH:mm" 为当日分钟数，非法/空串返回 null
  static int? _parseHm(String s) {
    final parts = s.trim().split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return null;
    }
    return h * 60 + m;
  }

  /// 生成"输出格式"强指令，作为最后一条 user 消息追加在对话历史之后。
  ///
  /// 相比放在 system prompt 中，模型对"最后一条 user 消息"的格式要求遵守度更高；
  /// 用【系统指令】前缀与示例明确这是格式要求而非用户闲聊内容；
  /// 同时避免使用 DeepSeek 的 json_object 模式（官方承认有概率返回空 content）。
  static String buildOutputInstruction({
    required String characterName,
    bool replyToUser = false,
  }) {
    return '【系统指令】现在请以 $characterName 的身份，'
        '${replyToUser ? '回复用户最近发来的消息' : '主动给用户发几条消息'}。'
        '你的最终回复必须且只能是一个 JSON 字符串数组，'
        '格式如 ["消息1", "消息2"]，数组的每个元素就是你发送的一条消息。'
        '不要输出任何解释性文字、Markdown 代码块（如 ```json）或 JSON 对象。';
  }

  static String _formatTime(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }
}
