enum FeedMode { bottle, direct }

enum MilkType { breastMilk, formula }

enum BreastSide { left, right }

enum StoolColor { yellow, green, brown, black, other }

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
  });

  final String id;
  final String babyId;
  final int occurredAt;
  final StoolColor? color;
  final String? consistency;
  final String? note;
  final int createdAt;
  final int updatedAt;

  Map<String, Object?> toMap() => {
    'id': id,
    'baby_id': babyId,
    'occurred_at': occurredAt,
    'color': color?.name,
    'consistency': consistency,
    'note': note,
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
