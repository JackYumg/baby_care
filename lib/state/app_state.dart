import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../data/backup_service.dart';
import '../data/repositories.dart';
import '../domain/daily_statistics.dart';
import '../domain/feeding_reminder.dart';
import '../domain/models.dart';
import '../domain/time_rules.dart';
import '../platform/feed_notifications.dart';
import '../platform/feed_status_service.dart';

enum TimelineKind { feeding, sleep, stool }

class TimelineEntry {
  const TimelineEntry({
    required this.timeMs,
    required this.kind,
    this.feeding,
    this.segments = const [],
    this.sleep,
    this.stool,
  });

  final int timeMs;
  final TimelineKind kind;
  final FeedingRecord? feeding;
  final List<FeedingSegment> segments;
  final SleepRecord? sleep;
  final StoolRecord? stool;
}

class AppState extends ChangeNotifier {
  AppState(this.db)
    : babyRepo = BabyRepository(db),
      recordRepo = RecordRepository(db),
      settingsRepo = SettingsRepository(db),
      backupService = BackupService(db);

  final Database db;
  final BabyRepository babyRepo;
  final RecordRepository recordRepo;
  final SettingsRepository settingsRepo;
  final BackupService backupService;

  static const _currentBabyKey = 'current_baby_id';
  static const _reminderEnabledKey = 'feed_reminder_enabled';
  static const _statusEnabledKey = 'feed_status_enabled';

  List<Baby> babies = const [];
  Baby? currentBaby;
  DateTime selectedDate = todayStatDate();
  DailySummary summary = DailySummary.empty;
  List<TimelineEntry> timeline = const [];
  SleepRecord? ongoingSleep;
  ActiveFeeding? activeFeeding;
  List<FeedingSegment> activeSegments = const [];
  int nowMs = DateTime.now().millisecondsSinceEpoch;
  int dataVersion = 0;
  bool initialized = false;

  /// 是否在预估的下次喂奶时间发送闹钟通知。
  bool feedReminderEnabled = true;

  /// 是否在状态栏/锁屏常驻展示喝奶状态。
  bool feedStatusEnabled = true;

  /// 最近一次喂奶结束时间（UTC 毫秒）。
  int? lastFeedingMs;

  /// 当前记录的提醒时间（UTC 毫秒）。
  int? nextReminderMs;

  List<FeedingRecord> _feedings = const [];
  Map<String, List<FeedingSegment>> _segments = const {};
  List<SleepRecord> _sleeps = const [];
  List<StoolRecord> _stools = const [];
  Timer? _ticker;

  bool get isToday => selectedDate == todayStatDate();

  bool get hasActiveTimer => ongoingSleep != null || activeFeeding != null;

  Future<void> init() async {
    nowMs = DateTime.now().millisecondsSinceEpoch;
    babies = await babyRepo.list();
    final savedId = await settingsRepo.get(_currentBabyKey);
    currentBaby = _findBaby(savedId) ?? (babies.isEmpty ? null : babies.first);
    if (currentBaby != null) {
      await settingsRepo.set(_currentBabyKey, currentBaby!.id);
    }
    feedReminderEnabled = (await settingsRepo.get(_reminderEnabledKey)) != '0';
    feedStatusEnabled = (await settingsRepo.get(_statusEnabledKey)) != '0';
    await refresh();
    await _syncFeedSystem();
    initialized = true;
    notifyListeners();
  }

  Future<void> setFeedReminderEnabled(bool value) async {
    feedReminderEnabled = value;
    await settingsRepo.set(_reminderEnabledKey, value ? '1' : '0');
    if (value) await FeedNotifications.requestPermissions();
    await _syncFeedSystem();
    notifyListeners();
  }

  Future<void> setFeedStatusEnabled(bool value) async {
    feedStatusEnabled = value;
    await settingsRepo.set(_statusEnabledKey, value ? '1' : '0');
    if (value) await FeedNotifications.requestPermissions();
    await _syncFeedSystem();
    notifyListeners();
  }

