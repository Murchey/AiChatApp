import 'package:flutter/cupertino.dart';

import '../config/theme.dart';
import '../config/ui_spec.dart';
import '../providers/settings_provider.dart';
import '../widgets/settings/settings_ui.dart';
import 'moments_screen.dart';
import 'story_community_screen.dart';

class DiscoverScreen extends StatelessWidget {
  final HomeNavigationStyle navigationStyle;

  const DiscoverScreen({
    super.key,
    required this.navigationStyle,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          '发现',
          style: TextStyle(
            fontSize: UiSpec.fontTitle,
            fontWeight: FontWeight.w600,
            color: context.textPrimaryColor,
          ),
        ),
        backgroundColor: context.navBarColor.withValues(alpha: 0.96),
        border: Border(
            bottom:
                BorderSide(color: context.settingsDividerColor, width: 0.5)),
      ),
      backgroundColor: context.scaffoldColor,
      child: ListView(
        key: const PageStorageKey<String>('discover-page-list'),
        padding: settingsPageContentPadding(
          context,
          bottom: context.homeContentBottomInset +
              MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
            child: Text(
              '探索你的聊天世界',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: context.textPrimaryColor,
              ),
            ),
          ),
          SettingsSection(
            title: '发现',
            children: [
              SettingsRow(
                icon: CupertinoIcons.compass_fill,
                iconColor: context.accentColor,
                title: const Text('朋友圈'),
                subtitle: const Text('查看角色动态、评论和互动通知'),
                showChevron: true,
                onTap: () => Navigator.push(
                  context,
                  CupertinoPageRoute(
                    builder: (_) =>
                        MomentsScreen(navigationStyle: navigationStyle),
                  ),
                ),
              ),
              SettingsRow(
                icon: CupertinoIcons.book,
                iconColor: const Color(0xFF6C7FA8),
                title: const Text('故事线社区'),
                subtitle: const Text('浏览和下载文字故事设定，安装到角色记忆池'),
                showChevron: true,
                onTap: () => Navigator.push(
                  context,
                  CupertinoPageRoute(
                    builder: (_) => const StoryCommunityScreen(),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Text(
              '故事线内容只会作为独立记忆源加入你选择的角色，不会覆盖已有记忆。',
              style: TextStyle(
                fontSize: UiSpec.settingsRowSubtitle,
                height: 1.45,
                color: context.textSecondaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
