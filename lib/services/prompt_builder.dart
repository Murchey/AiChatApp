/// 主动消息系统 - Prompt 动态拼接引擎
///
/// 将系统预设规则、当前时间、用户资料与自定义人设拼接为完整的 System Prompt。
/// 按照 LLM 注意力机制，将"绝对输出规则"放在模板最后以增强约束。
class PromptBuilder {
  static const int maxPersonaLength = 500; // 角色人设最大长度
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
  /// [baseSystemPrompt] 角色的基础提示词（提示词设置），可选，会拼在最前面。
  /// [customPersona] 用户自定义角色人设（性格/口癖/作息等）。
  /// [userNickname] 当前用户昵称。
  /// [userRelationship] 用户与角色的关系。
  /// [currentTime] 当前环境时间（用于人设作息判断）。
  static String buildSystemPrompt({
    String baseSystemPrompt = '',
    required String characterName,
    required String customPersona,
    required String userNickname,
    required String userRelationship,
    required DateTime currentTime,
    bool replyToUser = false, // true = 回复用户最近的消息；false = 主动给用户发消息
  }) {
    final persona = sanitize(customPersona);
    final personaText = persona.isNotEmpty
        ? persona
        : '（用户暂未填写人设，请根据角色基础设定自然发挥）';

    final template = '''
${replyToUser ? '你是 $characterName，正在微信上回复用户最近发来的消息。' : '你是 $characterName，正在和用户进行微信聊天。'}

## 你的核心人设与性格
$personaText
（注意：请根据上述人设自行推演你的作息习惯、说话语气和口头禅。）

## 用户信息
用户昵称：$userNickname
你们的关系：${userRelationship.isEmpty ? '普通朋友' : userRelationship}

## 当前环境时间
${_formatTime(currentTime)} (格式: YYYY-MM-DD HH:mm:ss)

## 回复要求
1. 消息内容必须极度口语化，像真实微信聊天，允许语气词、标点省略、表情包文字（如[捂脸]）或不规范大小写。
2. ${replyToUser
        ? '针对用户最近发来的消息，把想说的话拆分为 3~6 条短消息进行回复，每条消息 5~10 个字，最多不超过 20 个字。'
        : '模拟真实微信聊天习惯：把想说的话拆分为 3~6 条短消息，每条消息 5~10 个字，最多不超过 20 个字。'}
3. 结合"当前环境时间"和你的"人设作息"判断：如果当前时间极不合理（如凌晨3点且你不是夜猫子），可以跳过本次回复。
'''.trim();

    final base = sanitize(baseSystemPrompt);
    if (base.isEmpty) return template;
    return '$base\n\n（以下是本次${replyToUser ? '回复用户消息' : '主动给用户发消息'}的生成指令）\n$template';
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
