part of 'llm_service.dart';

  Future<ProactiveResult> generateMessages({
    required ApiModel model,
    required String systemPrompt,
    List<Map<String, Object>> historyMessages = const [],
    String outputInstruction = '',
    bool roleplayMode = false,
  }) async {
    final completion = await LLMService._fetchWithKimiFallback(
      model: model,
      messages: [
        {'role': 'system', 'content': systemPrompt},
        ...historyMessages,
        if (outputInstruction.trim().isNotEmpty)
          {'role': 'user', 'content': outputInstruction.trim()},
      ],
      maxTokens: 1024,
    );
    final raw = completion.content;
    debugPrint('[LLMService] 模型原始响应: $raw');
    final result =
        roleplayMode ? LLMService.parseRoleplayMessage(raw) : LLMService.parseMessages(raw);
    debugPrint('[LLMService] 解析结果(${result.length}条): $result');
    return ProactiveResult(
      result,
      completion.usage,
      reasoningContent: completion.reasoningContent,
      reasoningDurationMs: completion.reasoningDurationMs,
    );
  }

  /// 为语C正文回复提供 4 个可继续推进剧情的候选行动。
  /// 候选项仅用于填入输入框，不会写入聊天记录。
  Future<ProactiveResult> generateRoleplayChoices({
    required ApiModel model,
    required String systemPrompt,
    required List<Map<String, String>> historyMessages,
  }) async {
    const instruction = '【系统指令】基于当前语C剧情，给用户提供恰好 4 个可选的下一步行动或台词。\n'
        '要求：\n'
        '1. 每一条都必须是用户可以直接发出的具体内容（完整台词，或「（动作）台词」式行动），'
        '点一下就能发进聊天，不要概括、不要抽象标签。\n'
        '2. 禁止「关心对方」「继续询问」「转移话题」这类概括；'
        '要写成具体话或具体动作。\n'
        '3. 四条尽量方向不同（如：靠近 / 试探 / 拒绝 / 旁敲侧击），但每条都仍要具体。\n'
        '4. 不要替用户决定结果，不要写对方的反应。\n'
        '示例（好）：「你最近是不是瞒着我什么？」'
        '「（不动声色地把茶杯推近）先喝口热的。」\n'
        '示例（坏）：「询问对方」「表达关心」「继续对话」。\n'
        '只输出 JSON 字符串数组，例如：["台词或行动1","台词或行动2","台词或行动3","台词或行动4"]，不要输出其他内容。';
    final completion = await LLMService._fetchWithKimiFallback(
      model: model,
      messages: [
        {'role': 'system', 'content': systemPrompt},
        ...historyMessages,
        {'role': 'user', 'content': instruction},
      ],
      maxTokens: 400,
      initialTemperature: 0.7,
    );
    return ProactiveResult(
      LLMService.parseMessages(completion.content).take(4).toList(),
      completion.usage,
    );
  }

  /// 剧情建议：基于当前聊天上下文（可附用户补充）生成可直接填入输入框的建议。
  /// 语C / 短信通用；建议写成用户可以直接发出的内容，用来指导 AI 继续推进对话。
  /// 不会写入聊天记录。
  Future<ProactiveResult> generatePlotSuggestions({
    required ApiModel model,
    required String systemPrompt,
    required List<Map<String, String>> historyMessages,
    String userSupplement = '',
    bool roleplayMode = false,
  }) async {
    final supplement = userSupplement.trim();
    final supplementBlock = supplement.isEmpty
        ? ''
        : '\n\n用户的补充（必须融入建议，不可忽略）：\n$supplement';
    final instruction = (roleplayMode
            ? '【系统指令】你是剧情导演，不是角色本人。基于当前语C剧情，'
                '给用户提供恰好 3 条剧情建议，帮用户决定下一步怎么推进故事，'
                '用户选一条发出后即可指导 AI 沿该方向继续聊天。\n'
                '要求：\n'
                '1. 每条建议都是用户可以直接发出的内容：完整台词，或「（动作）台词」式剧情行动。\n'
                '2. 三条方向不同（如：推进主线 / 拉近关系 / 制造冲突），但都要具体、可发送。\n'
                '3. 不要替用户决定结果，不要写对方的反应。\n'
                '示例（好）：「（把密信推到桌上）这封信是谁送来的？」'
                '「我今晚就走，你别拦我。」\n'
                '示例（坏）：「推进主线」「继续发展关系」。\n'
                '只输出 JSON 字符串数组，例如：["建议1","建议2","建议3"]，不要输出其他内容。'
            : '【系统指令】你是对话剧情顾问，不是聊天对方。基于当前聊天记录，'
                '给用户提供恰好 3 条剧情建议，帮用户想好下一句怎么回，'
                '用户选一条发出后即可指导 AI 沿该方向继续聊下去。\n'
                '要求：\n'
                '1. 每条建议都是用户可以直接发出的消息内容（口语、符合当前聊天氛围）。\n'
                '2. 三条方向不同（如：顺着话题深入 / 抛出新话题 / 暗示下一步安排），但都要具体、可发送。\n'
                '3. 不要写对方的回复，禁止「继续聊」「关心对方」这类概括标签。\n'
                '示例（好）：「刚下班，今天那家店还开着吗？」'
                '「上次你说的事，后来怎么样了？」\n'
                '示例（坏）：「继续话题」「询问近况」。\n'
                '只输出 JSON 字符串数组，例如：["建议1","建议2","建议3"]，不要输出其他内容。') +
        supplementBlock;
    final completion = await LLMService._fetchWithKimiFallback(
      model: model,
      messages: [
        {'role': 'system', 'content': systemPrompt},
        ...historyMessages,
        {'role': 'user', 'content': instruction},
      ],
      maxTokens: 600,
      initialTemperature: 0.8,
    );
    return ProactiveResult(
      LLMService.parseMessages(completion.content).take(4).toList(),
      completion.usage,
    );
  }

  /// 发送图片消息：以 OpenAI 兼容的视觉消息格式，把用户选择的图片
  /// （转 base64 data URL）连同输出指令作为最后一条 user 消息发给模型，
  /// 让角色"看到"图片后按 JSON 数组格式回复。
  ///
  /// [historyMessages] 为最近的文本对话历史（不含本图片），
  /// [outputInstruction] 复用普通文本的格式强指令。
  /// 图片读取失败时抛出 [LLMException]（可读提示）。
  Future<ProactiveResult> generateVisionReply({
    required ApiModel model,
    required String systemPrompt,
    required List<Map<String, Object>> historyMessages,
    required String imagePath,
    required String outputInstruction,
    bool roleplayMode = false,
  }) async {
    String base64;
    try {
      final bytes = await File(imagePath).readAsBytes();
      base64 = base64Encode(bytes);
    } catch (_) {
      throw const LLMException('无法读取图片，请重新选择图片后重试');
    }
    final completion = await LLMService._fetchWithKimiFallback(
      model: model,
      messages: [
        {'role': 'system', 'content': systemPrompt},
        ...historyMessages,
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': outputInstruction.trim()},
            {
              'type': 'image_url',
              'image_url': {
                'url': 'data:${_imageMime(imagePath)};base64,$base64',
              },
            },
          ],
        },
      ],
      maxTokens: 1024,
    );
    final raw = completion.content;
    debugPrint('[LLMService] 模型原始响应: $raw');
    final result =
        roleplayMode ? LLMService.parseRoleplayMessage(raw) : LLMService.parseMessages(raw);
    debugPrint('[LLMService] 解析结果(${result.length}条): $result');
    return ProactiveResult(
      result,
      completion.usage,
      reasoningContent: completion.reasoningContent,
      reasoningDurationMs: completion.reasoningDurationMs,
    );
  }

  /// 按文件扩展名推断图片 MIME（OpenAI 视觉格式要求 data URL 带类型）
