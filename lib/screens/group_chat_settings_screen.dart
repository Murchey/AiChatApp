import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/chat_settings_provider.dart';
import '../providers/group_chat_provider.dart';
import 'chat_settings_screen.dart' show kMaxContextCount, kUnlimitedSliderValue;

/// 群聊详情 / 底部加号面板 → 【上下文设置】二级页：
/// 每群可单独设置「携带上下文条数」，默认跟随全局聊天设置；
/// UI 复用私聊聊天设置中的滑条 + 精确输入交互。
class GroupChatSettingsScreen extends StatefulWidget {
  final String groupId;

  const GroupChatSettingsScreen({super.key, required this.groupId});

  @override
  State<GroupChatSettingsScreen> createState() => _GroupChatSettingsScreenState();
}

class _GroupChatSettingsScreenState extends State<GroupChatSettingsScreen> {
  /// 弹出上下文条数编辑弹窗（点击数字小窗触发）
  void _showEditContextCount(
    BuildContext context,
    GroupChatProvider provider,
    int current,
  ) {
    final controller = TextEditingController(
      text: current == 0 ? '' : '$current',
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
              '输入 1~$kMaxContextCount 条，输入 0 表示无限制',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: context.textSecondaryColor),
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
                provider.setContextCount(
                  widget.groupId,
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
    final groupProvider = context.watch<GroupChatProvider>();
    final group = groupProvider.getGroupById(widget.groupId);
    if (group == null) {
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('上下文设置')),
        child: Center(
          child: Text(
            '群聊不存在或已删除',
            style: TextStyle(color: context.textSecondaryColor),
          ),
        ),
      );
    }

    final chatSettings = context.watch<ChatSettingsProvider>();
    final groupCount = group.contextCount;
    final followingGlobal = groupCount == null;
    // 当前生效条数：跟随全局时取全局值
    final effective = followingGlobal ? chatSettings.contextCount : groupCount;
    final sliderValue = effective == 0
        ? kUnlimitedSliderValue.toDouble()
        : effective.clamp(1, kMaxContextCount).toDouble();

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('上下文设置')),
      child: ListView(
        children: [
          const SizedBox(height: 12),
          CupertinoListSection.insetGrouped(
            backgroundColor: context.scaffoldColor,
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            header: const Text('上下文'),
            children: [
              CupertinoListTile(
                title: const Text('跟随全局聊天设置'),
                subtitle: Text(
                  followingGlobal
                      ? '使用「聊天设置」中的上下文条数（当前 ${effective == 0 ? '无限制' : '$effective 条'}）'
                      : '已为此群单独设置上下文条数',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondaryColor,
                  ),
                ),
                trailing: CupertinoSwitch(
                  value: followingGlobal,
                  onChanged: (v) {
                    groupProvider.setContextCount(
                      widget.groupId,
                      v
                          ? null // 恢复跟随全局
                          : (chatSettings.contextCount == 0
                              ? 0
                              : chatSettings.contextCount), // 从当前全局值开始
                    );
                  },
                ),
              ),
              if (!followingGlobal) ...[
                Container(height: 0.5, color: context.separatorColor),
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
                          GestureDetector(
                            onTap: () =>
                                _showEditContextCount(context, groupProvider, effective),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    context.accentColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                effective == 0 ? '无限制' : '$effective 条',
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
                            groupProvider.setContextCount(
                              widget.groupId,
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
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '发送消息后，群内角色回复时会携带最近 N 条对话作为上下文；'
              '0 条 = 无限制（携带全部历史，适合较短对话，长对话建议设置条数）。\n'
              '取消「跟随全局」后即可单独调整本群的上下文条数。',
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
