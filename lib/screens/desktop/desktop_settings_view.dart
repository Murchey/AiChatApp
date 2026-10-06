import 'package:flutter/cupertino.dart';

import '../api_settings_screen.dart';
import '../settings_screen.dart';
import 'desktop_theme.dart';

/// 桌面设置容器：保留手机端完整设置列表，同时提供宽屏标题、留白和卡片层级。
/// 设置项仍由 [SettingsScreen] 维护，新增手机设置时桌面端会自动可见。
class DesktopSettingsView extends StatelessWidget {
  const DesktopSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return ColoredBox(
      color: p.shellBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(34, 28, 34, 18),
            child: Row(
              children: [
                Icon(CupertinoIcons.gear_solid,
                    color: p.textSecondary, size: 24),
                const SizedBox(width: 10),
                Text(
                  '设置',
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '账户、聊天、备份与外观',
                  style: TextStyle(color: p.textSecondary, fontSize: 13),
                ),
                const Spacer(),
                CupertinoButton(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  onPressed: () => Navigator.of(context).push(
                    CupertinoPageRoute(
                      builder: (_) => const ApiSettingsScreen(),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.slider_horizontal_3,
                          size: 17, color: p.accent),
                      const SizedBox(width: 6),
                      Text(
                        'API 设置',
                        style: TextStyle(
                          color: p.accent,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: p.panelBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: p.border),
                  ),
                  child: const ClipRRect(
                    borderRadius: BorderRadius.all(Radius.circular(18)),
                    child: SettingsScreen(),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
