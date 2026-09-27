import 'package:flutter/foundation.dart';

/// 平台能力探测：区分移动端与桌面端，供 Android 专属功能降级。
class PlatformSupport {
  static bool get isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  static bool get isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 系统桌面小组件（Android Home Widget）
  static bool get supportsHomeWidgets => isAndroid;

  /// 系统通知（移动端完整，桌面端可先关闭）
  static bool get supportsLocalNotifications => isAndroid;

  /// 相册写入（gal）
  static bool get supportsGallerySave => isAndroid;

  /// 应用内更新安装 APK
  static bool get supportsApkInstall => isAndroid;
}
