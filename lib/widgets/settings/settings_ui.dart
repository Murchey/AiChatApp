import 'dart:ui';
import 'package:flutter/cupertino.dart';

import '../../config/motion.dart';
import '../../config/theme.dart';
import '../../config/ui_spec.dart';

/// Shared content inset for settings pages hosted below a Cupertino bar.
/// The page scaffold consumes the navigation bar, while the status-bar inset
/// still needs to be reserved explicitly by the scrolling child.
EdgeInsets settingsPageContentPadding(
  BuildContext context, {
  double? bottom,
  double extraTop = 0,
}) {
  return EdgeInsets.only(
    top: MediaQuery.paddingOf(context).top + UiSpec.settingsPageTop + extraTop,
    bottom: bottom ?? UiSpec.floatingContentBottomInset,
  );
}

/// Shared navigation chrome for settings pages. It keeps normal
/// Navigator.pop/back gesture semantics while using a quieter, centered
/// Obsidian-style title treatment.
ObstructingPreferredSizeWidget settingsNavigationBar(
  BuildContext context,
  String title, {
  String? previousPageTitle,
  Widget? trailing,
  bool legacy = false,
  bool compact = false,
  VoidCallback? onBack,
}) {
  if (legacy) {
    return _legacySettingsNavigationBar(context, title,
        previousPageTitle: previousPageTitle, trailing: trailing);
  }
  return _GlassSettingsHeader(
      title: title, trailing: trailing, compact: compact, onBack: onBack);
}

CupertinoNavigationBar _legacySettingsNavigationBar(
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

class _GlassSettingsHeader extends StatelessWidget
    implements ObstructingPreferredSizeWidget {
  final String title;
  final Widget? trailing;
  final bool compact;
  final VoidCallback? onBack;
  const _GlassSettingsHeader(
      {required this.title, this.trailing, this.compact = false, this.onBack});

  @override
  Size get preferredSize => Size.fromHeight(compact ? 56 : 96);
  @override
  bool shouldFullyObstruct(BuildContext context) => false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.paddingOf(context).top + preferredSize.height,
      child: Stack(children: [
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRect(
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFFFFFFF),
                    Color(0xFFFFFFFF),
                    Color(0x00FFFFFF)
                  ],
                  stops: [0, 0.25, 1],
                ).createShader(rect),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: ColoredBox(
                      color: context.navBarColor.withValues(alpha: 0.95)),
                ),
              ),
            ),
          ),
        ),
        SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, 4, 12, compact ? 4 : 28),
              child: Row(children: [
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                  child: ClipOval(
                      child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: context.fieldBgColor.withValues(alpha: 0.65),
                        border: Border.all(
                            color: context.textSecondaryColor
                                .withValues(alpha: 0.25)),
                      ),
                      child: Icon(CupertinoIcons.chevron_left,
                          size: 20, color: context.textPrimaryColor),
                    ),
                  )),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: UiSpec.fontTitle,
                            fontWeight: FontWeight.w600,
                            color: context.textPrimaryColor))),
                if (trailing != null) trailing!,
              ]),
            )),
      ]),
    );
  }
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
/// stable trailing slot. Keeping the right slot constrained prevents a
/// multiline subtitle from shifting values, switches, or chevrons sideways.
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
  final double? trailingWidth;

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
    this.trailingWidth,
  });

  @override
  Widget build(BuildContext context) {
    final hasTrailing = trailing != null || showChevron;
    final defaultTrailingWidth = showChevron
        ? (trailing == null ? 28.0 : 104.0)
        : (trailing == null ? 0.0 : 58.0);
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: UiSpec.settingsRowMinHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: UiSpec.settingsRowHorizontal,
          vertical: UiSpec.settingsRowVertical,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
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
            if (hasTrailing) ...[
              const SizedBox(width: 10),
              SizedBox(
                width: trailingWidth ?? defaultTrailingWidth,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (trailing != null)
                      Flexible(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: trailing!,
                        ),
                      ),
                    if (showChevron) ...[
                      if (trailing != null) const SizedBox(width: 8),
                      Icon(
                        CupertinoIcons.chevron_right,
                        size: 17,
                        color:
                            context.textSecondaryColor.withValues(alpha: 0.72),
                      ),
                    ],
                  ],
                ),
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
    textAlign: TextAlign.end,
    style: TextStyle(
      fontSize: UiSpec.fontBodySm,
      color: context.textSecondaryColor,
    ),
  );
}

