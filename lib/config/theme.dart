import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import 'ui_spec.dart';

/// sr 崩铁短信气泡配色（从截图提取）
class SrBubbleColors {
  /// 我方气泡：暖棕/驼色（明暗模式一致）
  static const selfColor = Color(0xFFD2BC95);

  /// 对方气泡：浅色模式浅灰
  static const otherColor = Color(0xFFE7E7E7);

  /// 对方气泡：深色模式深灰
  static const otherColorDark = Color(0xFF2C2C2C);

  /// 我方气泡文字：白色（明暗模式一致）
  static const selfTextColor = Color.fromARGB(255, 0, 0, 0);

  /// 对方气泡文字：浅色模式深灰
  static const otherTextColor = Color(0xFF4A4A4A);

  /// 对方气泡文字：深色模式浅灰
  static const otherTextColorDark = Color(0xFFE0E0E0);

  /// 柔和底部阴影
  static const shadowColor = Color(0x1A000000); // alpha ≈ 0.1
}

/// ww 鸣潮气泡配色（浅色/深色模式分开配置）
class WwBubbleColors {
  /// 我方气泡：浅色模式（深灰蓝）
  static const selfColorLight = Color(0xFF20252E);

  /// 我方气泡：深色模式
  static const selfColorDark = Color.fromARGB(255, 95, 110, 129);

  /// 对方气泡：浅色模式
  static const otherColorLight = Color(0xFFE7E7E7);

  /// 对方气泡：深色模式
  static const otherColorDark = Color(0xFF2C2C2C);

  /// 我方气泡文字：黑色
  static const selfTextColor = Color(0xFFFFFFFF);

  /// 对方气泡文字：浅色模式黑色
  static const otherTextColorLight = Color(0xFF000000);

  /// 对方气泡文字：深色模式白色
  static const otherTextColorDark = Color(0xFFFFFFFF);

  /// 柔和底部阴影：深色模式 alpha 0.05
  static const shadowColorDark = Color(0x0D000000);

  /// 柔和底部阴影：浅色模式再减半 alpha ≈ 0.025
  static const shadowColorLight = Color(0x06000000);
}

/// zmd 终末地气泡配色（基于鸣潮尾巴形状，浅色/深色模式对方气泡配色分开）
class ZmdBubbleColors {
  /// 我方气泡：白色（浅深一致）
  static const selfColor = Color(0xFFEDEDED);

  /// 我方气泡文字：黑色（浅深一致）
  static const selfTextColor = Color(0xFF000000);

  /// 我方气泡黑色轮廓描边（浅深一致）
  static const selfBorderColor = Color(0xFF000000);

  /// 对方气泡：浅色模式浅灰（与 ww/sr/默认样式统一）
  static const otherColorLight = Color(0xFFE7E7E7);

  /// 对方气泡：深色模式深灰（与 ww/sr/默认样式统一）
  static const otherColorDark = Color(0xFF2C2C2C);

  /// 对方气泡文字：浅色模式黑色
  static const otherTextColorLight = Color(0xFF000000);

  /// 对方气泡文字：深色模式白色
  static const otherTextColorDark = Color(0xFFFFFFFF);

  /// 柔和底部阴影（与鸣潮一致：深色 alpha 0.05）
  static const shadowColorDark = Color(0x0D000000);

  /// 柔和底部阴影（与鸣潮一致：浅色 alpha ≈ 0.025）
  static const shadowColorLight = Color(0x06000000);
}

/// 亮/暗两套色板
class AppColors {
  // 亮色模式
  static const scaffoldLight = Color(0xFFF5F5F7); // Apple grouped background
  // 二级页面使用 CupertinoPageScaffold 的自动顶部安全区消费。
  // 完全不透明可避免列表首项被半透明导航栏覆盖。
  static const navBarLight = Color(0xFFFFFFFF);
  static const listBgLight = Color(0xFFFFFFFF); // surface
  static const chatBgLight = Color(0xFFF9F9FB); // calm conversation canvas
  // iMessage / ChatGPT style default conversation colors.
  static const bubbleSelfLight = Color(0xFF0A84FF); // 自己气泡
  static const bubbleOtherLight = Color(0xFFE7E7E7); // 对方气泡
  static const textPrimaryLight = Color(0xFF1F1F1F);
  static const textSecondaryLight = Color(0xFF8A8A8E);
  static const fieldBgLight = Color(0xFFEFEFF4); // system fill
  static const pinnedChatLight = Color(0xFFFFFFFF); // 置顶会话条目背景（浅色）

