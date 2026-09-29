import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../models/visibility_group.dart';
import '../../providers/auto_moment_provider.dart';
import '../../providers/character_provider.dart';
import '../../providers/proactive_greeting_provider.dart';
import '../../screens/moment_visibility_screen.dart';
import 'auto_moment_pickers.dart';

  Widget buildAutoMomentSection(BuildContext context, String characterId, {required void Function() onChanged}) {
    return Consumer<AutoMomentProvider>(
      builder: (context, autoProvider, _) {
        final config = autoProvider.configFor(characterId);
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: context.listBgColor,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              CupertinoListTile(
                leading: Icon(
                  CupertinoIcons.camera,
                  color: context.textPrimaryColor,
                ),
                title: Text(
                  '自动发朋友圈',
                  style: TextStyle(color: context.textPrimaryColor),
                ),
                subtitle: Text(
                  config.enabled
                      ? describeAutoMomentConfig(config)
                      : '让角色定时自动发布朋友圈，其他角色会像真人一样点赞评论',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: context.textSecondaryColor,
                  ),
                ),
                trailing: CupertinoSwitch(
                  value: config.enabled,
                  onChanged: (v) => autoProvider.setEnabled(characterId, v),
                ),
              ),
              if (config.enabled) ...[
                Container(
                  height: 0.5,
                  margin: const EdgeInsets.only(left: 16),
                  color: context.separatorColor,
                ),
                AutoMomentPickerSection(
                  key: ValueKey('auto_moment_picker_$characterId'),
                  initialPeriodHours: config.periodHours,
                  initialCount: config.count,
                  onPeriodChanged: (h) =>
                      autoProvider.setPeriod(characterId, h),
                  onCountChanged: (c) => autoProvider.setCount(characterId, c),
                ),
                Container(
                  height: 0.5,
                  margin: const EdgeInsets.only(left: 16),
                  color: context.separatorColor,
                ),
                CupertinoListTile(
                  leading: Icon(
                    CupertinoIcons.person_2,
                    color: context.textPrimaryColor,
                  ),
                  title: Text(
                    '谁可以互动',
                    style: TextStyle(color: context.textPrimaryColor),
                  ),
                  subtitle: Text(
                    visibilityLabel(context, config.visibility),
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
                  onTap: () => openAutoMomentVisibility(
                    context,
                    characterId: characterId,
                    autoProvider: autoProvider,
                    currentId: config.visibility,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget buildProactiveGreetingSection(BuildContext context, String characterId) {
    return Consumer<ProactiveGreetingProvider>(
      builder: (context, greetingProvider, _) {
        final config = greetingProvider.configFor(characterId);
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: context.listBgColor,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              CupertinoListTile(
                leading: Icon(
                  CupertinoIcons.text_bubble,
                  color: context.textPrimaryColor,
                ),
                title: Text(
                  '主动问候',
                  style: TextStyle(color: context.textPrimaryColor),
                ),
                subtitle: Text(
                  config.enabled
                      ? describeGreetingConfig(config)
                      : '用户长时间未聊天时，角色会主动发消息问候',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: context.textSecondaryColor,
                  ),
                ),
                trailing: CupertinoSwitch(
                  value: config.enabled,
                  onChanged: (v) =>
                      greetingProvider.setEnabled(characterId, v),
                ),
              ),
              if (config.enabled) ...[
                Container(
                  height: 0.5,
                  margin: const EdgeInsets.only(left: 16),
                  color: context.separatorColor,
                ),
                ProactiveGreetingPickerSection(
                  key: ValueKey('proactive_greeting_picker_$characterId'),
                  initialIdleHours: config.idleHours,
                  onChanged: (h) =>
                      greetingProvider.setIdleHours(characterId, h),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String describeGreetingConfig(ProactiveGreetingConfig config) {
    final idx = ProactiveGreetingProvider.idleOptions.indexOf(config.idleHours);
    final label = ProactiveGreetingProvider.idleLabels[idx < 0 ? 3 : idx];
    return '$label后，角色会主动发消息问候你';
  }

  String describeAutoMomentConfig(AutoMomentConfig config) {
    final idx = AutoMomentProvider.periodOptions.indexOf(config.periodHours);
    final label = AutoMomentProvider.periodLabels[idx < 0 ? 3 : idx];
    return '每 $label 发 ${config.count} 条，其他角色会像真人一样点赞评论';
  }

  String visibilityLabel(BuildContext context, String visibility) {
    if (visibility == VisibilityScope.onlyMe) return '仅自己可见（无人互动）';
    if (visibility == VisibilityScope.all) return '全部角色可见';
    final groups = context.read<CharacterProvider>().visibilityGroups;
    for (final g in groups) {
      if (g.id == visibility) {
        // 该角色即便在分组内，互动阶段也已排除发布者本人，不会自己点赞评论
        return '分组「${g.name}」';
      }
    }
    return '全部角色可见';
  }


/// 打开可见范围选择页
Future<void> openAutoMomentVisibility(
  BuildContext context, {
  required String characterId,
  required AutoMomentProvider autoProvider,
  required String currentId,
}) async {
  final selected = await Navigator.push<String>(
    context,
    CupertinoPageRoute(
      builder: (_) => MomentVisibilityScreen(selectedId: currentId),
    ),
  );
  if (selected == null) return;
  await autoProvider.setVisibility(characterId, selected);
}
