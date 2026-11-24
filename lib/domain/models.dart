import 'dart:convert';

enum FeedMode { bottle, direct }

enum MilkType { breastMilk, formula }

enum BreastSide { left, right }

enum StoolColor { yellow, green, brown, black, other }

/// 待办（儿保 / 疫苗）状态。
enum CareTaskStatus { pending, done, skipped }

class Baby {
  const Baby({
    required this.id,
    required this.nickname,
    required this.birthDate,
    required this.createdAt,
    required this.updatedAt,
    this.sex,
    this.avatarKey = 'default',
  });

  final String id;
  final String nickname;
  final DateTime birthDate;
  final String? sex;
  final String avatarKey;
  final int createdAt;
  final int updatedAt;

  Map<String, Object?> toMap() => {
    'id': id,
    'nickname': nickname,
    'birth_date': birthDate.millisecondsSinceEpoch,
    'sex': sex,
    'avatar_key': avatarKey,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  factory Baby.fromMap(Map<String, Object?> map) => Baby(
    id: map['id']! as String,
    nickname: map['nickname']! as String,
    birthDate: DateTime.fromMillisecondsSinceEpoch(map['birth_date']! as int),
    sex: map['sex'] as String?,
    avatarKey: (map['avatar_key'] as String?) ?? 'default',
    createdAt: map['created_at']! as int,
    updatedAt: map['updated_at']! as int,
  );

  Baby copyWith({
    String? nickname,
    DateTime? birthDate,
    String? sex,
    String? avatarKey,
  }) => Baby(
    id: id,
    nickname: nickname ?? this.nickname,
    birthDate: birthDate ?? this.birthDate,
    sex: sex ?? this.sex,
    avatarKey: avatarKey ?? this.avatarKey,
    createdAt: createdAt,
    updatedAt: DateTime.now().millisecondsSinceEpoch,
  );
}

class FeedingRecord {
  const FeedingRecord({
    required this.id,
    required this.babyId,
    required this.mode,
    required this.startedAt,
    required this.createdAt,
    required this.updatedAt,
    this.endedAt,
    this.amountMl,
    this.milkType,
    this.note,
    this.remindAt,
  });

  final String id;
  final String babyId;
  final FeedMode mode;
  final int startedAt;
  final int? endedAt;
  final int? amountMl;
  final MilkType? milkType;
  final String? note;

  /// 下次喂奶提醒时间（UTC 毫秒），为空表示未设置提醒。
  final int? remindAt;
  final int createdAt;
  final int updatedAt;

  bool get isDirect => mode == FeedMode.direct;

  Map<String, Object?> toMap() => {
    'id': id,
    'baby_id': babyId,
    'mode': mode.name,
    'started_at': startedAt,
    'ended_at': endedAt,
    'amount_ml': amountMl,
    'milk_type': milkType?.name,
    'note': note,
    'remind_at': remindAt,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  factory FeedingRecord.fromMap(Map<String, Object?> map) => FeedingRecord(
    id: map['id']! as String,
    babyId: map['baby_id']! as String,
    mode: FeedMode.values.firstWhere((e) => e.name == map['mode']),
    startedAt: map['started_at']! as int,
    endedAt: map['ended_at'] as int?,
    amountMl: map['amount_ml'] as int?,
    milkType: map['milk_type'] == null
        ? null
        : MilkType.values.firstWhere((e) => e.name == map['milk_type']),
    note: map['note'] as String?,
    remindAt: map['remind_at'] as int?,
    createdAt: map['created_at']! as int,
    updatedAt: map['updated_at']! as int,
  );
}

class FeedingSegment {
  const FeedingSegment({
    required this.id,
    required this.feedingId,
    required this.side,
    required this.startedAt,
    required this.endedAt,
  });

  final String id;
  final String feedingId;
  final BreastSide side;
  final int startedAt;
  final int endedAt;

  int get seconds => ((endedAt - startedAt) / 1000).round();

  Map<String, Object?> toMap() => {
    'id': id,
    'feeding_id': feedingId,
    'side': side.name,
    'started_at': startedAt,
    'ended_at': endedAt,
  };

  factory FeedingSegment.fromMap(Map<String, Object?> map) => FeedingSegment(
    id: map['id']! as String,
    feedingId: map['feeding_id']! as String,
    side: BreastSide.values.firstWhere((e) => e.name == map['side']),
    startedAt: map['started_at']! as int,
    endedAt: map['ended_at']! as int,
  );
}

class StoolRecord {
  const StoolRecord({
    required this.id,
    required this.babyId,
    required this.occurredAt,
    required this.createdAt,
    required this.updatedAt,
    this.color,
    this.consistency,
    this.note,
    this.imagePath,
  });

  final String id;
  final String babyId;
  final int occurredAt;
  final StoolColor? color;
  final String? consistency;
  final String? note;

  /// 图片相对路径（如 `stool/xxx.jpg`），为空表示未添加图片。
  final String? imagePath;
  final int createdAt;
  final int updatedAt;

