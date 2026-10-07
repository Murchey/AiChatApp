import 'package:flutter/cupertino.dart';
import '../config/theme.dart';
import '../models/provider_preset.dart';
import '../widgets/settings/settings_ui.dart';
import 'provider_config_screen.dart';

/// 快捷预设二级页面：常用 OpenAI 兼容厂商列表
///
/// 点击厂商进入「厂商设置」页：填写请求地址与 API Key，
/// 勾选本地推荐模型（或在线检测）后批量添加。
class ProviderPresetScreen extends StatefulWidget {
  const ProviderPresetScreen({super.key});

  @override
  State<ProviderPresetScreen> createState() => _ProviderPresetScreenState();
}

class _ProviderPresetScreenState extends State<ProviderPresetScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: settingsNavigationBar(context, '快捷预设'),
      backgroundColor: context.scaffoldColor,
      child: ListView(
        key: const PageStorageKey<String>('provider-preset-list'),
        controller: _scrollController,
        padding: settingsPageContentPadding(context),
        children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '点击厂商进入设置页：填写请求地址与 API Key，勾选模型后批量添加。均兼容 OpenAI 接口。',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: context.textSecondaryColor,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SettingsSection(
            title: '服务商',
            children: [
              for (final provider in providerPresets)
                SettingsRow(
                  icon: CupertinoIcons.cube,
                  title: Text(provider.name),
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
                  showChevron: true,
                  onTap: () => Navigator.push(
                    context,
                    CupertinoPageRoute(
                      builder: (_) => ProviderConfigScreen(preset: provider),
                    ),
                  ),
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
