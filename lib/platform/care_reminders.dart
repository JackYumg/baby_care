import 'dart:convert';

import '../domain/models.dart';
import '../domain/time_rules.dart';
import '../state/app_state.dart';
import 'feed_notifications.dart';

/// 一条待提醒的儿保 / 疫苗待办。
class CareReminder {
  const CareReminder({
    required this.id,
    required this.babyNickname,
    required this.title,
    required this.scheduledAt,
    required this.isVaccine,
  });

  final String id;
  final String babyNickname;
  final String title;
  final int scheduledAt;
  final bool isVaccine;
}

/// 设置项：是否发送儿保 / 疫苗提醒（默认开启）。
const String kCareRemindersEnabledKey = 'care_reminders_enabled';

const String _scheduledIdsKey = 'care_reminder_scheduled_ids';
const String _reminderPayloadPrefix = 'task_';

/// 单次最多调度的通知数量，避免触发系统定时通知上限。
const int _maxScheduled = 64;

/// 按当前宝宝的待办状态重排儿保 / 疫苗通知。
///
/// 先取消上一次记录在 [SettingsRepository] 中的通知 id，再对未来待办
/// 按计划日 09:00 重新调度；失败时静默，不影响待办本身。
Future<void> syncCareReminders(AppState state) async {
  try {
    await _sync(state);
  } catch (_) {
    // 通知组件不可用时忽略，页面与数据不受影响。
  }
}

Future<void> _sync(AppState state) async {
  final enabled =
      (await state.settingsRepo.get(kCareRemindersEnabledKey)) != '0';
  final previous = await _scheduledIds(state);
  for (final id in previous) {
    await FeedNotifications.cancelCare(id);
  }

  final scheduled = <int>[];
  final baby = state.currentBaby;
  if (enabled && baby != null) {
    final reminders = <CareReminder>[
      for (final plan in state.checkups)
        if (plan.status == CareTaskStatus.pending)
          CareReminder(
            id: _reminderPayloadPrefix + plan.id,
            babyNickname: baby.nickname,
            title: plan.title,
            scheduledAt: plan.scheduledAt,
            isVaccine: false,
          ),
      for (final record in state.vaccines)
        if (record.status == CareTaskStatus.pending)
          CareReminder(
            id: _reminderPayloadPrefix + record.id,
            babyNickname: baby.nickname,
            title: '${record.name} 第 ${record.dose} 剂',
            scheduledAt: record.scheduledAt,
            isVaccine: true,
          ),
    ]..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

    if (reminders.isNotEmpty) {
      await FeedNotifications.requestPermissionsOnce();
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    for (final reminder in reminders) {
      if (scheduled.length >= _maxScheduled) break;
      final atMs = _reminderAt(reminder.scheduledAt);
      if (atMs <= now) continue;
      final id = _notificationId(reminder.id);
      final ok = await FeedNotifications.scheduleCare(
        id: id,
        atMs: atMs,
        title: reminder.isVaccine ? '今天有疫苗' : '今天有儿保',
        body: '${reminder.babyNickname} · ${reminder.title}，记得按时前往',
      );
      if (ok) scheduled.add(id);
    }
  }

  await state.settingsRepo.set(_scheduledIdsKey, jsonEncode(scheduled));
}

/// 计划日当天 09:00 的 UTC 毫秒。
int _reminderAt(int scheduledAt) {
  final (date, _, _) = splitStatDateTime(scheduledAt);
  return combineStatDateTime(date, 9, 0);
}

/// 稳定的 int 通知 id（FNV-1a），跨进程重启保持一致，便于精确取消。
int _notificationId(String key) {
  var hash = 0x811c9dc5;
  for (final unit in key.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash == 0 ? 1 : hash;
}

Future<List<int>> _scheduledIds(AppState state) async {
  final raw = await state.settingsRepo.get(_scheduledIdsKey);
  if (raw == null || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final id in decoded)
        if (id is int) id,
    ];
  } on FormatException {
    return const [];
  }
}
