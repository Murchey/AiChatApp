import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/ui_spec.dart';
import '../providers/api_provider.dart';
import '../providers/chat_settings_provider.dart';
import '../services/tts_service.dart';
import '../widgets/settings/settings_ui.dart';
import 'chat_settings_screen.dart';
import 'model_edit_screen.dart';
import 'provider_preset_screen.dart';

/// API 设置页面 - 管理模型（API 地址、模型名称、展示名称、API Key）
class ApiSettingsScreen extends StatelessWidget {
  const ApiSettingsScreen({super.key});

  /// 跳转到添加 / 编辑模型的二级页面
  void _openModelEdit(BuildContext context, {ApiModel? model}) {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => ModelEditScreen(model: model),
      ),
    );
  }

  /// 压缩会话模型显示文案
  String _compressionModelLabel(ApiProvider api) {
    if (api.compressionModelId == null) return '跟随聊天模型';
    final model = api.getModelById(api.compressionModelId);
    if (model == null) return '跟随聊天模型';
    return '${model.displayName}（${model.modelName}）';
  }

  /// 朋友圈互动模型显示文案
  String _momentModelLabel(ApiProvider api) {
    if (api.momentModelId == null) return '未设置';
    final model = api.getModelById(api.momentModelId);
    if (model == null) return '未设置';
    return '${model.displayName}（${model.modelName}）';
  }

  String _ttsModelLabel(ApiProvider api) {
    if (api.ttsModelId == null) return '未设置';
    final model = api.getModelById(api.ttsModelId);
    if (model == null) return '未设置';
    return '${model.displayName}（${model.modelName}）';
  }

  void _showTtsModelPicker(BuildContext context) {
    final api = context.read<ApiProvider>();
    final items = <({String? id, String label})>[
      (id: null, label: '未设置'),
      for (final model in api.models)
        if (TtsService.isSupportedModel(model))
          (id: model.id, label: model.displayName),
    ];
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.6,
          ),
          margin: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
          decoration: BoxDecoration(
            color: context.scaffoldColor,
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  children: [
                    Text(
                      '选择语音模型',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimaryColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '当前支持：OpenAI、MiMo、MiniMax、Qwen 非流式 TTS',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
              Container(height: 0.5, color: context.separatorColor),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final item in items)
                      CupertinoListTile(
                        onTap: () {
                          api.setTtsModel(item.id);
                          Navigator.pop(ctx);
                        },
                        title: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            color: context.textPrimaryColor,
                          ),
                        ),
                        trailing: item.id == api.ttsModelId
                            ? Icon(
                                CupertinoIcons.check_mark,
                                color: context.accentColor,
                              )
                            : null,
                      ),
                  ],
                ),
              ),
              Container(height: 0.5, color: context.separatorColor),
              CupertinoButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  '取消',
                  style: TextStyle(
                    fontSize: 16,
                    color: context.textSecondaryColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 弹出朋友圈互动模型的选取（未设置 / 已配置模型）
  ///
  /// 使用可滚动选项列表：用户添加大量模型时也能正常显示全部选项
  void _showMomentModelPicker(BuildContext context) {
    final api = context.read<ApiProvider>();
    final items = <({String? id, String label})>[
      (id: null, label: '未设置'),
      for (final m in api.models) (id: m.id, label: m.displayName),
    ];
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.6,
          ),
          margin: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
          decoration: BoxDecoration(
            color: context.scaffoldColor,
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  children: [
                    Text(
                      '读取朋友圈的模型',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimaryColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '发布朋友圈后由该模型决定角色是否点赞/评论',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
              Container(height: 0.5, color: context.separatorColor),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final item in items)
                      CupertinoListTile(
                        onTap: () {
                          api.setMomentModel(item.id);
                          Navigator.pop(ctx);
                        },
                        title: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            color: context.textPrimaryColor,
                          ),
                        ),
                        trailing: item.id == api.momentModelId
                            ? Icon(
                                CupertinoIcons.check_mark,
                                color: context.accentColor,
                              )
                            : null,
                      ),
                  ],
                ),
              ),
              Container(height: 0.5, color: context.separatorColor),
              CupertinoButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  '取消',
                  style: TextStyle(
                    fontSize: 16,
                    color: context.textSecondaryColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 弹出压缩会话模型的选取（跟随聊天模型 / 已配置模型）
  ///
  /// 使用可滚动选项列表：用户添加大量模型时也能正常显示全部选项
  void _showCompressionModelPicker(BuildContext context) {
    final api = context.read<ApiProvider>();
    final items = <({String? id, String label})>[
      (id: null, label: '跟随聊天模型'),
      for (final m in api.models) (id: m.id, label: m.displayName),
    ];
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.6,
          ),
          margin: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
          decoration: BoxDecoration(
            color: context.scaffoldColor,
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  children: [
                    Text(
                      '压缩会话使用的模型',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimaryColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '用于上下文达到 70% 时压缩历史消息',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
              Container(height: 0.5, color: context.separatorColor),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final item in items)
                      CupertinoListTile(
                        onTap: () {
                          api.setCompressionModel(item.id);
                          Navigator.pop(ctx);
                        },
                        title: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            color: context.textPrimaryColor,
                          ),
                        ),
                        trailing: item.id == api.compressionModelId
                            ? Icon(
                                CupertinoIcons.check_mark,
                                color: context.accentColor,
                              )
                            : null,
                      ),
                  ],
                ),
              ),
              Container(height: 0.5, color: context.separatorColor),
              CupertinoButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  '取消',
                  style: TextStyle(
                    fontSize: 16,
                    color: context.textSecondaryColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, ApiModel model) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('删除模型'),
        content: Text('确定要删除 "${model.displayName}" 吗？'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () async {
              await context.read<ApiProvider>().deleteModel(model.id);
              if (!ctx.mounted) return;
              // 删到只剩一个模型且当前聊天模型已失效时，自动切到剩余模型
              final api = context.read<ApiProvider>();
              final settings = context.read<ChatSettingsProvider>();
              await settings.ensureSoleModelSelected(
                  api.models.map((m) => m.id).toList());
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final api = context.watch<ApiProvider>();

    return CupertinoPageScaffold(
      navigationBar: settingsNavigationBar(context, 'API 设置'),
      backgroundColor: context.scaffoldColor,
      child: ListView(
        padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top + UiSpec.settingsPageTop,
          bottom: UiSpec.floatingContentBottomInset,
        ),
        children: [
          SettingsSection(
            title: '快捷预设',
            children: [
              SettingsRow(
                icon: CupertinoIcons.speedometer,
                title: const Text('从常用提供商快速添加'),
                subtitle: const Text(
                    'OpenAI、小米 MiMo、DeepSeek、Grok、Kimi、阿里云百炼、硅基流动、MiniMax 等'),
                showChevron: true,
                onTap: () => Navigator.push(
                    context,
                    CupertinoPageRoute(
                        builder: (_) => const ProviderPresetScreen())),
              ),
            ],
          ),
          SettingsSection(
            title: '可用模型 (${api.models.length})',
            children: [
              for (final model in api.models)
                SettingsRow(
                  icon: CupertinoIcons.gear,
                  title: Text(model.displayName),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('模型: ${model.modelName}'),
                      if (model.baseUrl.isNotEmpty)
                        Text(model.baseUrl,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                  trailing: CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(32, 32),
                    onPressed: () => _confirmDelete(context, model),
                    child: const Icon(CupertinoIcons.delete,
                        size: 18, color: CupertinoColors.systemRed),
                  ),
                  onTap: () => _openModelEdit(context, model: model),
                ),
              SettingsRow(
                icon: CupertinoIcons.plus,
                iconColor: context.accentColor,
                title: Text('添加模型',
                    style: TextStyle(
                        color: context.accentColor,
                        fontWeight: FontWeight.w600)),
                onTap: () => _openModelEdit(context),
              ),
            ],
          ),
          SettingsSection(
            title: '会话压缩',
            children: [
              SettingsRow(
                  icon: CupertinoIcons.archivebox,
                  title: const Text('压缩会话使用的模型'),
                  subtitle: Text(_compressionModelLabel(api)),
                  showChevron: true,
                  onTap: () => _showCompressionModelPicker(context)),
            ],
          ),
          SettingsSection(
            title: '朋友圈互动',
            children: [
              SettingsRow(
                  icon: CupertinoIcons.bell,
                  title: const Text('读取朋友圈的模型'),
                  subtitle: Text(_momentModelLabel(api)),
                  showChevron: true,
                  onTap: () => _showMomentModelPicker(context)),
            ],
          ),
          SettingsSection(
            title: '语音合成',
            children: [
              SettingsRow(
                  icon: CupertinoIcons.waveform,
                  title: const Text('语音模型'),
                  subtitle: Text(_ttsModelLabel(api)),
                  showChevron: true,
                  onTap: () => _showTtsModelPicker(context)),
            ],
          ),
          SettingsSection(
            title: '聊天设置',
            children: [
              SettingsRow(
                icon: CupertinoIcons.settings,
                title: const Text('上下文、压缩与使用的模型'),
                subtitle: const Text('设置携带上下文条数、自动压缩策略及当前使用的模型'),
                showChevron: true,
                onTap: () => Navigator.push(
                    context,
                    CupertinoPageRoute(
                        builder: (_) => const ChatSettingsScreen())),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '模型添加后可在聊天设置中选择使用。每个模型可独立配置 API 地址、模型名称和 API Key。',
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