  Map<String, Object?> toMap() => {
    'id': id,
    'baby_id': babyId,
    'occurred_at': occurredAt,
    'color': color?.name,
    'consistency': consistency,
    'note': note,
    'image_path': imagePath,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  factory StoolRecord.fromMap(Map<String, Object?> map) => StoolRecord(
    id: map['id']! as String,
    babyId: map['baby_id']! as String,
    occurredAt: map['occurred_at']! as int,
    color: map['color'] == null
        ? null
        : StoolColor.values.firstWhere((e) => e.name == map['color']),
    consistency: map['consistency'] as String?,
    note: map['note'] as String?,
    imagePath: map['image_path'] as String?,
    createdAt: map['created_at']! as int,
    updatedAt: map['updated_at']! as int,
  );
}

class SleepRecord {
  const SleepRecord({
    required this.id,
    required this.babyId,
    required this.startedAt,
    required this.createdAt,
    required this.updatedAt,
    this.endedAt,
    this.note,
  });

  final String id;
  final String babyId;
  final int startedAt;
  final int? endedAt;
  final String? note;
  final int createdAt;
  final int updatedAt;

  bool get isOngoing => endedAt == null;

  Map<String, Object?> toMap() => {
    'id': id,
    'baby_id': babyId,
    'started_at': startedAt,
    'ended_at': endedAt,
    'note': note,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  factory SleepRecord.fromMap(Map<String, Object?> map) => SleepRecord(
    id: map['id']! as String,
    babyId: map['baby_id']! as String,
    startedAt: map['started_at']! as int,
    endedAt: map['ended_at'] as int?,
    note: map['note'] as String?,
    createdAt: map['created_at']! as int,
    updatedAt: map['updated_at']! as int,
  );
}

class ActiveFeeding {
  const ActiveFeeding({
    required this.babyId,
    required this.feedingId,
    required this.startedAt,
    this.currentSide,
    this.activeSegmentId,
  });

  final String babyId;
  final String feedingId;
  final int startedAt;
  final BreastSide? currentSide;
  final String? activeSegmentId;

  bool get isPaused => currentSide == null;

  Map<String, Object?> toMap() => {
    'baby_id': babyId,
    'feeding_id': feedingId,
    'started_at': startedAt,
    'current_side': currentSide?.name,
    'active_segment_id': activeSegmentId,
  };

  factory ActiveFeeding.fromMap(Map<String, Object?> map) => ActiveFeeding(
    babyId: map['baby_id']! as String,
    feedingId: map['feeding_id']! as String,
    startedAt: map['started_at']! as int,
    currentSide: map['current_side'] == null
        ? null
        : BreastSide.values.firstWhere((e) => e.name == map['current_side']),
    activeSegmentId: map['active_segment_id'] as String?,
  );
}

class GrowthRecord {
  const GrowthRecord({
    required this.id,
    required this.babyId,
    required this.measuredAt,
    required this.createdAt,
    required this.updatedAt,
    this.heightCm,
    this.weightKg,
    this.headCm,
    this.note,
  });

  final String id;
  final String babyId;
  final int measuredAt;
  final double? heightCm;
  final double? weightKg;
  final double? headCm;
  final String? note;
  final int createdAt;
  final int updatedAt;

  Map<String, Object?> toMap() => {
    'id': id,
    'baby_id': babyId,
    'measured_at': measuredAt,
    'height_cm': heightCm,
    'weight_kg': weightKg,
    'head_cm': headCm,
    'note': note,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  factory GrowthRecord.fromMap(Map<String, Object?> map) => GrowthRecord(
    id: map['id']! as String,
    babyId: map['baby_id']! as String,
    measuredAt: map['measured_at']! as int,
    heightCm: (map['height_cm'] as num?)?.toDouble(),
    weightKg: (map['weight_kg'] as num?)?.toDouble(),
    headCm: (map['head_cm'] as num?)?.toDouble(),
    note: map['note'] as String?,
    createdAt: map['created_at']! as int,
    updatedAt: map['updated_at']! as int,
  );

  GrowthRecord copyWith({
    int? measuredAt,
    double? heightCm,
    double? weightKg,
    double? headCm,
    String? note,
  }) => GrowthRecord(
    id: id,
    babyId: babyId,
    measuredAt: measuredAt ?? this.measuredAt,
    heightCm: heightCm ?? this.heightCm,
    weightKg: weightKg ?? this.weightKg,
    headCm: headCm ?? this.headCm,
    note: note ?? this.note,
    createdAt: createdAt,
    updatedAt: DateTime.now().millisecondsSinceEpoch,
  );
}

/// 儿保检查项，`items` 在数据库中整体存为 JSON 字符串。
class CheckupItem {
  const CheckupItem({required this.label, this.done = false, this.result});

  final String label;
  final bool done;
  final String? result;

  Map<String, Object?> toMap() => {
    'label': label,
    'done': done,
    'result': result,
  };

  factory CheckupItem.fromMap(Map<String, Object?> map) => CheckupItem(
    label: map['label']! as String,
    done: (map['done'] as bool?) ?? false,
    result: map['result'] as String?,
  );