  // 暗色模式（Apple system background / surface 层级）
  static const scaffoldDark = Color(0xFF0B0B0F);
  static const navBarDark = Color(0xFF111318);
  static const listBgDark = Color(0xFF111318);
  static const chatBgDark = Color(0xFF0B0B0F);
  static const bubbleSelfDark = Color(0xFF0A84FF); // 自己气泡
  static const bubbleOtherDark = Color(0xFF2C2C2C); // 对方气泡
  static const textPrimaryDark = Color(0xFFF0F0F0);
  static const textSecondaryDark = Color(0xFF8E8E93);
  static const fieldBgDark = Color(0xFF1C1C1E);
  static const pinnedChatDark = Color(0xFF242424); // 置顶会话条目背景（深色）

  // Obsidian-style settings surfaces. These are UI-only surfaces and do not
  // participate in persisted preferences or bubble palettes.
  static const settingsSurfaceLight = Color(0xFFFFFFFF);
  static const settingsSurfaceDark = Color(0xFF1C1C1E);
  static const settingsOutlineLight = Color(0xFFD9D9DE);
  static const settingsOutlineDark = Color(0xFF2A2A2E);

  // 气泡内字体颜色（自己/对方 × 浅色/深色）
  static const bubbleTextSelfLight = Color(0xFFFFFFFF);
  static const bubbleTextOtherLight = Color(0xFF000000);
  static const bubbleTextSelfDark = Color(0xFFFFFFFF);
  static const bubbleTextOtherDark = Color(0xFFD6D6D6);

  // 预设主题色（5 个）
  static const presetColors = <Color>[
    Color(0xFF07C160), // 微信绿
    Color(0xFFFE8E1C), // mimo橙色
    Color(0xFF007AFF), // QQ蓝
    Color(0xFFD8BF00), // 终末地黄
    Color(0xFF2A5995), // ds蓝
  ];

  // 朋友圈（深色卡片风格，浅色模式改用浅灰底）
  static const momentsBgLight = Color(0xFFF5F5F7); // 朋友圈页面/面板背景
  static const momentsBgDark = Color(0xFF0B0B0F);
  static const momentCardLight = Color(0xFFFFFFFF); // 朋友圈卡片背景
  static const momentCardDark = Color(0xFF202024);
  static const momentBlockLight = Color(0xFFF2F2F2); // 点赞/评论浅底块
  static const momentBlockDark = Color(0xFF18181A);

  // 设置页低饱和语义图标色：普通图标不跟随主题色，避免全部同色。
  static const settingIconAppearanceLight = Color(0xFF7566A8);
  static const settingIconAppearanceDark = Color(0xFFB9A8ED);
  static const settingIconStickersLight = Color(0xFFB9783B);
  static const settingIconStickersDark = Color(0xFFD6A16A);
  static const settingIconDisplayLight = Color(0xFF3C8A88);
  static const settingIconDisplayDark = Color(0xFF79C5C0);
  static const settingIconNotificationsLight = Color(0xFFB65E68);
  static const settingIconNotificationsDark = Color(0xFFE38B96);
  static const settingIconDeveloperLight = Color(0xFFA77B2E);
  static const settingIconDeveloperDark = Color(0xFFD7B15E);
  static const settingIconUpdatesLight = Color(0xFF4A78A8);
  static const settingIconUpdatesDark = Color(0xFF8FB5E2);
  static const settingIconMemoryLight = Color(0xFF596AA6);
  static const settingIconMemoryDark = Color(0xFF9EADDF);
  static const settingIconStorageLight = Color(0xFF5E748A);
  static const settingIconStorageDark = Color(0xFF9BB6C8);
}

/// 设置页前导图标的功能语义。
enum SettingIconRole {
  appearance,
  stickers,
  display,
  notifications,
  developer,
  updates,
  memory,
  storage,
}

