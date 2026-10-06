import 'package:flutter/cupertino.dart';

import '../../config/theme.dart';
import '../../config/ui_spec.dart';

/// Shared navigation chrome for settings pages. It keeps the normal
/// Navigator.pop/back gesture semantics while using a quieter, centered
/// Obsidian-style title treatment.
CupertinoNavigationBar settingsNavigationBar(
  BuildContext context,
  String title, {
  String? previousPageTitle,
  Widget? trailing,
}) {
  return CupertinoNavigationBar(
    automaticallyImplyLeading: false,
    border: Border(
      bottom: BorderSide(
        color: context.settingsDividerColor,
        width: 0.5,
      ),
    ),
    leading: CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(34, 34),
      onPressed: () => Navigator.of(context).maybePop(),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: context.fieldBgColor,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          CupertinoIcons.chevron_left,
          size: 18,
          color: context.textSecondaryColor,
        ),
      ),
    ),
    middle: Text(
      title,
      style: TextStyle(
        fontSize: UiSpec.fontTitle,
        fontWeight: FontWeight.w600,
        color: context.textPrimaryColor,
      ),
    ),
    previousPageTitle: previousPageTitle,
    trailing: trailing,
    backgroundColor: context.navBarColor.withValues(alpha: 0.96),
  );
}

/// A grouped settings panel with a stable section header and low-contrast
/// separators. The children are intentionally generic so switches, sliders,
/// previews, and color pickers can keep their existing behavior.
class SettingsSection extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  final Widget? footer;

  const SettingsSection({
    super.key,
    this.title,
    required this.children,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final content = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        content.add(
          Container(
            height: 0.5,
            margin: const EdgeInsets.only(
              left: UiSpec.settingsRowHorizontal + UiSpec.settingsIconWidth,
              right: UiSpec.settingsRowHorizontal,
            ),
            color: context.settingsDividerColor,
          ),
        );
      }
      content.add(children[i]);
    }

    return Padding(
      padding: const EdgeInsets.only(
        left: UiSpec.pageH + UiSpec.settingsSectionHorizontal,
        right: UiSpec.pageH + UiSpec.settingsSectionHorizontal,
        bottom: UiSpec.settingsSectionGap,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 9),
              child: Text(
                title!,
                style: TextStyle(
                  fontSize: UiSpec.settingsSectionTitle,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.15,
                  color: context.textSecondaryColor,
                ),
              ),
            ),
          ],
          DecoratedBox(
            decoration: BoxDecoration(
              color: context.settingsSurfaceColor,
              borderRadius: BorderRadius.circular(
                UiSpec.settingsSectionRadius,
              ),
              border: Border.all(
                color: context.settingsOutlineColor.withValues(alpha: 0.7),
                width: 0.6,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                UiSpec.settingsSectionRadius,
              ),
              child: Column(children: content),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 8, top: 8),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  fontSize: UiSpec.settingsRowSubtitle,
                  height: 1.35,
                  color: context.textSecondaryColor,
                ),
                child: footer!,
              ),
            ),
        ],
      ),
    );
  }
}

/// A settings row with aligned leading icon, title/subtitle hierarchy, and a
/// neutral chevron. Interactive controls remain supplied by the caller.
class SettingsRow extends StatelessWidget {
  final Widget? leading;
  final IconData? icon;
  final Color? iconColor;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;
  final bool enabled;

  const SettingsRow({
    super.key,
    this.leading,
    this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.showChevron = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: UiSpec.settingsRowMinHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: UiSpec.settingsRowHorizontal,
          vertical: UiSpec.settingsRowVertical,
        ),
        child: Row(
          children: [
            SizedBox(
              width: UiSpec.settingsIconWidth,
              child: leading ??
                  (icon == null
                      ? null
                      : Icon(
                          icon,
                          size: 22,
                          color: iconColor ?? context.textSecondaryColor,
                        )),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  fontSize: UiSpec.settingsRowTitle,
                  color: enabled
                      ? context.textPrimaryColor
                      : context.textSecondaryColor,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    title,
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      DefaultTextStyle.merge(
                        style: TextStyle(
                          fontSize: UiSpec.settingsRowSubtitle,
                          height: 1.35,
                          color: context.textSecondaryColor,
                        ),
                        child: subtitle!,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 10),
              Flexible(child: trailing!),
            ],
            if (showChevron) ...[
              const SizedBox(width: 8),
              Icon(
                CupertinoIcons.chevron_right,
                size: 17,
                color: context.textSecondaryColor.withValues(alpha: 0.72),
              ),
            ],
          ],
        ),
      ),
    );

    if (onTap == null || !enabled) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: row,
    );
  }
}

Widget settingsValueText(BuildContext context, String value) {
  return Text(
    value,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: UiSpec.fontBodySm,
      color: context.textSecondaryColor,
    ),
  );
}
