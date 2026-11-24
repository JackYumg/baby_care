import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../data/backup_service.dart';
import '../data/repositories.dart';
import '../domain/care_schedule.dart';
import '../domain/daily_statistics.dart';
import '../domain/feeding_reminder.dart';
import '../domain/models.dart';
import '../domain/time_rules.dart';
import '../platform/feed_notifications.dart';
import '../platform/feed_status_service.dart';
import '../platform/image_store.dart';

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
      growthRepo = GrowthRepository(db),
      checkupRepo = CheckupRepository(db),
      vaccineRepo = VaccineRepository(db),
      settingsRepo = SettingsRepository(db),
      backupService = BackupService(db);

  final Database db;
  final BabyRepository babyRepo;
  final RecordRepository recordRepo;
  final GrowthRepository growthRepo;
  final CheckupRepository checkupRepo;
  final VaccineRepository vaccineRepo;
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
  List<GrowthRecord> growthRecords = const [];
  List<CheckupPlan> checkups = const [];
  List<VaccineRecord> vaccines = const [];
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
      growthRecords = const [];
      checkups = const [];
      vaccines = const [];
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
    growthRecords = await growthRepo.listByBaby(baby.id);
    checkups = await checkupRepo.listByBaby(baby.id);
    vaccines = await vaccineRepo.listByBaby(baby.id);
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
    final imagePaths = <String>[
      ...await recordRepo.stoolImagePaths(babyId: babyId),
      ...await checkupRepo.imagePaths(babyId: babyId),
    ];
    await babyRepo.delete(babyId);
    for (final path in imagePaths) {
      await _deleteImage(path);
    }
    babies = await babyRepo.list();
    if (currentBaby?.id == babyId) {
      currentBaby = babies.isEmpty ? null : babies.first;
      if (currentBaby != null) {
        await settingsRepo.set(_currentBabyKey, currentBaby!.id);
      }
    }
    await refresh();
    await _pruneImages();
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
    String? imagePath,
  }) async {
    final baby = currentBaby;
    if (baby == null) return;
    await recordRepo.insertStool(
      babyId: baby.id,
      occurredAt: occurredAt,
      color: color,
      consistency: consistency,
      note: note,
      imagePath: imagePath,
    );
    await refresh();
  }

  Future<void> updateStool({
    required String id,
    required int occurredAt,
    StoolColor? color,
    String? consistency,
    String? note,
    String? imagePath,
  }) async {
    final oldImagePath = (await recordRepo.stoolById(id))?.imagePath;
    await recordRepo.updateStool(
      id: id,
      occurredAt: occurredAt,
      color: color,
      consistency: consistency,
      note: note,
      imagePath: imagePath,
    );
    if (oldImagePath != null && oldImagePath != imagePath) {
      await _deleteImage(oldImagePath);
    }
    await refresh();
  }

  Future<void> deleteStool(String id) async {
    final imagePath = (await recordRepo.stoolById(id))?.imagePath;
    await recordRepo.deleteStool(id);
    if (imagePath != null) {
      await _deleteImage(imagePath);
    }
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

  // ---------- 生长记录 ----------

  Future<void> addGrowth({
    required int measuredAt,
    double? heightCm,
    double? weightKg,
    double? headCm,
    String? note,
  }) async {
    final baby = currentBaby;
    if (baby == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await growthRepo.insert(
      GrowthRecord(
        id: const Uuid().v4(),
        babyId: baby.id,
        measuredAt: measuredAt,
        heightCm: heightCm,
        weightKg: weightKg,
        headCm: headCm,
        note: note,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await refresh();
  }

  Future<void> updateGrowth({
    required String id,
    required int measuredAt,
    double? heightCm,
    double? weightKg,
    double? headCm,
    String? note,
  }) async {
    final existing = _growthById(id);
    if (existing == null) return;
    await growthRepo.update(
      existing.copyWith(
        measuredAt: measuredAt,
        heightCm: heightCm,
        weightKg: weightKg,
        headCm: headCm,
        note: note,
      ),
    );
    await refresh();
  }

  Future<void> deleteGrowth(String id) async {
    await growthRepo.delete(id);
    await refresh();
  }

  // ---------- 儿保 ----------

  Future<void> addCheckup({
    required String title,
    required int scheduledAt,
    List<String> items = const [],
    String? note,
  }) async {
    final baby = currentBaby;
    if (baby == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await checkupRepo.insert(
      CheckupPlan(
        id: const Uuid().v4(),
        babyId: baby.id,
        title: title.trim(),
        scheduledAt: scheduledAt,
        items: [for (final label in items) CheckupItem(label: label)],
        note: note,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await refresh();
  }

  /// 修改儿保内容与计划日期，已完成 / 已跳过状态保持不变。
  Future<void> updateCheckup({
    required String id,
    String? title,
    int? scheduledAt,
    List<CheckupItem>? items,
    String? note,
  }) async {
    final existing = _checkupById(id);
    if (existing == null) return;
    await checkupRepo.update(
      existing.copyWith(
        title: title,
        scheduledAt: scheduledAt,
        items: items,
        note: note,
      ),
    );
    await refresh();
  }

  Future<void> completeCheckup({
    required String id,
    List<CheckupItem>? items,
    String? note,
    String? imagePath,
    int? completedAt,
  }) async {
    final existing = _checkupById(id);
    if (existing == null) return;
    final oldImagePath = existing.imagePath;
    await checkupRepo.update(
      existing.copyWith(
        items: items,
        note: note,
        imagePath: imagePath,
        status: CareTaskStatus.done,
        completedAt: completedAt ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (oldImagePath != null && oldImagePath != imagePath) {
      await _deleteImage(oldImagePath);
    }
    await refresh();
  }

  Future<void> skipCheckup(String id) async {
    final existing = _checkupById(id);
    if (existing == null) return;
    await checkupRepo.update(
      existing.copyWith(status: CareTaskStatus.skipped),
    );
    await refresh();
  }

  Future<void> deleteCheckup(String id) async {
    final imagePath = _checkupById(id)?.imagePath;
    await checkupRepo.delete(id);
    if (imagePath != null) {
      await _deleteImage(imagePath);
    }
    await refresh();
  }

  // ---------- 疫苗 ----------

  Future<void> addVaccine({
    required String name,
    required int scheduledAt,
    int dose = 1,
    String? note,
  }) async {
    final baby = currentBaby;
    if (baby == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await vaccineRepo.insert(
      VaccineRecord(
        id: const Uuid().v4(),
        babyId: baby.id,
        name: name.trim(),
        dose: dose,
        scheduledAt: scheduledAt,
        note: note,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await refresh();
  }

  /// 修改疫苗名称、剂次与计划日期，接种 / 跳过状态保持不变。
  Future<void> updateVaccine({
    required String id,
    String? name,
    int? dose,
    int? scheduledAt,
    String? note,
  }) async {
    final existing = _vaccineById(id);
    if (existing == null) return;
    await vaccineRepo.update(
      existing.copyWith(
        name: name,
        dose: dose,
        scheduledAt: scheduledAt,
        note: note,
      ),
    );
    await refresh();
  }

  Future<void> markVaccineDone({
    required String id,
    int? administeredAt,
    bool fever = false,
    double? temperature,
    String? note,
  }) async {
    final existing = _vaccineById(id);
    if (existing == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await vaccineRepo.update(
      VaccineRecord(
        id: existing.id,
        babyId: existing.babyId,
        name: existing.name,
        dose: existing.dose,
        scheduledAt: existing.scheduledAt,
        status: CareTaskStatus.done,
        administeredAt: administeredAt ?? now,
        fever: fever,
        temperature: fever ? temperature : null,
        note: note ?? existing.note,
        createdAt: existing.createdAt,
        updatedAt: now,
      ),
    );
    await refresh();
  }

  Future<void> skipVaccine(String id) async {
    final existing = _vaccineById(id);
    if (existing == null) return;
    await vaccineRepo.update(
      existing.copyWith(status: CareTaskStatus.skipped),
    );
    await refresh();
  }

  Future<void> deleteVaccine(String id) async {
    await vaccineRepo.delete(id);
    await refresh();
  }

  // ---------- 默认计划 ----------

  /// 按出生日期补齐默认儿保与疫苗计划，返回新增数量。
  ///
  /// 以「类型 + 名称 + 剂次」为唯一键，已存在的项（含改期、已完成、已跳过）
  /// 一律不覆盖。
  Future<int> generateDefaultCareSchedule() async {
    final baby = currentBaby;
    if (baby == null) return 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    var added = 0;

    final checkupTitles = {for (final plan in checkups) plan.title};
    for (final draft in generateCheckupDrafts(baby.birthDate)) {
      if (!checkupTitles.add(draft.title)) continue;
      await checkupRepo.insert(
        CheckupPlan(
          id: const Uuid().v4(),
          babyId: baby.id,
          title: draft.title,
          scheduledAt: draft.scheduledAt,
          items: draft.items,
          createdAt: now,
          updatedAt: now,
        ),
      );
      added++;
    }

    final vaccineKeys = {
      for (final record in vaccines) _vaccineKey(record.name, record.dose),
    };
    for (final draft in generateVaccineDrafts(baby.birthDate)) {
      if (!vaccineKeys.add(_vaccineKey(draft.name, draft.dose))) continue;
      await vaccineRepo.insert(
        VaccineRecord(
          id: const Uuid().v4(),
          babyId: baby.id,
          name: draft.name,
          dose: draft.dose,
          scheduledAt: draft.scheduledAt,
          createdAt: now,
          updatedAt: now,
        ),
      );
      added++;
    }

    await refresh();
    return added;
  }

  static String _vaccineKey(String name, int dose) => '$name|$dose';

  GrowthRecord? _growthById(String id) {
    for (final record in growthRecords) {
      if (record.id == id) return record;
    }
    return null;
  }

  CheckupPlan? _checkupById(String id) {
    for (final plan in checkups) {
      if (plan.id == id) return plan;
    }
    return null;
  }

  VaccineRecord? _vaccineById(String id) {
    for (final record in vaccines) {
      if (record.id == id) return record;
    }
    return null;
  }

  /// 删除图片文件；失败不影响记录本身的删除。
  Future<void> _deleteImage(String relativePath) async {
    try {
      await ImageStore.delete(relativePath);
    } catch (_) {
      // 图片文件不可用时忽略，避免阻断数据操作。
    }
  }

  /// 清理没有被任何记录引用的图片。
  Future<void> _pruneImages() async {
    try {
      final keep = <String>{
        ...await recordRepo.stoolImagePaths(),
        ...await checkupRepo.imagePaths(),
      };
      await ImageStore.pruneOrphans(keep);
    } catch (_) {
      // 图片清理失败不影响主流程。
    }
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
