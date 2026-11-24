import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'alarm_scheduler.dart';

/// 到点提醒（系统级闹钟，App 被杀后仍会触发）。
///
/// 真正的调度与响铃交给 [AlarmScheduler]：Android 端用 AlarmManager 定时、
/// 前台服务循环播放手机自带闹钟铃声，直到用户点击「停止响铃」。
/// 本类只保留通知插件初始化与权限申请，并作为业务侧统一入口。
class FeedNotifications {
  static const String _feedingTag = 'feeding';
  static const String _careTag = 'care';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _ready = false;

  static AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  static Future<void> init() async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_feed'),
      ),
    );
    try {
      // 清理旧版本经本地通知调度的提醒，统一改由系统闹钟处理，避免重复响铃。
      await _plugin.cancelAll();
    } on Object catch (error) {
      debugPrint('清理旧提醒失败: $error');
    }
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

  /// 调度一条喂奶提醒闹钟。
  static Future<void> schedule({
    required int id,
    required int atMs,
    required String body,
  }) async {
    await init();
    if (atMs <= DateTime.now().millisecondsSinceEpoch) return;
    await AlarmScheduler.schedule(
      id: id,
      atMs: atMs,
      title: '该喂奶了',
      body: body,
      tag: _feedingTag,
    );
  }

  /// 调度一条儿保 / 疫苗接种提醒闹钟。
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
    return AlarmScheduler.schedule(
      id: id,
      atMs: atMs,
      title: title,
      body: body,
      tag: _careTag,
    );
  }

  /// 按 id 取消一条儿保 / 疫苗提醒。
  static Future<void> cancelCare(int id) async {
    await init();
    await AlarmScheduler.cancel(id);
  }

  /// 取消所有喂奶相关闹钟，但保留已调度的儿保 / 疫苗提醒。
  static Future<void> cancelAll() async {
    await init();
    await AlarmScheduler.cancelTagged(_feedingTag);
  }
}
