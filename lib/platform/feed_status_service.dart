import 'package:flutter/services.dart';

/// 常驻状态栏通知，由原生前台服务每分钟刷新一次倒计时。
class FeedStatusService {
  static const MethodChannel _channel = MethodChannel('yuying/feed_status');

  static Future<void> show({
    required int? lastFeedMs,
    required int? nextFeedMs,
  }) async {
    try {
      await _channel.invokeMethod<void>('start', {
        'lastFeedMs': lastFeedMs,
        'nextFeedMs': nextFeedMs,
      });
    } on PlatformException {
      // Android 12+ 后台限制下启动前台服务可能被拒绝，忽略即可。
    } on MissingPluginException {
      // 非 Android 平台不提供状态栏通知。
    }
  }

  static Future<void> hide() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // 忽略
    } on MissingPluginException {
      // 忽略
    }
  }
}
