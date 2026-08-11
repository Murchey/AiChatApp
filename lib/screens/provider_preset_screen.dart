import 'package:flutter/cupertino.dart';
import '../config/theme.dart';
import 'model_edit_screen.dart';

/// 提供商快捷预设数据
class _ProviderPreset {
  final String name; // 提供商名称
  final String description; // 一句话说明
  final String baseUrl; // OpenAI 兼容请求地址
  final List<({String displayName, String modelName})> models; // 推荐模型

  const _ProviderPreset({
    required this.name,
    required this.description,
    required this.baseUrl,
    required this.models,
  });
}

/// 内置提供商列表（均兼容 OpenAI 接口，请求地址为官方最新值）
const List<_ProviderPreset> _presets = [
  _ProviderPreset(
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
  _ProviderPreset(
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
  _ProviderPreset(
    name: '小米 MiMo',
    description: '按量付费，官方平台 platform.xiaomimimo.com',
    baseUrl: 'https://api.xiaomimimo.com/v1',
    models: [
      (displayName: 'MiMo V2.5 Pro', modelName: 'mimo-v2.5-pro'),
      (displayName: 'MiMo V2 Flash', modelName: 'mimo-v2-flash'),
      (displayName: 'MiMo V2.5 Omni', modelName: 'mimo-v2.5-omni'),
    ],
  ),
  _ProviderPreset(
    name: '小米 MiMo Token Plan',
    description: '订阅制套餐，API Key 以 tp- 开头',
    baseUrl: 'https://token-plan-cn.xiaomimimo.com/v1',
    models: [
      (displayName: 'MiMo V2.5 Pro', modelName: 'mimo-v2.5-pro'),
      (displayName: 'MiMo V2 Flash', modelName: 'mimo-v2-flash'),
    ],
  ),
  _ProviderPreset(
    name: 'DeepSeek',
    description: 'V4 系列，baseUrl 与官方一致',
    baseUrl: 'https://api.deepseek.com',
    models: [
      (displayName: 'DeepSeek V4 Flash', modelName: 'deepseek-v4-flash'),
      (displayName: 'DeepSeek V4 Pro', modelName: 'deepseek-v4-pro'),
    ],
  ),
  _ProviderPreset(
    name: 'Grok (xAI)',
    description: 'Grok 4.5 旗舰，2M 上下文',
    baseUrl: 'https://api.x.ai/v1',
    models: [
      (displayName: 'Grok 4.5', modelName: 'grok-4.5'),
      (displayName: 'Grok 4.20 Reasoning', modelName: 'grok-4.20-reasoning'),
      (displayName: 'Grok 4.1 Fast Reasoning', modelName: 'grok-4-1-fast-reasoning'),
    ],
  ),
  _ProviderPreset(
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
  _ProviderPreset(
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
  _ProviderPreset(
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
  _ProviderPreset(
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

/// 快捷预设二级页面：常用 OpenAI 兼容提供商列表
///
/// 点击提供商弹出其推荐模型，选择后进入「添加模型」页面，
/// 自动预填 API 请求地址与模型名称，仅需补充 API Key。
/// 上下文长度由本地注册表自动补全（保存时触发）。
class ProviderPresetScreen extends StatelessWidget {
  const ProviderPresetScreen({super.key});

  /// 弹出提供商可选的模型列表，选中后进入添加模型页面
  void _showModels(BuildContext context, _ProviderPreset provider) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(provider.name),
        message: Text(
          provider.baseUrl,
          style: TextStyle(
            fontSize: 12,
            color: context.textSecondaryColor,
          ),
        ),
        actions: [
          for (final model in provider.models)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                _openModelEdit(context, provider, model);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    model.displayName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    model.modelName,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondaryColor,
                    ),
                  ),
                ],
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
      ),
    );
  }

  /// 进入添加模型页面并预填提供商配置
  void _openModelEdit(
    BuildContext context,
    _ProviderPreset provider,
    ({String displayName, String modelName}) model,
  ) {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => ModelEditScreen(
          preset: ModelPreset(
            displayName: model.displayName,
            modelName: model.modelName,
            baseUrl: provider.baseUrl,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('快捷预设'),
      ),
      child: ListView(
        children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '选择提供商与模型后自动填入 API 地址，仅需补充 API Key。均兼容 OpenAI 接口。',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: context.textSecondaryColor,
              ),
            ),
          ),
          const SizedBox(height: 8),
          CupertinoListSection.insetGrouped(
            backgroundColor: context.scaffoldColor,
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            children: [
              for (final provider in _presets)
                CupertinoListTile(
                  leading: Icon(
                    CupertinoIcons.cube,
                    color: context.accentColor,
                  ),
                  title: Text(
                    provider.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        provider.baseUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondaryColor,
                        ),
                      ),
                      Text(
                        provider.description,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondaryColor,
                        ),
                      ),
                    ],
                  ),
                  trailing: Icon(
                    CupertinoIcons.chevron_right,
                    size: 14,
                    color: context.textSecondaryColor,
                  ),
                  onTap: () => _showModels(context, provider),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '未列出的服务商可返回「添加模型」手动填写；请求地址以官方最新文档为准。',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: context.textSecondaryColor,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