/// One option shown by an anchored settings picker.
class SettingsChoiceOption<T> {
  final T value;
  final String label;
  final String? subtitle;
  final bool enabled;

  const SettingsChoiceOption({
    required this.value,
    required this.label,
    this.subtitle,
    this.enabled = true,
  });
}

/// A reusable overlay anchored to a settings row. It deliberately uses the
/// app overlay instead of a bottom sheet so the option list stays visually
/// attached to the setting the user just tapped.
class SettingsInlinePanel extends StatefulWidget {
  final Widget Function(BuildContext context, VoidCallback toggle) rowBuilder;
  final Widget Function(BuildContext context, VoidCallback close) panelBuilder;
  final double estimatedPanelHeight;
  final double? panelWidth;
  final String? panelKey;

  const SettingsInlinePanel({
    super.key,
    required this.rowBuilder,
    required this.panelBuilder,
    this.estimatedPanelHeight = 220,
    this.panelWidth,
    this.panelKey,
  });

  @override
  State<SettingsInlinePanel> createState() => _SettingsInlinePanelState();
}

class _SettingsInlinePanelState extends State<SettingsInlinePanel>
    with SingleTickerProviderStateMixin {
  final _targetKey = GlobalKey();
  OverlayEntry? _overlay;
  late final AnimationController _animationController;
  bool _placeAbove = false;
  double _panelLeft = 0;
  double _panelTop = 0;
  double _panelWidth = 0;
  double _panelHeight = 0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: AppMotion.quick,
      reverseDuration: AppMotion.micro,
    );
  }

  bool get isOpen => _overlay != null;

  void _toggle() {
    if (isOpen) {
      _close();
    } else {
      _open();
    }
  }

  void _open() {
    final target = _targetKey.currentContext?.findRenderObject() as RenderBox?;
    if (target == null || !target.hasSize) return;
    final topLeft = target.localToGlobal(Offset.zero);
    final media = MediaQuery.of(context);
    final viewportTop = media.padding.top;
    final availableBottom =
        media.size.height - media.viewInsets.bottom - media.padding.bottom;
    final availableHeight =
        (availableBottom - viewportTop).clamp(1.0, double.infinity).toDouble();
    final viewportBottom = availableBottom > viewportTop
        ? availableBottom
        : viewportTop + availableHeight;
    final maxWidth = media.size.width - UiSpec.pageH * 2;
    _panelWidth =
        (widget.panelWidth ?? maxWidth).clamp(1.0, maxWidth).toDouble();
    _panelLeft = topLeft.dx.clamp(
      UiSpec.pageH,
      media.size.width - UiSpec.pageH - _panelWidth,
    );

    // Give the panel a real height before inserting it into the root overlay.
    // This keeps shrink-wrapped lists from expanding to the overlay height and
    // moving their options outside the viewport when the row is near the
    // bottom of a scrolling settings page.
    final preferredHeight = widget.estimatedPanelHeight
        .clamp(1.0, UiSpec.settingsInlinePanelMaxHeight)
        .toDouble();
    final belowSpace = viewportBottom -
        (topLeft.dy + target.size.height + UiSpec.settingsInlinePanelGap);
    final aboveSpace = topLeft.dy - viewportTop - UiSpec.settingsInlinePanelGap;
    _placeAbove = belowSpace < preferredHeight && aboveSpace > belowSpace;
    final sideSpace = _placeAbove ? aboveSpace : belowSpace;
    final fallbackSpace = _placeAbove ? belowSpace : aboveSpace;
    _panelHeight = preferredHeight.clamp(1.0, availableHeight).toDouble();
    if (sideSpace > 1) {
      _panelHeight = _panelHeight.clamp(1.0, sideSpace).toDouble();
    } else if (fallbackSpace > 1) {
      _placeAbove = !_placeAbove;
      _panelHeight = _panelHeight.clamp(1.0, fallbackSpace).toDouble();
    }
    _panelTop = _placeAbove
        ? topLeft.dy - UiSpec.settingsInlinePanelGap - _panelHeight
        : topLeft.dy + target.size.height + UiSpec.settingsInlinePanelGap;
    _panelTop =
        _panelTop.clamp(viewportTop, viewportBottom - _panelHeight).toDouble();

    _animationController.value = 0;
    _overlay = OverlayEntry(builder: _buildOverlay);
    Overlay.of(context, rootOverlay: true).insert(_overlay!);
    _animationController.forward();
    setState(() {});
  }

  Widget _buildOverlay(BuildContext overlayContext) {
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _close,
          child: const SizedBox.expand(),
        ),
        Positioned(
          left: _panelLeft,
          top: _panelTop,
          width: _panelWidth,
          height: _panelHeight,
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: _animationController,
              curve: Curves.easeOut,
            ),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.98, end: 1).animate(
                CurvedAnimation(
                  parent: _animationController,
                  curve: Curves.easeOutCubic,
                ),
              ),
              alignment: _placeAbove ? Alignment.bottomLeft : Alignment.topLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: _panelWidth,
                  maxHeight: _panelHeight,
                ),
                child: KeyedSubtree(
                  key: widget.panelKey == null
                      ? null
                      : ValueKey<String>(widget.panelKey!),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: context.settingsSurfaceColor,
                      borderRadius: BorderRadius.circular(
                        UiSpec.settingsInlinePanelRadius,
                      ),
                      border: Border.all(
                        color: context.settingsOutlineColor.withValues(
                          alpha: 0.82,
                        ),
                        width: 0.6,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: CupertinoColors.black.withValues(
                            alpha: UiSpec.settingsInlinePanelShadowOpacity,
                          ),
                          blurRadius: UiSpec.settingsInlinePanelShadowBlur,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        UiSpec.settingsInlinePanelRadius,
                      ),
                      child: widget.panelBuilder(context, _close),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _close() {
    final overlay = _overlay;
    if (overlay == null) return;
    _overlay = null;
    _animationController.reverse().whenCompleteOrCancel(() {
      overlay.remove();
    });
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    final overlay = _overlay;
    _overlay = null;
    overlay?.remove();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minWidth =
            constraints.hasBoundedWidth ? constraints.maxWidth : 0.0;
        return Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: minWidth),
            child: KeyedSubtree(
              key: _targetKey,
              child: IntrinsicHeight(
                child: widget.rowBuilder(context, _toggle),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A compact anchored choice list. The row remains owned by the caller so
/// existing icons, subtitles, values, and navigation semantics are retained.
class SettingsInlinePicker<T> extends StatelessWidget {
  final T value;
  final List<SettingsChoiceOption<T>> options;
  final ValueChanged<T> onChanged;
  final Widget Function(BuildContext context, VoidCallback toggle) rowBuilder;
  final String? panelKey;

  const SettingsInlinePicker({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.rowBuilder,
    this.panelKey,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsInlinePanel(
      panelKey: panelKey,
      estimatedPanelHeight: options.fold<double>(
        12,
        (height, option) => height + (option.subtitle == null ? 52.0 : 88.0),
      ),
      rowBuilder: rowBuilder,
      panelBuilder: (panelContext, close) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 6),
        children: [
          for (final option in options)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              onPressed: option.enabled
                  ? () {
                      onChanged(option.value);
                      close();
                    }
                  : null,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          option.label,
                          style: TextStyle(
                            fontSize: UiSpec.settingsRowTitle,
                            color: option.enabled
                                ? panelContext.textPrimaryColor
                                : panelContext.textSecondaryColor
                                    .withValues(alpha: 0.5),
                          ),
                        ),
                        if (option.subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            option.subtitle!,
                            style: TextStyle(
                              fontSize: UiSpec.settingsRowSubtitle,
                              color: panelContext.textSecondaryColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (option.value == value)
                    Icon(
                      CupertinoIcons.check_mark,
                      size: 18,
                      color: panelContext.accentColor,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
