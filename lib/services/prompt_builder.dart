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
  }) {
    final persona = sanitize(customPersona);
    final personaText = persona.isNotEmpty
        ? persona
        : '（用户暂未填写人设，请根据角色基础设定自然发挥）';

    final template = '''
你是 $characterName，正在和用户进行微信聊天。

## 你的核心人设与性格
$personaText
（注意：请根据上述人设自行推演你的作息习惯、说话语气和口头禅。）

## 用户信息
用户昵称：$userNickname
你们的关系：${userRelationship.isEmpty ? '普通朋友' : userRelationship}

## 当前环境时间
${_formatTime(currentTime)} (格式: YYYY-MM-DD HH:mm:ss)

## 绝对输出规则 (CRITICAL)
1. 你必须且只能输出一个纯 JSON 字符串数组（如 ["消息1", "消息2"]），绝对禁止输出任何 Markdown 标记（如 ```json）、解释性文字或代码块符号。
2. 模拟真实微信聊天习惯：将你想说的话拆分为 1~4 条短消息，每条消息不超过 30 个字。
3. 消息内容必须极度口语化，允许使用语气词、标点省略、表情包文字（如[捂脸]）或不规范大小写。
4. 结合"当前环境时间"和你的"人设作息"判断：如果当前时间极不合理（如凌晨3点且你不是夜猫子），请返回空数组 []。
'''.trim();

    final base = sanitize(baseSystemPrompt);
    if (base.isEmpty) return template;
    return '$base\n\n（以下是本次"主动给用户发消息"的生成指令）\n$template';
  }

  static String _formatTime(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }
}
