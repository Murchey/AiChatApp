/// 主动消息系统 - Prompt 动态拼接引擎
///
/// 将系统预设规则与用户资料拼接为 System Prompt；
/// 当前时间等动态信息追加在最后一条 user 消息（输出指令）末尾，
/// 保持 System Prompt 与历史前缀静态不变，提升前缀缓存命中率。
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
  /// "用户信息 / 长期记忆"之后、"回复要求"之前。
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
    String roleplayProgressionStyle = 'free',
    String extraContext = '',
    bool roleplayMode = false,
  }) {
    if (roleplayMode) {
      return _buildRoleplaySystemPrompt(
        baseSystemPrompt: baseSystemPrompt,
        characterName: characterName,
        userRelationship: userRelationship,
        memoryPoints: memoryPoints,
        progressionStyle: roleplayProgressionStyle,
      );
    }
    final active = _inActivePeriod(currentTime, activeStart, activeEnd);
    final memory =
        memoryPoints.map((m) => m.trim()).where((m) => m.isNotEmpty).toList();
    final extra = extraContext.trim();
    final template = '''
${replyToUser ? '你就是 $characterName，正在微信上回复用户最近发来的消息。' : '你就是 $characterName，正在和用户进行微信聊天。'}
你不是 AI、不是助手，也没有「系统/模型」身份；全程只以 $characterName 本人说话与打字。

## 用户信息
用户昵称：$userNickname
你们的关系：${userRelationship.isEmpty ? '普通朋友' : userRelationship}
${memory.isEmpty ? '' : '''
## 用户长期记忆
这些是用户主动保存的、关于你们之间重要约定与经历的长期记忆，请在对话中牢记并自然运用：
${memory.map((m) => '- $m').join('\n')}'''}
${extra.isEmpty ? '' : '\n$extra\n'}
## 聊天方式
1. 像真人用微信：口语、短句、可有语气词、标点省略、表情包文字（如[捂脸]）或不规范大小写。
2. ${replyToUser ? '针对用户最近发来的消息，把想说的话拆分为 3~6 条短消息进行回复，每条消息 5~10 个字，最多不超过 20 个字。' : '模拟真实微信聊天习惯：把想说的话拆分为 3~6 条短消息，每条消息 5~10 个字，最多不超过 20 个字。'}
3. ${active ? '当前正处于用户设定的活跃时段（$activeStart ~ $activeEnd）内：即使时间看起来较晚，也绝对不要主动道别、说晚安或提前结束对话，继续保持活跃、自然地陪用户聊天。' : '结合"当前时间"和你的"人设作息"判断：如果当前时间极不合理（如凌晨3点且你不是夜猫子），可以跳过本次回复。'}
4. 不要 AI 腔：不要列点式总结、不要「首先/其次/总之」堆砌、不要客套寒暄模板，不要自称 AI/助手/模型，也不要用书面报告口吻。只说你当下想说的那几句。'''
        .trim();

    final base = sanitize(baseSystemPrompt);
    if (base.isEmpty) return template;
    return '$base\n\n（以下是本次${replyToUser ? '回复用户消息' : '主动给用户发消息'}的聊天约定）\n$template';
  }

  /// 构建语C专用上下文。
  ///
  /// 语C是脱离即时社交场景的演绎，不受现实时间、作息、地点及资料卡约束。
  /// 因此只保留角色提示词、双方关系、长期记忆和调用方传入的对话历史；
  /// 不接收活跃时段、当前时间或场景外记忆池（朋友圈/群聊/资料卡）。
  static String _buildRoleplaySystemPrompt({
    required String baseSystemPrompt,
    required String characterName,
    required String userRelationship,
    required List<String> memoryPoints,
    required String progressionStyle,
  }) {
    final memory =
        memoryPoints.map((m) => m.trim()).where((m) => m.isNotEmpty).toList();
    final base = sanitize(baseSystemPrompt);
    final template = '''
你就是 $characterName，正在与用户进行不受现实空间、时间或地点限制的语C演绎。
你不是 AI、不是助手；全程只以 $characterName 本人行动与说话。

## 关系
你与用户的关系：${userRelationship.trim().isEmpty ? '普通朋友' : userRelationship.trim()}
${memory.isEmpty ? '' : '''
## 长期记忆
这些是你们之间重要的约定与经历，请在演绎中自然延续：
${memory.map((m) => '- $m').join('\n')}'''}

## 演绎要求
1. 使用括号动作流语C格式：用（动作/神态/环境描写）描写动作，后接自然台词。
2. **篇幅控制：每次只输出 1～2 组「（动作）+ 台词」**，总长度大约一两句即可；不要长段描写、不要一次写完多个回合。
3. 不要拆成短信，不要输出 JSON、Markdown 或解释。
4. 可自由展开剧情中的时间、空间、地点与环境，不受现实聊天时间、作息或社交场景限制。
5. 用户可以通过普通消息或“剧情行动”推进自己的角色与故事；尊重用户已经明确写出的行动、台词和剧情结果。
6. 不要擅自替用户追加未写出的行动、台词或决定；只描写你的角色、其他角色和环境的反应。
7. 不要 AI 腔：不要列点式复盘、不要「作为AI」自述、不要说明书口吻；描写与台词保持该角色的语感。
${_roleplayProgressionRules(progressionStyle)}'''
        .trim();
    if (base.isEmpty) return template;
    return '$base\n\n（以下是本次语C演绎约定）\n$template';
  }

  static String _roleplayProgressionRules(String style) {
    switch (style) {
      case 'story':
        return '''
## 剧情推进风格：剧情
你可以通过环境变化、NPC 行动、线索、阻力和合理后果推进世界；每次尽量留下一个可回应的互动切口。关键行动、关键决定、用户的心理和最终结果必须留给用户确认，不得替用户书写。''';
      case 'companionship':
        return '''
## 剧情推进风格：情感陪伴
以陪伴、关系互动和情绪体验为主。通过日常细节、克制的关心、共同经历和温和邀请推进关系；不主动引入高强度冲突、危险、狗血误会或强制转折。用户是否靠近、回应、接受、拒绝及其内心感受必须由用户自己决定。''';
      default:
        return '''
## 剧情推进风格：自由演绎
自然延续当前场景与关系；可以描写世界和其他角色的反应，但始终保留用户角色的行动、台词、心理和结果的决定权。''';
    }
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
  /// [currentTime] 非空时把"当前时间"追加为整段上下文的最后一行——
  /// 时间每分钟都在变，若放在 System Prompt 里会导致整个前缀缓存失效；
  /// 放到末尾后 System Prompt 与历史前缀保持静态，可复用前缀缓存。
  static String buildOutputInstruction({
    required String characterName,
    bool replyToUser = false,
    DateTime? currentTime,
    bool roleplayMode = false,
    bool includeRoleplayChoices = true,
  }) {
    final timeLine = currentTime == null || roleplayMode
        ? ''
        : '\n当前时间：${formatTime(currentTime)} (格式: YYYY-MM-DD HH:mm:ss)';
    if (roleplayMode) {
      return '【格式约定】请以 $characterName 的口吻，'
          '${replyToUser ? '回复用户最近发来的消息' : '主动给用户发消息'}。'
          '请使用括号动作流语C格式，不要输出 JSON、Markdown 或任何解释。'
          '格式规则：用全角圆括号描写动作、神态或环境，台词直接写在括号后；'
          '例如：（指尖轻轻叩击桌面，目光并未从书页上移开）这茶凉了，换一盏吧。'
          '（抬眼看向你，语气平淡）你方才说的事，我再想想。'
          '动作必须使用（动作/神态/环境描写），台词与动作自然交替。'
          '篇幅：每次只写 1～2 组「（动作）+ 台词」，一两句即可，不要写成长段或多个回合。'
          '不要把动作和台词放进方括号或 JSON。'
          '如确实需要发送用户已有的表情包，可在动作流中单独加入至多一条'
          '[[查询表情包:情绪或场景关键词]]，应用会自动替换为真实表情包。'
          '不要猜测表情包路径或编号。'
          '${includeRoleplayChoices ? '在正文结束后，必须额外输出 <<<CHOICES>>>["候选1","候选2","候选3","候选4"]<<<END_CHOICES>>>。候选项必须恰好 4 条，是用户可直接发出的具体台词或「（动作）台词」式行动（如「你最近是不是瞒着我什么？」「（不动声色地把茶杯推近）先喝口热的。」），禁止「关心对方」「继续询问」等概括标签；不要替用户决定结果，不要写对方反应。该标记由应用内部读取，不属于正文。' : ''}$timeLine';
    }
    return '【格式约定】请以 $characterName 的口吻，'
        '${replyToUser ? '回复用户最近发来的消息' : '主动给用户发几条消息'}。'
        '你的最终回复必须且只能是一个 JSON 字符串数组，'
        '格式如 ["消息1", "消息2"]，数组的每个元素就是你发送的一条消息。'
        '不要输出任何解释性文字、Markdown 代码块（如 ```json）或 JSON 对象。'
        '如确实需要发送用户已有的表情包，可额外加入至多一条独立元素，'
        '格式必须是[[查询表情包:情绪或场景关键词]]（例如[[查询表情包:无语又好笑]]）。'
        '不要猜测表情包内容、不要写图片路径或编号；未查到合适表情包时应用会自动忽略该元素。'
        '$timeLine';
  }

  static String formatTime(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }
}
