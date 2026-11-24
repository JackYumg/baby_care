import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 系统闹钟调度。
///
/// 到点后由 Android 前台服务循环播放手机自带的闹钟铃声，
/// 用户点击通知「停止响铃」或响铃满 5 分钟后自动结束。
class AlarmScheduler {
  static const MethodChannel _channel = MethodChannel('yuying/alarm');

  /// 写入一条系统闹钟；时间已过或平台不可用时返回 false。
  ///
  /// [tag] 用于按业务分组批量取消，例如 `feeding` / `care`。
  static Future<bool> schedule({
    required int id,
    required int atMs,
    required String title,
    required String body,
    String tag = '',
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>('schedule', {
        'id': id,
        'atMs': atMs,
        'title': title,
        'body': body,
        'tag': tag,
      });
      return ok ?? false;
    } on MissingPluginException {
      debugPrint('系统闹钟不可用：当前平台未实现 yuying/alarm');
      return false;
    } on PlatformException catch (error) {
      debugPrint('系统闹钟调度失败: ${error.message}');
      return false;
    }
  }

  static Future<void> cancel(int id) async {
    try {
      await _channel.invokeMethod<void>('cancel', {'id': id});
    } on Object catch (error) {
      debugPrint('取消系统闹钟失败: $error');
    }
  }

  static Future<void> cancelAll() async {
    try {
      await _channel.invokeMethod<void>('cancelAll');
    } on Object catch (error) {
      debugPrint('取消全部系统闹钟失败: $error');
    }
  }

  /// 按业务分组取消，例如只清理喂奶提醒而保留儿保提醒。
  static Future<void> cancelTagged(String tag) async {
    try {
      await _channel.invokeMethod<void>('cancelTagged', {'tag': tag});
    } on Object catch (error) {
      debugPrint('取消 $tag 分组系统闹钟失败: $error');
    }
  }

  /// 立即停止正在播放的闹钟铃声（用户打开 App 时调用）。
  static Future<void> stopRinging() async {
    try {
      await _channel.invokeMethod<void>('stopRinging');
    } on Object catch (_) {
      // 没有在响铃时调用会静默失败，无需处理。
    }
  }
}
