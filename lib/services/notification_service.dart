import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 系统通知服务：角色在用户离开聊天界面时发来新消息，
/// 向系统通知栏推送一条包含角色名称、消息内容与角色头像的通知。
///
/// 「未读消息发送系统通知」开关（shared_preferences key: unread_notify）
/// 由 SettingsProvider 持久化，本服务在发送前自行读取判断，避免 Provider 耦合。
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const String _channelId = 'unread_messages';
  static const String _channelName = '未读消息';
  static const String _channelDesc = '角色在您离开聊天界面时发来的新消息提醒';
  static const String _unreadNotifyKey = 'unread_notify';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// 应用启动时初始化：创建通知渠道并请求 Android 13+ 通知权限。
  Future<void> init() async {
    if (_initialized) return;
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings: initSettings);
    final android =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    // Android 13+（API 33）需要运行时通知权限
    await android?.requestNotificationsPermission();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.high,
        playSound: true,
      ),
    );
    _initialized = true;
  }

  /// 发送一条角色新消息通知。[notificationId] 按会话稳定生成，
  /// 同一会话的多条新消息会更新同一条通知（显示最新内容），避免通知堆积。
  Future<void> showCharacterNotification({
    required int notificationId,
    required String characterName,
    required String content,
    String avatarBase64 = '',
  }) async {
    if (!await _isUnreadNotifyEnabled()) return;

    // 角色头像（base64）解码为原始图片字节，作为通知大图标
    Uint8List? largeIconBytes;
    if (avatarBase64.isNotEmpty) {
      try {
        largeIconBytes = base64Decode(avatarBase64);
      } catch (_) {
        largeIconBytes = null; // 非法 base64 忽略头像
      }
    }

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(
          content,
          contentTitle: characterName,
          summaryText: 'AiChat',
        ),
        largeIcon: largeIconBytes == null
            ? null
            : ByteArrayAndroidBitmap(largeIconBytes),
      ),
    );
    await _plugin.show(
      id: notificationId,
      title: characterName,
      body: content,
      notificationDetails: details,
    );
  }

  /// 读取「未读消息发送系统通知」开关状态
  Future<bool> _isUnreadNotifyEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_unreadNotifyKey) ?? true; // 默认开启
  }
}