class AppTheme {
  /// 构建动态主题（明暗 + 主题色）
  static CupertinoThemeData buildTheme({
    required Brightness brightness,
    required Color accent,
    String? fontFamily,
  }) {
    final isDark = brightness == Brightness.dark;
    return CupertinoThemeData(
      brightness: brightness,
      primaryColor: accent,
      primaryContrastingColor: CupertinoColors.white,
      scaffoldBackgroundColor:
          isDark ? AppColors.scaffoldDark : AppColors.scaffoldLight,
      barBackgroundColor: isDark ? AppColors.navBarDark : AppColors.navBarLight,
      textTheme: CupertinoTextThemeData(
        primaryColor: accent,
        // 桌面端传入 Windows 字体栈；手机端不指定，用系统字体
        textStyle: TextStyle(
          fontSize: 16,
          fontFamily: fontFamily,
          color:
              isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
        ),
        navTitleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          fontFamily: fontFamily,
          color:
              isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
        ),
        navActionTextStyle: TextStyle(
          fontSize: 16,
          color: accent,
          fontFamily: fontFamily,
        ),
        actionTextStyle: TextStyle(
          fontSize: 16,
          color: accent,
          fontFamily: fontFamily,
        ),
        tabLabelTextStyle: TextStyle(
          fontSize: 10,
          fontFamily: fontFamily,
          color: isDark
              ? AppColors.textSecondaryDark
              : AppColors.textSecondaryLight,
        ),
      ),
    );
  }
}

/// 通过 BuildContext 便捷获取主题相关颜色
extension AppThemeX on BuildContext {
  bool get isDark => CupertinoTheme.of(this).brightness == Brightness.dark;

  Color get accentColor => CupertinoTheme.of(this).primaryColor;

  Color settingIconColor(SettingIconRole role) {
    final dark = isDark;
    return switch (role) {
      SettingIconRole.appearance => dark
          ? AppColors.settingIconAppearanceDark
          : AppColors.settingIconAppearanceLight,
      SettingIconRole.stickers => dark
          ? AppColors.settingIconStickersDark
          : AppColors.settingIconStickersLight,
      SettingIconRole.display => dark
          ? AppColors.settingIconDisplayDark
          : AppColors.settingIconDisplayLight,
      SettingIconRole.notifications => dark
          ? AppColors.settingIconNotificationsDark
          : AppColors.settingIconNotificationsLight,
      SettingIconRole.developer => dark
          ? AppColors.settingIconDeveloperDark
          : AppColors.settingIconDeveloperLight,
      SettingIconRole.updates => dark
          ? AppColors.settingIconUpdatesDark
          : AppColors.settingIconUpdatesLight,
      SettingIconRole.memory => dark
          ? AppColors.settingIconMemoryDark
          : AppColors.settingIconMemoryLight,
      SettingIconRole.storage => dark
          ? AppColors.settingIconStorageDark
          : AppColors.settingIconStorageLight,
    };
  }

  Color get scaffoldColor =>
      isDark ? AppColors.scaffoldDark : AppColors.scaffoldLight;

  Color get navBarColor =>
      isDark ? AppColors.navBarDark : AppColors.navBarLight;

  Color get listBgColor =>
      isDark ? AppColors.listBgDark : AppColors.listBgLight;

  /// Apple-style semantic surfaces used by cards and grouped settings.
  Color get surfaceColor => listBgColor;

  Color get groupedSurfaceColor =>
      isDark ? const Color(0xFF161A22) : const Color(0xFFEFEFF4);

  Color get settingsSurfaceColor =>
      isDark ? AppColors.settingsSurfaceDark : AppColors.settingsSurfaceLight;

  Color get settingsOutlineColor =>
      isDark ? AppColors.settingsOutlineDark : AppColors.settingsOutlineLight;

  Color get settingsDividerColor => isDark
      ? CupertinoColors.white.withValues(alpha: 0.075)
      : CupertinoColors.black.withValues(alpha: 0.075);

  Color get outlineColor =>
      isDark ? const Color(0xFF2E2F32) : const Color(0xFFD1D1D6);

  Color get chatBgColor =>
      isDark ? AppColors.chatBgDark : AppColors.chatBgLight;

  /// 置顶会话条目背景色
  Color get pinnedChatColor =>
      isDark ? AppColors.pinnedChatDark : AppColors.pinnedChatLight;

