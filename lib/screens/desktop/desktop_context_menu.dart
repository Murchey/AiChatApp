import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show Material, Colors, Theme, Brightness;

/// 桌面端右键菜单项
class DesktopMenuItem {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool destructive;
  final bool enabled;
  final bool dividerBefore;

  const DesktopMenuItem({
    required this.label,
    this.icon,
    this.onTap,
    this.destructive = false,
    this.enabled = true,
    this.dividerBefore = false,
  });
}

/// 在鼠标位置弹出桌面右键菜单（而非手机长按菜单）。
void showDesktopContextMenu(
  BuildContext context, {
  required Offset globalPos,
  required List<DesktopMenuItem> items,
}) {
  final overlay = Overlay.of(context);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final bg = isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF7F7F7);
  final border = isDark ? const Color(0xFF444444) : const Color(0xFFD0D0D0);
  final hover = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE8E8E8);
  final ink = isDark ? const Color(0xFFEDEDED) : const Color(0xFF191919);
  final muted = isDark ? const Color(0xFF8E8E8E) : const Color(0xFFB0B0B0);
  const danger = Color(0xFFFA5151);

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) {
      final size = MediaQuery.of(ctx).size;
      const menuWidth = 180.0;
      const itemHeight = 36.0;
      final menuHeight = items.fold<double>(
            0,
            (sum, e) => sum + (e.dividerBefore ? 9 : 0) + itemHeight,
          ) +
          8;
      final dx = globalPos.dx + menuWidth > size.width
          ? size.width - menuWidth - 8
          : globalPos.dx;
      final dy = globalPos.dy + menuHeight > size.height
          ? size.height - menuHeight - 8
          : globalPos.dy;
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => entry.remove(),
              onSecondaryTap: () => entry.remove(),
              behavior: HitTestBehavior.translucent,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: dx,
            top: dy,
            child: Material(
              color: bg,
              elevation: 8,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: menuWidth,
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final item in items) ...[
                      if (item.dividerBefore)
                        Container(
                          height: 1,
                          margin: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          color: border,
                        ),
                      _MenuTile(
                        item: item,
                        hoverColor: hover,
                        inkColor: ink,
                        mutedColor: muted,
                        dangerColor: danger,
                        onTap: () {
                          entry.remove();
                          item.onTap?.call();
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
  overlay.insert(entry);
}

class _MenuTile extends StatefulWidget {
  final DesktopMenuItem item;
  final VoidCallback onTap;
  final Color hoverColor;
  final Color inkColor;
  final Color mutedColor;
  final Color dangerColor;

  const _MenuTile({
    required this.item,
    required this.onTap,
    required this.hoverColor,
    required this.inkColor,
    required this.mutedColor,
    required this.dangerColor,
  });

  @override
  State<_MenuTile> createState() => _MenuTileState();
}

class _MenuTileState extends State<_MenuTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final color = !item.enabled
        ? widget.mutedColor
        : item.destructive
            ? widget.dangerColor
            : widget.inkColor;
    return MouseRegion(
      cursor: item.enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: item.enabled ? widget.onTap : null,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          color:
              _hover && item.enabled ? widget.hoverColor : Colors.transparent,
          child: Row(
            children: [
              if (item.icon != null) ...[
                Icon(item.icon, size: 15, color: color),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(fontSize: 13, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
