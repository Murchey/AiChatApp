/// 模型上下文长度本地注册表。
class LlmModelRegistry {
  LlmModelRegistry._();

  static const Map<String, int> exactModelContexts = {
    // OpenAI
    'gpt-4o': 128000,
    'gpt-4o-mini': 128000,
    'gpt-4.1': 1047576,
    'gpt-4.1-mini': 1047576,
    'gpt-4.1-nano': 1047576,
    'gpt-4-turbo': 128000,
    'gpt-4': 8192,
    'gpt-3.5-turbo': 16385,
    'o1': 200000,
    'o1-mini': 128000,
    'o3': 200000,
    'o3-mini': 200000,
    'o4-mini': 200000,
    // Anthropic Claude
    'claude-opus-4': 200000,
    'claude-sonnet-4': 200000,
    'claude-3-7-sonnet': 200000,
    'claude-3-5-sonnet': 200000,
    'claude-3-opus': 200000,
    'claude-3-haiku': 200000,
    // Google Gemini
    'gemini-2.5-pro': 1048576,
    'gemini-2.5-flash': 1048576,
    'gemini-2.5-flash-lite': 1048576,
    'gemini-3-flash-preview': 1048576,
    'gemini-2.0-flash': 1048576,
    'gemini-1.5-pro': 2097152,
    'gemini-1.5-flash': 1048576,
    // DeepSeek
    'deepseek-flash': 1048576,
    'deepseek-v4-pro': 1048576,
    // 旧模型名仍路由到新系（非思考/思考模式），保留以兼容老配置
    'deepseek-v4-flash': 1048576,
    'deepseek-chat': 1048576,
    'deepseek-reasoner': 1048576,
    // 智谱 GLM（上下文 1M）
    'glm-5.3': 1048576,
    'glm-5.3-flash': 1048576,
    'glm-5.3-flashx': 1048576,
    'glm-5.2': 1048576,
    // 小米 MiMo
    'mimo-v2.6-pro': 1048576,
    'mimo-2.6-flash': 1048576,
    'mimo-v2.5-pro': 1048576,
    'mimo-v2.5-omni': 1048576,
    'mimo-v2-flash': 57344,
    // xAI Grok
    'grok-4.5': 500000,
    'grok-4.20-reasoning': 2097152,
    'grok-4.20-non-reasoning': 2097152,
    'grok-4-1-fast-reasoning': 2097152,
    'grok-4-1-fast-non-reasoning': 2097152,
    // 通义千问
    'qwen-max': 32768,
    'qwen-plus': 131072,
    'qwen-turbo': 131072,
    'qwen-long': 10000000,
    'qwen-vl-max': 32768,
    // Kimi / Moonshot
    'moonshot-v1-8k': 8192,
    'moonshot-v1-32k': 32768,
    'moonshot-v1-128k': 128000,
    'kimi-k2': 128000,
    // 智谱 GLM
    'glm-4': 128000,
    'glm-4-plus': 128000,
    'glm-4-flash': 128000,
    'glm-4-long': 1000000,
    // 豆包
    'doubao-pro': 65536,
    'doubao-lite': 65536,
    // MiniMax
    'minimax-m2.7': 204800,
    'minimax-m2.7-highspeed': 204800,
    'minimax-m2.5': 204800,
    'minimax-m2.1': 204800,
    'minimax-m1': 1048576,
    'minimax-text-01': 1048576,
    'minimax-abab6.5': 24576,
    // 硅基流动 SiliconCloud（模型名为「组织/模型」格式）
    'qwen/qwen2.5-72b-instruct': 131072,
    'qwen/qwen3-8b': 131072,
    'deepseek-ai/deepseek-v3': 131072,
    'deepseek-ai/deepseek-r1': 131072,
    'thudm/glm-4-9b-0414': 131072,
    // 开源系
    'llama-3.1-405b': 128000,
    'llama-3.1-70b': 128000,
    'llama-3.3-70b': 128000,
    'mistral-large': 128000,
    'mistral-medium': 32768,
    'yi-large': 32768,
  };

  /// 常见模型上下文长度的家族启发式表（按模型名子串匹配，靠前的优先）。
  /// 仅作为注册表精确匹配未命中时的兜底。
  static const List<(String, int)> contextHeuristics = [
    ('gemini', 1048576),
    ('claude', 200000),
    ('deepseek', 1048576),
    ('grok', 500000),
    ('mimo', 1048576),
    ('gpt-4o', 128000),
    ('gpt-4-turbo', 128000),
    ('gpt-4', 8192),
    ('gpt-3.5', 16385),
    ('o3', 200000),
    ('o1', 200000),
    ('glm', 128000),
    ('moonshot', 128000),
    ('kimi', 128000),
    ('qwen-long', 10000000),
    ('qwen', 32768),
    ('doubao', 65536),
    ('minimax', 204800),
    ('mistral', 32768),
    ('llama', 32768),
    ('yi-', 32768),
    ('baichuan', 32768),
    ('gemma', 8192),
    ('spark', 8192),
    ('ernie', 8192),
  ];

  /// 纯本地（不联网）按模型名查询上下文长度：
  /// 先精确匹配注册表，未命中再用家族启发式兜底。未命中返回 null。
  static int? localContextLength(String modelName) {
    final name = modelName.trim().toLowerCase();
    if (name.isEmpty) return null;
    final exact = exactModelContexts[name];
    if (exact != null) return exact;
    return _heuristicContextLength(name);
  }

  static int? _heuristicContextLength(String name) {
    for (final (key, value) in contextHeuristics) {
      if (name.contains(key)) return value;
    }
    return null;
  }
}
