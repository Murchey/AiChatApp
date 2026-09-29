import 'package:flutter/cupertino.dart';

import '../../config/theme.dart';
import '../../config/ui_spec.dart';

/// 备份页共享 UI 构件
class BackupEmptyHint extends StatelessWidget {
  final String text;
  const BackupEmptyHint({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: UiSpec.fontCaption, color: context.textSecondaryColor),
      ),
    );
  }
}

class BackupSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const BackupSection({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: TextStyle(fontSize: UiSpec.fontCaption, color: context.textSecondaryColor),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: context.listBgColor,
            borderRadius: BorderRadius.circular(UiSpec.radiusCard),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }
}

class BackupActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool enabled;

  const BackupActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final muted = !enabled || onTap == null;
    return CupertinoListTile(
      leading: Icon(
        icon,
        color: muted ? context.textSecondaryColor : context.accentColor,
      ),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: UiSpec.fontCaption, color: context.textSecondaryColor),
      ),
      trailing: Icon(
        CupertinoIcons.chevron_right,
        size: 16,
        color: context.textSecondaryColor,
      ),
      onTap: muted ? null : onTap,
    );
  }
}

class BackupTileBody extends StatelessWidget {
  final String title;
  final String meta;
  final bool encrypted;
  final List<Widget> actions;

  const BackupTileBody({
    super.key,
    required this.title,
    required this.meta,
    required this.encrypted,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: UiSpec.listTilePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: UiSpec.fontBodySm,
                    color: context.textPrimaryColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (encrypted)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: context.accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '加密',
                    style: TextStyle(fontSize: 10, color: context.accentColor),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            meta,
            style: TextStyle(fontSize: UiSpec.fontCaption, color: context.textSecondaryColor),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ),
    );
  }
}

class BackupMiniButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool destructive;

  const BackupMiniButton({
    super.key,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        destructive ? CupertinoColors.destructiveRed : context.accentColor;
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      minimumSize: const Size(0, 32),
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(UiSpec.radiusButton),
      onPressed: onTap,
      child: Text(
        label,
        style: TextStyle(
          fontSize: UiSpec.fontCaption,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