  CheckupItem copyWith({bool? done, String? result}) => CheckupItem(
    label: label,
    done: done ?? this.done,
    result: result ?? this.result,
  );
}

class CheckupPlan {
  const CheckupPlan({
    required this.id,
    required this.babyId,
    required this.title,
    required this.scheduledAt,
    required this.createdAt,
    required this.updatedAt,
    this.status = CareTaskStatus.pending,
    this.items = const [],
    this.note,
    this.imagePath,
    this.completedAt,
  });

  final String id;
  final String babyId;
  final String title;
  final int scheduledAt;
  final CareTaskStatus status;
  final List<CheckupItem> items;
  final String? note;

  /// 检查图片相对路径（如 `checkup/xxx.jpg`）。
  final String? imagePath;
  final int? completedAt;
  final int createdAt;
  final int updatedAt;

  Map<String, Object?> toMap() => {
    'id': id,
    'baby_id': babyId,
    'title': title,
    'scheduled_at': scheduledAt,
    'status': status.name,
    'items': jsonEncode([for (final item in items) item.toMap()]),
    'note': note,
    'image_path': imagePath,
    'completed_at': completedAt,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  factory CheckupPlan.fromMap(Map<String, Object?> map) => CheckupPlan(
    id: map['id']! as String,
    babyId: map['baby_id']! as String,
    title: map['title']! as String,
    scheduledAt: map['scheduled_at']! as int,
    status: CareTaskStatus.values.firstWhere(
      (e) => e.name == map['status'],
      orElse: () => CareTaskStatus.pending,
    ),
    items: _decodeCheckupItems(map['items']),
    note: map['note'] as String?,
    imagePath: map['image_path'] as String?,
    completedAt: map['completed_at'] as int?,
    createdAt: map['created_at']! as int,
    updatedAt: map['updated_at']! as int,
  );

  CheckupPlan copyWith({
    String? title,
    int? scheduledAt,
    CareTaskStatus? status,
    List<CheckupItem>? items,
    String? note,
    String? imagePath,
    int? completedAt,
  }) => CheckupPlan(
    id: id,
    babyId: babyId,
    title: title ?? this.title,
    scheduledAt: scheduledAt ?? this.scheduledAt,
    status: status ?? this.status,
    items: items ?? this.items,
    note: note ?? this.note,
    imagePath: imagePath ?? this.imagePath,
    completedAt: completedAt ?? this.completedAt,
    createdAt: createdAt,
    updatedAt: DateTime.now().millisecondsSinceEpoch,
  );
}

class VaccineRecord {
  const VaccineRecord({
    required this.id,
    required this.babyId,
    required this.name,
    required this.scheduledAt,
    required this.createdAt,
    required this.updatedAt,
    this.dose = 1,
    this.status = CareTaskStatus.pending,
    this.administeredAt,
    this.fever = false,
    this.temperature,
    this.note,
  });

  final String id;
  final String babyId;
  final String name;
  final int dose;
  final int scheduledAt;
  final CareTaskStatus status;
  final int? administeredAt;
  final bool fever;
  final double? temperature;
  final String? note;
  final int createdAt;
  final int updatedAt;

  Map<String, Object?> toMap() => {
    'id': id,
    'baby_id': babyId,
    'name': name,
    'dose': dose,
    'scheduled_at': scheduledAt,
    'status': status.name,
    'administered_at': administeredAt,
    'fever': fever ? 1 : 0,
    'temperature': temperature,
    'note': note,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  factory VaccineRecord.fromMap(Map<String, Object?> map) => VaccineRecord(
    id: map['id']! as String,
    babyId: map['baby_id']! as String,
    name: map['name']! as String,
    dose: (map['dose'] as int?) ?? 1,
    scheduledAt: map['scheduled_at']! as int,
    status: CareTaskStatus.values.firstWhere(
      (e) => e.name == map['status'],
      orElse: () => CareTaskStatus.pending,
    ),
    administeredAt: map['administered_at'] as int?,
    fever: ((map['fever'] as int?) ?? 0) != 0,
    temperature: (map['temperature'] as num?)?.toDouble(),
    note: map['note'] as String?,
    createdAt: map['created_at']! as int,
    updatedAt: map['updated_at']! as int,
  );

  VaccineRecord copyWith({
    String? name,
    int? dose,
    int? scheduledAt,
    CareTaskStatus? status,
    int? administeredAt,
    bool? fever,
    double? temperature,
    String? note,
  }) => VaccineRecord(
    id: id,
    babyId: babyId,
    name: name ?? this.name,
    dose: dose ?? this.dose,
    scheduledAt: scheduledAt ?? this.scheduledAt,
    status: status ?? this.status,
    administeredAt: administeredAt ?? this.administeredAt,
    fever: fever ?? this.fever,
    temperature: temperature ?? this.temperature,
    note: note ?? this.note,
    createdAt: createdAt,
    updatedAt: DateTime.now().millisecondsSinceEpoch,
  );
}

List<CheckupItem> _decodeCheckupItems(Object? raw) {
  if (raw is! String || raw.trim().isEmpty) return const [];
  final decoded = jsonDecode(raw);
  if (decoded is! List) return const [];
  return [
    for (final item in decoded)
      if (item is Map) CheckupItem.fromMap(Map<String, Object?>.from(item)),
  ];
}
