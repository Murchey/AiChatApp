import 'dart:io';
import 'package:flutter/cupertino.dart';
import '../config/theme.dart';
import '../services/app_theme_store.dart';

Widget themedNavigationIcon(BuildContext context, IconData icon,
    {double? size, Color? color, Key? key}) {
  final slots = {
    CupertinoIcons.bubble_left: ('chat', false),
    CupertinoIcons.bubble_left_fill: ('chat', true),
    CupertinoIcons.person_2: ('contacts', false),
    CupertinoIcons.person_2_fill: ('contacts', true),
    CupertinoIcons.compass: ('discover', false),
    CupertinoIcons.compass_fill: ('discover', true),
    CupertinoIcons.person_crop_circle: ('profile', false),
    CupertinoIcons.person_crop_circle_fill: ('profile', true),
  };
  return AnimatedBuilder(
      animation: AppThemeStore.instance,
      builder: (context, _) {
        final theme = AppThemeStore.instance.active;
        final slot = slots[icon];
        final pair = theme?.navigation[slot?.$1];
        final fallback = Icon(icon, size: size, color: color, key: key);
        if (pair == null || slot == null) return fallback;
        // Enlarge installed theme artwork too, without requiring a ZIP reimport.
        // The navigation slot constrains artwork when labels need more height.
        final imageSize = theme!.navigationSize(slot.$1, size ?? 24) * 1.1;
        return Image.file(
            File(theme.path(slot.$2 ? pair.$2.file : pair.$1.file)),
            key: key,
            width: imageSize,
            height: imageSize,
            fit: BoxFit.contain,
            cacheWidth: 144,
            errorBuilder: (context, error, stack) => fallback);
      });
}

/// Background painted behind a standard navigation bar, including its safe area.
class ThemeHeaderSurface extends StatelessWidget {
  final String slot;
  final Widget child;
  const ThemeHeaderSurface(
      {super.key, required this.slot, required this.child});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: AppThemeStore.instance,
      builder: (context, _) {
        final theme = AppThemeStore.instance.active;
        final image = theme?.headers[slot];
        if (image == null) return child;
        final page = child;
        if (page is! CupertinoPageScaffold || page.navigationBar == null) {
          return child;
        }
        // Paint in the navigation bar, above opaque scrolling list surfaces.
        // An image behind the entire scaffold is hidden by nonempty lists.
        return CupertinoPageScaffold(
          backgroundColor: page.backgroundColor == CupertinoColors.transparent
              ? context.scaffoldColor
              : page.backgroundColor,
          resizeToAvoidBottomInset: page.resizeToAvoidBottomInset,
          navigationBar: _ThemeImageNavigationBar(
              bar: page.navigationBar!, path: theme!.path(image.file)),
          child: page.child,
        );
      });
}

class _ThemeImageNavigationBar extends StatelessWidget
    implements ObstructingPreferredSizeWidget {
  static const _extraHeight = 16.0;
  final ObstructingPreferredSizeWidget bar;
  final String path;
  const _ThemeImageNavigationBar({required this.bar, required this.path});
  @override
  Size get preferredSize =>
      Size(bar.preferredSize.width, bar.preferredSize.height + _extraHeight);
  @override
  bool shouldFullyObstruct(BuildContext context) =>
      bar.shouldFullyObstruct(context);
  @override
  Widget build(BuildContext context) => Stack(children: [
        Positioned.fill(
            child: IgnorePointer(
                child: Stack(fit: StackFit.expand, children: [
          Image.file(File(path),
              key: const ValueKey('theme-header-background'),
              fit: BoxFit.cover,
              // Favor the upper portrait, but avoid cropping to only the hair
              // when a compact header shows a narrow slice of the artwork.
              alignment: const Alignment(0, -0.4),
              cacheWidth: 1500,
              errorBuilder: (context, error, stack) =>
                  ColoredBox(color: context.navBarColor)),
          ColoredBox(
              color: context.isDark
                  ? const Color(0x55000000)
                  : const Color(0x55FFFFFF)),
        ]))),
        Padding(
            padding: const EdgeInsets.symmetric(vertical: _extraHeight / 2),
            child: bar),
      ]);
}
