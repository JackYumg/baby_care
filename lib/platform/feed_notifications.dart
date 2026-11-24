import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// 到点闹钟提醒（系统级定时通知，App 被杀后仍会触发）。
class FeedNotifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static const String _channelId = 'feeding_reminder';
  static const String _careChannelId = 'care_tasks';
  static const String _carePayload = 'care_task';
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

  /// 调度一条儿保 / 疫苗接种提醒。
  ///
  /// 返回是否真正写入系统调度（时间已过或平台失败时返回 false）。
  static Future<bool> scheduleCare({
    required int id,
    required int atMs,
    required String title,
    required String body,
  }) async {
    await init();
    if (atMs <= DateTime.now().millisecondsSinceEpoch) return false;
    final when = tz.TZDateTime.fromMillisecondsSinceEpoch(tz.local, atMs);
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _careChannelId,
        '儿保与疫苗',
        channelDescription: '儿保检查与疫苗接种计划当天的提醒',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        visibility: NotificationVisibility.public,
        playSound: true,
        enableVibration: true,
      ),
    );
    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: when,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: _carePayload,
      );
    } on Exception catch (error) {
      debugPrint('儿保提醒精确调度失败，改为非精确调度: $error');
      try {
        await _plugin.zonedSchedule(
          id: id,
          title: title,
          body: body,
          scheduledDate: when,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: _carePayload,
        );
      } on Exception catch (fallbackError) {
        debugPrint('儿保提醒调度失败: $fallbackError');
        return false;
      }
    }
    return true;
  }

  /// 按 id 取消一条儿保 / 疫苗提醒。
  static Future<void> cancelCare(int id) async {
    await init();
    await _plugin.cancel(id: id);
  }

  /// 取消所有喂奶相关通知，但保留已调度的儿保 / 疫苗提醒。
  static Future<void> cancelAll() async {
    await init();
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final request in pending) {
        if (request.payload == _carePayload) continue;
        await _plugin.cancel(id: request.id);
      }
    } on Object catch (error) {
      debugPrint('按条取消通知失败，改用全部取消: $error');
      await _plugin.cancelAll();
    }
  }
}
