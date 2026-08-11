import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/api_provider.dart';
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
      navigationBar: const CupertinoNavigationBar(
        middle: Text('API 设置'),
      ),
      child: ListView(
        children: [
          const SizedBox(height: 12),
          // 快捷预设：常用 OpenAI 兼容提供商快速添加
          CupertinoListSection.insetGrouped(
            backgroundColor: context.scaffoldColor,
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            header: const Text('快捷预设'),
            children: [
              CupertinoListTile(
                leading: Icon(
                  CupertinoIcons.speedometer,
                  color: context.accentColor,
                ),
                title: Text(
                  '从常用提供商快速添加',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: context.textPrimaryColor,
                  ),
                ),
                subtitle: Text(
                  'OpenAI、小米 MiMo、DeepSeek、Grok、Kimi、阿里云百炼、硅基流动、MiniMax 等',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondaryColor,
                  ),
                ),
                trailing: Icon(
                  CupertinoIcons.chevron_right,
                  size: 16,
                  color: context.textSecondaryColor,
                ),
                onTap: () => Navigator.push(
                  context,
                  CupertinoPageRoute(
                    builder: (_) => const ProviderPresetScreen(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          CupertinoListSection.insetGrouped(
            backgroundColor: context.scaffoldColor,
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            header: Text('可用模型 (${api.models.length})'),
            children: [
              for (final model in api.models)
                CupertinoListTile(
                  leading: Icon(
                    CupertinoIcons.gear,
                    color: context.accentColor,
                  ),
                  title: Text(
                    model.displayName,
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
                        '模型: ${model.modelName}',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondaryColor,
                        ),
                      ),
                      if (model.baseUrl.isNotEmpty)
                        Text(
                          model.baseUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondaryColor,
                          ),
                        ),
                    ],
                  ),
                  trailing: CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: const Icon(
                      CupertinoIcons.delete,
                      size: 18,
                      color: CupertinoColors.systemRed,
                    ),
                    onPressed: () => _confirmDelete(context, model),
                  ),
                  onTap: () => _openModelEdit(context, model: model),
                ),
              CupertinoListTile(
                leading: Icon(
                  CupertinoIcons.plus_circle_fill,
                  color: context.accentColor,
                ),
                title: Text(
                  '添加模型',
                  style: TextStyle(
                    color: context.accentColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () => _openModelEdit(context),
              ),
            ],
          ),
          // 会话压缩专用模型
          CupertinoListSection.insetGrouped(
            backgroundColor: context.scaffoldColor,
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            header: const Text('会话压缩'),
            children: [
              CupertinoListTile(
                leading: Icon(
                  CupertinoIcons.archivebox,
                  color: context.accentColor,
                ),
                title: const Text('压缩会话使用的模型'),
                subtitle: Text(
                  _compressionModelLabel(api),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondaryColor,
                  ),
                ),
                trailing: Icon(
                  CupertinoIcons.chevron_right,
                  size: 16,
                  color: context.textSecondaryColor,
                ),
                onTap: () => _showCompressionModelPicker(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