  /// 读取最近一次喂奶并同步闹钟提醒与常驻状态栏。
  Future<void> _syncFeedSystem() async {
    final baby = currentBaby;
    final latest = baby == null
        ? null
        : await recordRepo.latestFeeding(baby.id);
    lastFeedingMs = latest?.endedAt ?? latest?.startedAt;
    nextReminderMs = latest?.remindAt;
    final now = DateTime.now().millisecondsSinceEpoch;

    if ((feedStatusEnabled && lastFeedingMs != null) || feedReminderEnabled) {
      await FeedNotifications.requestPermissionsOnce();
    }

    if (feedStatusEnabled && lastFeedingMs != null) {
      await FeedStatusService.show(
        lastFeedMs: lastFeedingMs,
        nextFeedMs: nextReminderMs,
      );
    } else {
      await FeedStatusService.hide();
    }

    await FeedNotifications.cancelAll();
    if (feedReminderEnabled &&
        latest != null &&
        nextReminderMs != null &&
        nextReminderMs! > now) {
      await FeedNotifications.schedule(
        id: _notificationId(latest.id),
        atMs: nextReminderMs!,
        body: '上次 ${formatClock(lastFeedingMs!)} 喝奶，该喂奶了',
      );
    }
    notifyListeners();
  }

  static int _notificationId(String feedingId) {
    final id = feedingId.hashCode.abs() % 0x7ffffffe;
    return id == 0 ? 1 : id;
  }

  Baby? _findBaby(String? id) {
    if (id == null) return null;
    for (final baby in babies) {
      if (baby.id == id) return baby;
    }
    return null;
  }

  Future<void> refresh() async {
    nowMs = DateTime.now().millisecondsSinceEpoch;
    final baby = currentBaby;
    if (baby == null) {
      summary = DailySummary.empty;
      timeline = const [];
      ongoingSleep = null;
      activeFeeding = null;
      _stopTicker();
      notifyListeners();
      return;
    }
    final start = dayStartMs(selectedDate);
    final end = dayEndMs(selectedDate);
    _feedings = await recordRepo.feedingsOverlapping(baby.id, start, end);
    _segments = await recordRepo.segmentsFor(
      _feedings.map((e) => e.id).toList(),
    );
    _sleeps = await recordRepo.sleepsOverlapping(baby.id, start, end);
    _stools = await recordRepo.stoolsBetween(baby.id, start, end);
    ongoingSleep = await recordRepo.ongoingSleep(baby.id);
    activeFeeding = await recordRepo.activeFeeding(baby.id);
    if (activeFeeding != null) {
      final all = await recordRepo.segmentsFor([activeFeeding!.feedingId]);
      activeSegments = all[activeFeeding!.feedingId] ?? const [];
    } else {
      activeSegments = const [];
    }
    _recompute();
    _syncTicker();
    dataVersion++;
    notifyListeners();
  }

  void _recompute() {
    summary = computeDailySummary(
      statDate: selectedDate,
      feedings: _feedings,
      segmentsByFeeding: _segments,
      sleeps: _sleeps,
      stools: _stools,
      nowMs: nowMs,
    );
    final entries = <TimelineEntry>[
      for (final feeding in _feedings)
        if (feeding.endedAt != null || feeding.mode == FeedMode.bottle)
          TimelineEntry(
            timeMs: feeding.startedAt,
            kind: TimelineKind.feeding,
            feeding: feeding,
            segments: _segments[feeding.id] ?? const [],
          ),
      for (final sleep in _sleeps)
        TimelineEntry(
          timeMs: sleep.startedAt,
          kind: TimelineKind.sleep,
          sleep: sleep,
        ),
      for (final stool in _stools)
        TimelineEntry(
          timeMs: stool.occurredAt,
          kind: TimelineKind.stool,
          stool: stool,
        ),
    ];
    entries.sort((a, b) => b.timeMs.compareTo(a.timeMs));
    timeline = entries;
  }