  /// 自己气泡颜色：支持在设置中按明暗模式单独自定义
  Color get bubbleSelfColor {
    final settings = read<SettingsProvider>();
    return settings.bubbleColor(
        isDark ? BubbleColorSlot.selfDark : BubbleColorSlot.selfLight);
  }

  /// 对方气泡颜色：支持在设置中按明暗模式单独自定义
  Color get bubbleOtherColor {
    final settings = read<SettingsProvider>();
    return settings.bubbleColor(
        isDark ? BubbleColorSlot.otherDark : BubbleColorSlot.otherLight);
  }

  /// 自己气泡内字体颜色：支持在设置中按明暗模式单独自定义
  Color get bubbleTextSelfColor {
    final settings = read<SettingsProvider>();
    return settings.bubbleTextColor(
        isDark ? BubbleTextSlot.selfDark : BubbleTextSlot.selfLight);
  }

  /// 对方气泡内字体颜色：支持在设置中按明暗模式单独自定义
  Color get bubbleTextOtherColor {
    final settings = read<SettingsProvider>();
    return settings.bubbleTextColor(
        isDark ? BubbleTextSlot.otherDark : BubbleTextSlot.otherLight);
  }

  Color get textPrimaryColor =>
      isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;

  Color get textSecondaryColor =>
      isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

  Color get fieldBgColor =>
      isDark ? AppColors.fieldBgDark : AppColors.fieldBgLight;

  Color get separatorColor => isDark
      ? CupertinoColors.white.withValues(alpha: 0.1)
      : CupertinoColors.systemGrey5;

  /// 会话列表的弱分割线：接近微信列表的低对比度分隔，避免暗色模式
  /// 因为重复覆盖透明度而出现刺眼的亮线。
  Color get conversationDividerColor => isDark
      ? CupertinoColors.white.withValues(alpha: 0.08)
      : CupertinoColors.black.withValues(alpha: 0.07);

  /// 通讯录分割线：比会话列表更轻，避免密集的亮线影响浏览。
  Color get contactDividerColor => isDark
      ? CupertinoColors.white.withValues(alpha: 0.045)
      : CupertinoColors.black.withValues(alpha: 0.05);

  /// 朋友圈页面/面板背景
  Color get momentsBgColor =>
      isDark ? AppColors.momentsBgDark : AppColors.momentsBgLight;

  /// 朋友圈卡片背景
  Color get momentCardColor =>
      isDark ? AppColors.momentCardDark : AppColors.momentCardLight;

  /// 朋友圈点赞/评论浅底块背景
  Color get momentBlockColor =>
      isDark ? AppColors.momentBlockDark : AppColors.momentBlockLight;

  /// 当前气泡样式
  BubbleStyle get bubbleStyle => read<SettingsProvider>().bubbleStyle;

  /// 当前会话 UI 样式
  UiStyle get uiStyle => read<SettingsProvider>().uiStyle;

  /// 当前首页移动端底部导航样式。
  HomeNavigationStyle get homeNavigationStyle =>
      read<SettingsProvider>().homeNavigationStyle;

  /// 底部导航模式对应的主页滚动末尾留白。
  double get homeContentBottomInset => homeNavigationStyle ==
          HomeNavigationStyle.floating
      ? UiSpec.floatingContentBottomInset
      : UiSpec.bottomPanelContentBottomInset;

  /// 气泡圆角半径（Apple 消息样式的柔和胶囊感）
  double get bubbleBorderRadius => 18;

  /// 气泡圆角：sr 样式下靠近头像一侧的上边角为直角
  /// （我方气泡在右侧头像在右 → 右上角直角；对方气泡在左侧头像在左 → 左上角直角）
  BorderRadius bubbleBorderRadiusFor(bool isUser) {
    final r = bubbleBorderRadius;
    if (bubbleStyle == BubbleStyle.sr) {
      return isUser
          ? BorderRadius.only(
              topLeft: Radius.circular(r),
              topRight: Radius.zero,
              bottomLeft: Radius.circular(r),
              bottomRight: Radius.circular(r),
            )
          : BorderRadius.only(
              topLeft: Radius.zero,
              topRight: Radius.circular(r),
              bottomLeft: Radius.circular(r),
              bottomRight: Radius.circular(r),
            );
    }
    return BorderRadius.circular(r);
  }