String _imageMime(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'image/jpeg';
    }
  }

  /// OpenAI 兼容 SSE 流式补全，仅语C正文使用，同时透传流式 usage。
  Stream<StreamCompletionChunk> streamCompletion({
    required ApiModel model,
    required List<Map<String, Object>> messages,
    int maxTokens = 1024,
    double temperature = 0.9,
  }) async* {
    if (model.modelName.isEmpty) {
      throw const LLMException('所选模型未填写模型名称，请到「API 设置」中检查');
    }
    if (model.apiKey.isEmpty) {
      throw const LLMException('所选模型未配置 API Key，请到「API 设置」中填写');
    }
    var base =
        model.baseUrl.trim().isNotEmpty ? model.baseUrl.trim() : LLMService.defaultBaseUrl;
    base = base.replaceAll(RegExp(r'/+$'), '');
    final url =
        base.endsWith('/chat/completions') ? base : '$base/chat/completions';
    final client = HttpClient();
    try {
      final request = await client
          .postUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      request.headers.set(
          HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      request.headers
          .set(HttpHeaders.authorizationHeader, 'Bearer ${model.apiKey}');
      request.add(utf8.encode(jsonEncode({
        'model': model.modelName,
        'messages': messages,
        'stream': true,
        'stream_options': {'include_usage': true},
        'max_tokens': maxTokens,
        'temperature': temperature,
        ...LLMService.thinkingRequestFields(),
      })));
      final response =
          await request.close().timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) {
        final body = await response.transform(utf8.decoder).join();
        throw LLMException(
            'API 请求失败：HTTP ${response.statusCode} ${body.trim()}');
      }
      await for (final line
          in response.transform(utf8.decoder).transform(const LineSplitter())) {
        if (!line.startsWith('data:')) continue;
        final data = line.substring(5).trim();
        if (data == '[DONE]') break;
        final chunk = LLMService.parseStreamChunk(data);
        if (chunk.content.isNotEmpty || chunk.reasoning.isNotEmpty || !chunk.usage.isEmpty) {
        yield chunk;
      }
      }
    } finally {
      client.close(force: true);
    }
  }

  /// 解析单个 OpenAI 兼容 SSE data payload。
  /// usage 通常出现在最后一条、且 choices 为空的事件。