  void _syncTicker() {
    if (hasActiveTimer && isToday) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        nowMs = DateTime.now().millisecondsSinceEpoch;
        _recompute();
        notifyListeners();
      });
    } else {
      _stopTicker();
    }
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  Future<void> selectBaby(String babyId) async {
    final baby = _findBaby(babyId);
    if (baby == null || baby.id == currentBaby?.id) return;
    currentBaby = baby;
    await settingsRepo.set(_currentBabyKey, baby.id);
    selectedDate = todayStatDate();
    await refresh();
    await _syncFeedSystem();
  }

  Future<void> selectDate(DateTime date) async {
    final normalized = DateTime.utc(date.year, date.month, date.day);
    if (normalized == selectedDate) return;
    selectedDate = normalized;
    await refresh();
  }

  // ---------- 宝宝 ----------

  Future<Baby> createBaby({
    required String nickname,
    required DateTime birthDate,
    String? sex,
    String avatarKey = 'default',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final baby = Baby(
      id: const Uuid().v4(),
      nickname: nickname.trim(),
      birthDate: DateTime(birthDate.year, birthDate.month, birthDate.day),
      sex: sex,
      avatarKey: avatarKey,
      createdAt: now,
      updatedAt: now,
    );
    await babyRepo.insert(baby);
    babies = await babyRepo.list();
    currentBaby = baby;
    await settingsRepo.set(_currentBabyKey, baby.id);
    selectedDate = todayStatDate();
    await refresh();
    return baby;
  }

  Future<void> updateBaby(Baby baby) async {
    await babyRepo.update(baby);
    babies = await babyRepo.list();
    if (currentBaby?.id == baby.id) {
      currentBaby = _findBaby(baby.id);
    }
    await refresh();
  }

  Future<void> deleteBaby(String babyId) async {
    await babyRepo.delete(babyId);
    babies = await babyRepo.list();
    if (currentBaby?.id == babyId) {
      currentBaby = babies.isEmpty ? null : babies.first;
      if (currentBaby != null) {
        await settingsRepo.set(_currentBabyKey, currentBaby!.id);
      }
    }
    await refresh();
  }

  // ---------- 喝奶 ----------

  Future<void> addBottleFeeding({
    required int startedAt,
    required int amountMl,
    required MilkType milkType,
    String? note,
    int? remindAt,
  }) async {
    final baby = currentBaby;
    if (baby == null) return;
    await recordRepo.insertBottleFeeding(
      babyId: baby.id,
      startedAt: startedAt,
      amountMl: amountMl,
      milkType: milkType,
      note: note,
      remindAt: remindAt,
    );
    await refresh();
    await _syncFeedSystem();
  }

  Future<void> updateBottleFeeding({
    required String id,
    required int startedAt,
    required int amountMl,
    required MilkType milkType,
    String? note,
    int? remindAt,
  }) async {
    await recordRepo.updateBottleFeeding(
      id: id,
      startedAt: startedAt,
      amountMl: amountMl,
      milkType: milkType,
      note: note,
      remindAt: remindAt,
    );
    await refresh();
    await _syncFeedSystem();
  }

  Future<void> addManualDirectFeeding({
    required int startedAt,
    required int leftMinutes,
    required int rightMinutes,
    String? note,
  }) async {
    final baby = currentBaby;
    if (baby == null) return;
    final feedingId = await recordRepo.insertManualDirectFeeding(
      babyId: baby.id,
      startedAt: startedAt,
      leftMinutes: leftMinutes,
      rightMinutes: rightMinutes,
      note: note,
    );
    final endedAt = startedAt + (leftMinutes + rightMinutes) * 60 * 1000;
    await recordRepo.setFeedingRemindAt(
      feedingId,
      endedAt + kDefaultDirectRemindMinutes * 60 * 1000,
    );
    await refresh();
    await _syncFeedSystem();
  }

  Future<void> deleteFeeding(String id) async {
    await recordRepo.deleteFeeding(id);
    await refresh();
    await _syncFeedSystem();
  }

  Future<void> startDirectFeeding() async {
    final baby = currentBaby;
    if (baby == null) return;
    await recordRepo.startDirectFeeding(
      baby.id,
      DateTime.now().millisecondsSinceEpoch,
    );
    await refresh();
  }

  Future<void> switchDirectSide(BreastSide side) async {
    final baby = currentBaby;
    if (baby == null) return;
    await recordRepo.switchDirectSide(
      baby.id,
      side,
      DateTime.now().millisecondsSinceEpoch,
    );
    await refresh();
  }

  Future<void> pauseDirectFeeding() async {
    final baby = currentBaby;
    if (baby == null) return;
    await recordRepo.pauseDirectFeeding(
      baby.id,
      DateTime.now().millisecondsSinceEpoch,
    );
    await refresh();
  }

  Future<void> resumeDirectFeeding(BreastSide side) async {
    final baby = currentBaby;
    if (baby == null) return;
    await recordRepo.resumeDirectFeeding(
      baby.id,
      side,
      DateTime.now().millisecondsSinceEpoch,
    );
    await refresh();
  }

  Future<void> finishDirectFeeding() async {
    final baby = currentBaby;
    if (baby == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final feedingId = await recordRepo.finishDirectFeeding(baby.id, now);
    await recordRepo.setFeedingRemindAt(
      feedingId,
      now + kDefaultDirectRemindMinutes * 60 * 1000,
    );
    await refresh();
    await _syncFeedSystem();
  }

  Future<void> discardDirectFeeding() async {
    final baby = currentBaby;
    if (baby == null) return;
    await recordRepo.discardDirectFeeding(baby.id);
    await refresh();
    await _syncFeedSystem();
  }

  int activeSideSeconds(BreastSide side) {
    return activeSegments
        .where((s) => s.side == side)
        .fold(0, (sum, s) => sum + s.seconds);
  }

  // ---------- 排便 ----------

  Future<void> addStool({
    required int occurredAt,
    StoolColor? color,
    String? consistency,
    String? note,
  }) async {
    final baby = currentBaby;
    if (baby == null) return;
    await recordRepo.insertStool(
      babyId: baby.id,
      occurredAt: occurredAt,
      color: color,
      consistency: consistency,
      note: note,
    );
    await refresh();
  }

  Future<void> updateStool({
    required String id,
    required int occurredAt,
    StoolColor? color,
    String? consistency,
    String? note,
  }) async {
    await recordRepo.updateStool(
      id: id,
      occurredAt: occurredAt,
      color: color,
      consistency: consistency,
      note: note,
    );
    await refresh();
  }

  Future<void> deleteStool(String id) async {
    await recordRepo.deleteStool(id);
    await refresh();
  }

  // ---------- 睡眠 ----------

  Future<void> startSleep() async {
    final baby = currentBaby;
    if (baby == null) return;
    await recordRepo.startSleep(baby.id, DateTime.now().millisecondsSinceEpoch);
    await refresh();
  }

  Future<void> endSleep(String id) async {
    await recordRepo.endSleep(id, DateTime.now().millisecondsSinceEpoch);
    await refresh();
  }

  Future<void> addManualSleep({
    required int startedAt,
    required int endedAt,
    String? note,
  }) async {
    final baby = currentBaby;
    if (baby == null) return;
    await recordRepo.insertManualSleep(
      babyId: baby.id,
      startedAt: startedAt,
      endedAt: endedAt,
      note: note,
    );
    await refresh();
  }

  Future<void> updateSleep({
    required String id,
    required int startedAt,
    required int endedAt,
    String? note,
  }) async {
    final baby = currentBaby;
    if (baby == null) return;
    await recordRepo.updateSleep(
      id: id,
      babyId: baby.id,
      startedAt: startedAt,
      endedAt: endedAt,
      note: note,
    );
    await refresh();
  }

  Future<void> deleteSleep(String id) async {
    await recordRepo.deleteSleep(id);
    await refresh();
  }

  // ---------- 统计 ----------

  Future<TrendSeries> loadTrend({int days = 7}) async {
    final baby = currentBaby;
    if (baby == null) {
      return TrendSeries(
        dates: List.generate(days, (i) => addDays(selectedDate, i - days + 1)),
        bottleMl: List.filled(days, 0),
        sleepMinutes: List.filled(days, 0),
        stoolCounts: List.filled(days, 0),
      );
    }
    final start = dayStartMs(addDays(selectedDate, -(days - 1)));
    final end = dayEndMs(selectedDate);
    final feedings = await recordRepo.feedingsOverlapping(baby.id, start, end);
    final segments = await recordRepo.segmentsFor(
      feedings.map((e) => e.id).toList(),
    );
    final sleeps = await recordRepo.sleepsOverlapping(baby.id, start, end);
    final stools = await recordRepo.stoolsBetween(baby.id, start, end);
    return computeTrend(
      endDate: selectedDate,
      days: days,
      feedings: feedings,
      segmentsByFeeding: segments,
      sleeps: sleeps,
      stools: stools,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  // ---------- 备份 ----------

  Future<String> exportBackupJson() => backupService.exportJson();

  Future<BackupPayload> parseBackup(String json) async =>
      backupService.parseAndValidate(json);

  Future<void> restoreBackup(BackupPayload payload) async {
    await backupService.restore(payload);
    babies = await babyRepo.list();
    final savedId = await settingsRepo.get(_currentBabyKey);
    currentBaby = _findBaby(savedId) ?? (babies.isEmpty ? null : babies.first);
    if (currentBaby != null) {
      await settingsRepo.set(_currentBabyKey, currentBaby!.id);
    }
    await refresh();
    await _syncFeedSystem();
  }

  @override
  void dispose() {
    _stopTicker();
    super.dispose();
  }
}