  /// 气泡背景色：sr/ww/zmd 样式使用自带配色，经典样式使用自定义颜色
  Color bubbleBgColor(bool isUser) {
    if (bubbleStyle == BubbleStyle.sr) {
      if (isUser) return SrBubbleColors.selfColor;
      return isDark ? SrBubbleColors.otherColorDark : SrBubbleColors.otherColor;
    }
    if (bubbleStyle == BubbleStyle.ww) {
      if (isUser) {
        return isDark
            ? WwBubbleColors.selfColorDark
            : WwBubbleColors.selfColorLight;
      }
      return isDark
          ? WwBubbleColors.otherColorDark
          : WwBubbleColors.otherColorLight;
    }
    if (bubbleStyle == BubbleStyle.zmd) {
      // 终末地：对方气泡按明暗模式分色，我方气泡浅深一致
      return isUser
          ? ZmdBubbleColors.selfColor
          : isDark
              ? ZmdBubbleColors.otherColorDark
              : ZmdBubbleColors.otherColorLight;
    }
    return isUser ? bubbleSelfColor : bubbleOtherColor;
  }

  /// 气泡内文字色：sr/ww/zmd 样式固定配色，经典样式使用自定义文字色
  Color bubbleTextColor(bool isUser) {
    if (bubbleStyle == BubbleStyle.sr) {
      if (isUser) return SrBubbleColors.selfTextColor;
      return isDark
          ? SrBubbleColors.otherTextColorDark
          : SrBubbleColors.otherTextColor;
    }
    if (bubbleStyle == BubbleStyle.ww) {
      if (isUser) return WwBubbleColors.selfTextColor;
      return isDark
          ? WwBubbleColors.otherTextColorDark
          : WwBubbleColors.otherTextColorLight;
    }
    if (bubbleStyle == BubbleStyle.zmd) {
      return isUser
          ? ZmdBubbleColors.selfTextColor
          : isDark
              ? ZmdBubbleColors.otherTextColorDark
              : ZmdBubbleColors.otherTextColorLight;
    }
    return isUser ? bubbleTextSelfColor : bubbleTextOtherColor;
  }

  /// 气泡内文字字体：分别由显示设置中的我方/对方选择决定；空值交给系统默认字体。
  String? bubbleFontFamily(bool isUser) {
    final family = read<SettingsProvider>().bubbleFontFamily(isUser);
    return family.isEmpty ? null : family;
  }

  /// 气泡内文字字号，由显示设置统一控制。
  double get bubbleFontSize => read<SettingsProvider>().bubbleFontSize;

  /// 气泡轮廓描边色：仅 zmd 样式我方气泡在深色模式使用黑色描边
  /// （浅色模式无描边，白底气泡与浅色聊天背景自然融合），其余样式无描边
  Color? bubbleBorderColor(bool isUser) {
    if (bubbleStyle != BubbleStyle.zmd || !isUser) return null;
    return isDark ? ZmdBubbleColors.selfBorderColor : null;
  }

  /// 气泡阴影：sr 带柔和投影，ww/zmd 投影减半（更轻），经典样式无阴影
  List<BoxShadow>? get bubbleShadow {
    if (bubbleStyle == BubbleStyle.sr) {
      return const [
        BoxShadow(
          color: SrBubbleColors.shadowColor,
          offset: Offset(0, 2),
          blurRadius: 6,
        ),
      ];
    }
    if (bubbleStyle == BubbleStyle.ww) {
      return [
        BoxShadow(
          // 浅色模式阴影再减半，深色模式保持原样
          color: isDark
              ? WwBubbleColors.shadowColorDark
              : WwBubbleColors.shadowColorLight,
          offset: const Offset(0, 1),
          blurRadius: 3,
        ),
      ];
    }
    if (bubbleStyle == BubbleStyle.zmd) {
      return [
        BoxShadow(
          // 与鸣潮一致：浅色模式阴影减半，深色模式保持原样
          color: isDark
              ? ZmdBubbleColors.shadowColorDark
              : ZmdBubbleColors.shadowColorLight,
          offset: const Offset(0, 1),
          blurRadius: 3,
        ),
      ];
    }
    return null;
  }
}
