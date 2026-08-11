/// 厂商快捷预设数据（本地硬编码：OpenAI 兼容提供商及其推荐模型）。
///
/// 模型列表与请求地址为本地静态数据，离线可用；模型名称仅为"推荐清单"，
/// 进入厂商设置页后可用【检测可用模型】在线拉取该服务商真实模型列表。
class ProviderPreset {
  final String name; // 厂商名称
  final String description; // 一句话说明
  final String baseUrl; // OpenAI 兼容请求地址
  final List<({String displayName, String modelName})> models; // 推荐模型

  const ProviderPreset({
    required this.name,
    required this.description,
    required this.baseUrl,
    required this.models,
  });
}

/// 内置厂商列表（均兼容 OpenAI 接口，请求地址为官方最新值）
const List<ProviderPreset> providerPresets = [
  ProviderPreset(
    name: 'OpenAI',
    description: 'GPT-4o / GPT-4.1 / o 系列官方接口',
    baseUrl: 'https://api.openai.com/v1',
    models: [
      (displayName: 'OpenAI GPT-4o', modelName: 'gpt-4o'),
      (displayName: 'OpenAI GPT-4o mini', modelName: 'gpt-4o-mini'),
      (displayName: 'OpenAI GPT-4.1', modelName: 'gpt-4.1'),
      (displayName: 'OpenAI GPT-4.1 mini', modelName: 'gpt-4.1-mini'),
      (displayName: 'OpenAI o3', modelName: 'o3'),
      (displayName: 'OpenAI o4-mini', modelName: 'o4-mini'),
    ],
  ),
  ProviderPreset(
    name: 'Google Gemini',
    description: 'AI Studio 官方兼容端点，模型名以 gemini- 开头',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
    models: [
      (displayName: 'Gemini 2.5 Pro', modelName: 'gemini-2.5-pro'),
      (displayName: 'Gemini 2.5 Flash', modelName: 'gemini-2.5-flash'),
      (displayName: 'Gemini 2.5 Flash-Lite', modelName: 'gemini-2.5-flash-lite'),
      (displayName: 'Gemini 2.0 Flash', modelName: 'gemini-2.0-flash'),
    ],
  ),
  ProviderPreset(
    name: '小米 MiMo',
    description: '按量付费，官方平台 platform.xiaomimimo.com',
    baseUrl: 'https://api.xiaomimimo.com/v1',
    models: [
      (displayName: 'MiMo V2.5 Pro', modelName: 'mimo-v2.5-pro'),
      (displayName: 'MiMo V2 Flash', modelName: 'mimo-v2-flash'),
      (displayName: 'MiMo V2.5 Omni', modelName: 'mimo-v2.5-omni'),
    ],
  ),
  ProviderPreset(
    name: '小米 MiMo Token Plan',
    description: '订阅制套餐，API Key 以 tp- 开头',
    baseUrl: 'https://token-plan-cn.xiaomimimo.com/v1',
    models: [
      (displayName: 'MiMo V2.5 Pro', modelName: 'mimo-v2.5-pro'),
      (displayName: 'MiMo V2 Flash', modelName: 'mimo-v2-flash'),
    ],
  ),
  ProviderPreset(
    name: 'DeepSeek',
    description: 'V4 系列，baseUrl 与官方一致',
    baseUrl: 'https://api.deepseek.com',
    models: [
      (displayName: 'DeepSeek V4 Flash', modelName: 'deepseek-v4-flash'),
      (displayName: 'DeepSeek V4 Pro', modelName: 'deepseek-v4-pro'),
    ],
  ),
  ProviderPreset(
    name: 'Grok (xAI)',
    description: 'Grok 4.5 旗舰，2M 上下文',
    baseUrl: 'https://api.x.ai/v1',
    models: [
      (displayName: 'Grok 4.5', modelName: 'grok-4.5'),
      (displayName: 'Grok 4.20 Reasoning', modelName: 'grok-4.20-reasoning'),
      (displayName: 'Grok 4.1 Fast Reasoning', modelName: 'grok-4-1-fast-reasoning'),
    ],
  ),
  ProviderPreset(
    name: '阿里云百炼',
    description: 'DashScope 兼容模式，通义千问系列',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    models: [
      (displayName: '通义千问 Max', modelName: 'qwen-max'),
      (displayName: '通义千问 Plus', modelName: 'qwen-plus'),
      (displayName: '通义千问 Turbo', modelName: 'qwen-turbo'),
      (displayName: '通义千问 Long', modelName: 'qwen-long'),
      (displayName: '通义千问 VL Max', modelName: 'qwen-vl-max'),
    ],
  ),
  ProviderPreset(
    name: '硅基流动 SiliconFlow',
    description: '开源模型聚合平台，模型名带组织前缀',
    baseUrl: 'https://api.siliconflow.cn/v1',
    models: [
      (displayName: 'Qwen2.5 72B', modelName: 'Qwen/Qwen2.5-72B-Instruct'),
      (displayName: 'Qwen3 8B', modelName: 'Qwen/Qwen3-8B'),
      (displayName: 'DeepSeek V3', modelName: 'deepseek-ai/DeepSeek-V3'),
      (displayName: 'DeepSeek R1', modelName: 'deepseek-ai/DeepSeek-R1'),
      (displayName: 'GLM-4 9B', modelName: 'THUDM/GLM-4-9B-0414'),
    ],
  ),
  ProviderPreset(
    name: 'Kimi (Moonshot)',
    description: 'Kimi 官方开放平台，moonshot 系列',
    baseUrl: 'https://api.moonshot.cn/v1',
    models: [
      (displayName: 'Kimi K2', modelName: 'kimi-k2'),
      (displayName: 'Moonshot v1 8K', modelName: 'moonshot-v1-8k'),
      (displayName: 'Moonshot v1 32K', modelName: 'moonshot-v1-32k'),
      (displayName: 'Moonshot v1 128K', modelName: 'moonshot-v1-128k'),
    ],
  ),
  ProviderPreset(
    name: 'MiniMax',
    description: 'M 系列旗舰，OpenAI 兼容地址',
    baseUrl: 'https://api.minimaxi.com/v1',
    models: [
      (displayName: 'MiniMax M2.7', modelName: 'MiniMax-M2.7'),
      (displayName: 'MiniMax M2.7 HighSpeed', modelName: 'MiniMax-M2.7-highspeed'),
      (displayName: 'MiniMax M2.5', modelName: 'MiniMax-M2.5'),
      (displayName: 'MiniMax M2.1', modelName: 'MiniMax-M2.1'),
    ],
  ),
];
