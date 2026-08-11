import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/api_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/chat_settings_provider.dart';

/// 上下文条数上限（滑条最右端为【无限制】）
const int kMaxContextCount = 999;
/// 滑条最大值：kMaxContextCount 时为有限条数，此值表示【无限制】
const int kUnlimitedSliderValue = kMaxContextCount + 1;

/// 聊天设置页面 - 上下文条数、自动压缩、使用的模型
class ChatSettingsScreen extends StatelessWidget {
  const ChatSettingsScreen({super.key, this.conversationId});

  /// 当前会话 id：用于在页面顶部展示该会话的上下文使用情况
  final String? conversationId;

  /// 当前会话上下文使用情况：已用 token / 模型上下文长度 / 进度与压缩阈值标记
  Widget _buildContextUsageSection(
    BuildContext context,
    ChatSettingsProvider settings,
    ApiProvider api,
    ChatProvider chat,
  ) {
    final tokens = chat.getContextTokens(conversationId!);
    final model = api.getModelById(settings.selectedModelId);
    final contextLength = model?.contextLength ?? 0;
    final usage = contextLength > 0 ? (tokens / contextLength) : 0.0;
    final threshold = settings.compressThreshold;
    final overThreshold = contextLength > 0 && usage >= threshold;
    final fmt = NumberFormat.decimalPattern();

    return CupertinoListSection.insetGrouped(
      backgroundColor: context.scaffoldColor,
      decoration: BoxDecoration(
        color: context.listBgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      header: const Text('上下文使用情况'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '当前会话',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  Text(
                    contextLength > 0
                        ? '${(usage * 100).clamp(0, 100).round()}%'
                        : '未统计',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: overThreshold
                          ? CupertinoColors.systemOrange
                          : context.accentColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // 进度条 + 压缩阈值标记
              LayoutBuilder(
                builder: (ctx, constraints) {
                  final width = constraints.maxWidth;
                  return SizedBox(
                    height: 6,
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: SizedBox(
                            width: width,
                            child: ColoredBox(
                              color: context.isDark
                                  ? CupertinoColors.white.withValues(alpha: 0.15)
                                  : CupertinoColors.black.withValues(alpha: 0.08),
                            ),
                          ),
                        ),
                        if (contextLength > 0 && usage > 0)
                          FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: usage.clamp(0.0, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                color: overThreshold
                                    ? CupertinoColors.systemOrange
                                    : context.accentColor,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        // 压缩阈值刻度线
                        if (settings.enableCompression && contextLength > 0)
                          Positioned(
                            left: (width * threshold - 1).clamp(0.0, width - 2),
                            top: -2,
                            child: Container(
                              width: 2,
                              height: 10,
                              decoration: BoxDecoration(
                                color: overThreshold
                                    ? CupertinoColors.systemOrange
                                    : context.textSecondaryColor,
                                borderRadius: BorderRadius.circular(1),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              Text(
                contextLength > 0
                    ? '已使用 ${fmt.format(tokens)} / ${fmt.format(contextLength)} token'
                    : '未选择模型或模型未配置上下文长度，无法统计',
                style: TextStyle(
                  fontSize: 12,
                  color: context.textSecondaryColor,
                ),
              ),
              if (overThreshold && settings.enableCompression) ...[
                const SizedBox(height: 4),
                Text(
                  '已达压缩阈值（${(threshold * 100).round()}%），下次发送将自动压缩更早的历史消息',
                  style: const TextStyle(
                    fontSize: 12,
                    color: CupertinoColors.systemOrange,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 弹出上下文条数编辑弹窗（点击显示小窗触发）
  void _showEditContextCount(BuildContext context, ChatSettingsProvider settings) {
    final controller = TextEditingController(
      text: settings.isUnlimitedContext ? '' : '${settings.contextCount}',
    );
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('设置上下文条数'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 4),
            Text(
              '输入 1~$kMaxContextCount 条，输入 0 表示无限制（将自动开启压缩会话）',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: context.textSecondaryColor,
              ),
            ),
            const SizedBox(height: 12),
            CupertinoTextField(
              controller: controller,
              placeholder: '如 30',
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              final n = int.tryParse(controller.text.trim());
              if (n != null) {
                settings.setContextCount(
                  n <= 0 ? 0 : (n > kMaxContextCount ? kMaxContextCount : n),
                );
              }
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<ChatSettingsProvider>();
    final api = context.watch<ApiProvider>();
    final chat = context.watch<ChatProvider>();

    // 滑条取值：无限制时为滑条最大值，否则为条数
    final sliderValue = settings.isUnlimitedContext
        ? kUnlimitedSliderValue.toDouble()
        : settings.contextCount.clamp(1, kMaxContextCount).toDouble();

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('聊天设置'),
      ),
      child: ListView(
        children: [
          const SizedBox(height: 12),
          // 当前会话的上下文使用情况
          if (conversationId != null)
            _buildContextUsageSection(context, settings, api, chat),
          if (conversationId != null) const SizedBox(height: 12),
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
                        // 显示小窗：点击可精确输入条数
                        GestureDetector(
                          onTap: () => _showEditContextCount(context, settings),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: context.accentColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              settings.isUnlimitedContext ? '无限制' : '${settings.contextCount} 条',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: context.accentColor,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // 滑条占满整个区块宽度，最右端为【无限制】
                    SizedBox(
                      width: double.infinity,
                      child: CupertinoSlider(
                        value: sliderValue,
                        min: 1,
                        max: kUnlimitedSliderValue.toDouble(),
                        divisions: kUnlimitedSliderValue - 1,
                        activeColor: context.accentColor,
                        onChanged: (value) {
                          final rounded = value.round();
                          settings.setContextCount(
                            rounded >= kUnlimitedSliderValue ? 0 : rounded,
                          );
                        },
                      ),
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
                          '无限制',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.textSecondaryColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '发送消息时携带最近的对话记录作为上下文；点击上方数字可精确设置条数',
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
          // 压缩会话
          CupertinoListSection.insetGrouped(
            backgroundColor: context.scaffoldColor,
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            header: const Text('压缩会话'),
            children: [
              CupertinoListTile(
                title: const Text('自动压缩历史消息'),
                subtitle: Text(
                  settings.enableCompression
                      ? '根据所选模型上下文长度，达到 70% 时自动压缩更早的历史消息'
                      : '已关闭',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondaryColor,
                  ),
                ),
                trailing: CupertinoSwitch(
                  value: settings.enableCompression,
                  onChanged: (v) => settings.setEnableCompression(v),
                ),
              ),
              // 压缩触发阈值（可手动调整）
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '压缩触发阈值',
                          style: TextStyle(
                            fontSize: 16,
                            color: context.textPrimaryColor,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color:
                                context.accentColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${(settings.compressThreshold * 100).round()}%',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: context.accentColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      child: CupertinoSlider(
                        value: settings.compressThreshold,
                        min: 0.3,
                        max: 0.9,
                        divisions: 12,
                        activeColor: context.accentColor,
                        onChanged: (v) =>
                            settings.setCompressThreshold(v),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '30%',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.textSecondaryColor,
                          ),
                        ),
                        Text(
                          '90%',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.textSecondaryColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '上下文设为【无限制】时将自动开启压缩会话；压缩使用的模型可在「API 设置 → 会话压缩」中单独指定。',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: context.textSecondaryColor,
              ),
            ),
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
