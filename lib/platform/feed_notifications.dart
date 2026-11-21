import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// 到点闹钟提醒（系统级定时通知，App 被杀后仍会触发）。
class FeedNotifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static const String _channelId = 'feeding_reminder';
  static bool _ready = false;

  static AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  static Future<void> init() async {
    if (_ready) return;
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_feed'),
      ),
    );
    _ready = true;
  }

  /// 请求通知权限与精确闹钟权限（Android 13+ / 14+ 需要）。
  static Future<void> requestPermissions() async {
    await init();
    try {
      await _android?.requestNotificationsPermission();
      await _android?.requestExactAlarmsPermission();
    } on Object catch (error) {
      debugPrint('请求通知权限失败: $error');
    }
  }

  static bool _permissionRequested = false;

  /// 每个进程内只请求一次，避免反复跳到系统设置页。
  static Future<void> requestPermissionsOnce() async {
    if (_permissionRequested) return;
    _permissionRequested = true;
    await requestPermissions();
  }

  static Future<void> schedule({
    required int id,
    required int atMs,
    required String body,
  }) async {
    await init();
    if (atMs <= DateTime.now().millisecondsSinceEpoch) return;
    final when = tz.TZDateTime.fromMillisecondsSinceEpoch(tz.local, atMs);
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        '喂奶提醒',
        channelDescription: '到达预估的下次喂奶时间时提醒',
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.public,
        playSound: true,
        enableVibration: true,
      ),
    );
    try {
      await _plugin.zonedSchedule(
        id: id,
        title: '该喂奶了',
        body: body,
        scheduledDate: when,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'feeding',
      );
    } on Exception catch (error) {
      // 没有精确闹钟权限时退化为非精确调度，仍能提醒。
      debugPrint('精确闹钟调度失败，改为非精确调度: $error');
      await _plugin.zonedSchedule(
        id: id,
        title: '该喂奶了',
        body: body,
        scheduledDate: when,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'feeding',
      );
    }
  }

  static Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }
}
