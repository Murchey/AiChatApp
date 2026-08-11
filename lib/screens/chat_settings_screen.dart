import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/api_provider.dart';
import '../providers/chat_settings_provider.dart';

/// 聊天设置页面 - 上下文条数、使用的模型
class ChatSettingsScreen extends StatelessWidget {
  const ChatSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<ChatSettingsProvider>();
    final api = context.watch<ApiProvider>();

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('聊天设置'),
      ),
      child: ListView(
        children: [
          const SizedBox(height: 12),
          // 上下文条数
          CupertinoListSection.insetGrouped(
            backgroundColor: context.scaffoldColor,
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            header: const Text('上下文'),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '携带上下文条数',
                          style: TextStyle(
                            fontSize: 16,
                            color: context.textPrimaryColor,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: context.accentColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${settings.contextCount} 条',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: context.accentColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    CupertinoSlider(
                      value: settings.contextCount.toDouble().clamp(1, 50),
                      min: 1,
                      max: 50,
                      divisions: 49,
                      activeColor: context.accentColor,
                      onChanged: (value) {
                        settings.setContextCount(value.round());
                      },
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '1',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.textSecondaryColor,
                          ),
                        ),
                        Text(
                          '50',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.textSecondaryColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '发送消息时携带最近的对话记录作为上下文',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // 使用的模型
          CupertinoListSection.insetGrouped(
            backgroundColor: context.scaffoldColor,
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            header: const Text('使用的模型'),
            children: [
              if (api.models.isEmpty)
                CupertinoListTile(
                  title: Text(
                    '暂无可用模型，请先到 API 设置中添加',
                    style: TextStyle(
                      fontSize: 14,
                      color: context.textSecondaryColor,
                    ),
                  ),
                )
              else
                for (final model in api.models)
                  CupertinoListTile(
                    leading: Icon(
                      model.id == settings.selectedModelId
                          ? CupertinoIcons.check_mark_circled_solid
                          : CupertinoIcons.circle,
                      color: model.id == settings.selectedModelId
                          ? context.accentColor
                          : context.textSecondaryColor,
                    ),
                    title: Text(
                      model.displayName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: context.textPrimaryColor,
                      ),
                    ),
                    subtitle: Text(
                      model.modelName,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondaryColor,
                      ),
                    ),
                    onTap: () {
                      settings.setSelectedModel(model.id);
                    },
                  ),
            ],
          ),
          if (api.models.isNotEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '添加模型后，可在聊天输入框的加号面板中使用【功能检测】测试该模型是否支持图片发送，检测通过后【相册】【拍照】才可点击。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: context.textSecondaryColor,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
