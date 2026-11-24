import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../platform/image_store.dart';

/// 备份文件格式标识与版本。
const String kBackupFormat = 'yuying-backup';
const int kBackupVersion = 2;
const int kMaxBackupBytes = 60 * 1024 * 1024;

const Set<String> _careStatuses = {'pending', 'done', 'skipped'};

class BackupException implements Exception {
  BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BackupPayload {
  const BackupPayload({
    required this.exportedAt,
    required this.babies,
    required this.feedings,
    required this.segments,
    required this.stools,
    required this.sleeps,
    required this.activeSessions,
    required this.growths,
    required this.checkups,
    required this.vaccines,
    required this.settings,
    required this.attachments,
  });

  final int exportedAt;
  final List<Map<String, Object?>> babies;
  final List<Map<String, Object?>> feedings;
  final List<Map<String, Object?>> segments;
  final List<Map<String, Object?>> stools;
  final List<Map<String, Object?>> sleeps;
  final List<Map<String, Object?>> activeSessions;
  final List<Map<String, Object?>> growths;
  final List<Map<String, Object?>> checkups;
  final List<Map<String, Object?>> vaccines;
  final List<Map<String, Object?>> settings;

  /// 相对路径（如 `stool/xxx.jpg`）→ base64 图片内容。
  final Map<String, String> attachments;
}

class BackupService {
  BackupService(
    this.db, {
    Future<Map<String, String>> Function()? readAttachments,
    Future<void> Function(Map<String, String>)? writeAttachments,
    Future<void> Function(Set<String>)? pruneAttachments,
  }) : _readAttachments = readAttachments ?? ImageStore.readAllAsBase64,
       _writeAttachments = writeAttachments ?? ImageStore.restoreAllFromBase64,
       _pruneAttachments = pruneAttachments ?? ImageStore.pruneOrphans;

  final Database db;

  final Future<Map<String, String>> Function() _readAttachments;
  final Future<void> Function(Map<String, String>) _writeAttachments;
  final Future<void> Function(Set<String>) _pruneAttachments;

  static const _tables = [
    'babies',
    'feeding_records',
    'breastfeeding_segments',
    'stool_records',
    'sleep_records',
    'active_feeding_sessions',
    'growth_records',
    'checkup_plans',
    'vaccine_records',
    'app_settings',
  ];

  Future<String> exportJson({int? nowMs, int? maxBytes}) async {
    final snapshot = await db.transaction((txn) async {
      final data = <String, List<Map<String, Object?>>>{};
      for (final table in _tables) {
        data[table] = await txn.query(table);
      }
      return data;
    });
    final attachments = await _readAttachments();
    final exportedAt = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final payload = <String, Object?>{
      'format': kBackupFormat,
      'version': kBackupVersion,
      'exported_at': exportedAt,
      'timezone': 'Asia/Shanghai',
      'babies': snapshot['babies'],
      'feeding_records': snapshot['feeding_records'],
      'breastfeeding_segments': snapshot['breastfeeding_segments'],
      'stool_records': snapshot['stool_records'],
      'sleep_records': snapshot['sleep_records'],
      'active_feeding_sessions': snapshot['active_feeding_sessions'],
      'growth_records': snapshot['growth_records'],
      'checkup_plans': snapshot['checkup_plans'],
      'vaccine_records': snapshot['vaccine_records'],
      'app_settings': snapshot['app_settings'],
      'attachments': attachments,
    };
    final json = const JsonEncoder.withIndent('  ').convert(payload);
    if (utf8.encode(json).length > (maxBytes ?? kMaxBackupBytes)) {
      throw BackupException('备份内容超过 60MB，请先清理部分图片后重试');
    }
    return json;
  }

  BackupPayload parseAndValidate(String source) {
    if (utf8.encode(source).length > kMaxBackupBytes) {
      throw BackupException('备份文件超过 60MB 限制');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } catch (_) {
      throw BackupException('文件不是有效的 JSON 备份');
    }
    if (decoded is! Map<String, Object?>) {
      throw BackupException('备份文件结构不正确');
    }
    if (decoded['format'] != kBackupFormat) {
      throw BackupException('不是「育婴」的备份文件');
    }
    if (decoded['version'] is! int ||
        (decoded['version']! as int) > kBackupVersion) {
      throw BackupException('备份版本不受支持，请升级应用后重试');
    }
    final babies = _rows(decoded['babies'], '宝宝');
    final feedings = _rows(decoded['feeding_records'], '喝奶记录');
    final segments = _rows(decoded['breastfeeding_segments'], '亲喂分段');
    final stools = _rows(decoded['stool_records'], '排便记录');
    final sleeps = _rows(decoded['sleep_records'], '睡眠记录');
    final active = _rows(
      decoded['active_feeding_sessions'] ?? const <Object?>[],
      '进行中亲喂',
    );
    final growths = _rows(
      decoded['growth_records'] ?? const <Object?>[],
      '生长记录',
    );
    final checkups = _rows(
      decoded['checkup_plans'] ?? const <Object?>[],
      '儿保计划',
    );
    final vaccines = _rows(
      decoded['vaccine_records'] ?? const <Object?>[],
      '疫苗记录',
    );
    final settings = _rows(decoded['app_settings'] ?? const <Object?>[], '设置');
    final attachments = _attachments(decoded['attachments']);

    final babyIds = <String>{};
    for (final baby in babies) {
      final id = baby['id'];
      if (id is! String || id.isEmpty) throw BackupException('宝宝数据缺少 ID');
      if (!babyIds.add(id)) throw BackupException('宝宝 ID 重复');
      if (baby['nickname'] is! String) throw BackupException('宝宝昵称无效');
      _requireInt(baby['birth_date'], '宝宝出生日期');
    }
    if (babyIds.isEmpty) throw BackupException('备份中没有宝宝数据');

    final feedingIds = <String>{};
    final feedingModes = <String, String>{};
    for (final feeding in feedings) {
      final id = feeding['id'];
      if (id is! String || !feedingIds.add(id)) {
        throw BackupException('喝奶记录 ID 无效或重复');
      }
      _requireBaby(feeding, babyIds);
      final mode = feeding['mode'];
      if (mode != 'bottle' && mode != 'direct') {
        throw BackupException('喝奶记录类型无效');
      }
      feedingModes[id] = mode as String;
      _requireInt(feeding['started_at'], '喝奶时间');
      if (mode == 'bottle') {
        final amount = feeding['amount_ml'];
        if (amount is! int || amount <= 0) {
          throw BackupException('瓶喂奶量必须为正整数');
        }
      }
    }

    for (final segment in segments) {
      final feedingId = segment['feeding_id'];
      if (feedingId is! String || !feedingIds.contains(feedingId)) {
        throw BackupException('亲喂分段引用了不存在的喝奶记录');
      }
      if (feedingModes[feedingId] != 'direct') {
        throw BackupException('亲喂分段只能属于亲喂记录');
      }
      if (segment['side'] != 'left' && segment['side'] != 'right') {
        throw BackupException('亲喂侧别无效');
      }
      final start = _requireInt(segment['started_at'], '亲喂分段开始时间');
      final end = _requireInt(segment['ended_at'], '亲喂分段结束时间');
      if (end < start) throw BackupException('亲喂分段结束时间早于开始时间');
    }

    for (final stool in stools) {
      _requireBaby(stool, babyIds);
      _requireInt(stool['occurred_at'], '排便时间');
      _checkRelativePath(stool['image_path'], '排便图片路径');
    }

    final sleepByBaby = <String, List<List<int>>>{};
    final ongoingCount = <String, int>{};
    for (final sleep in sleeps) {
      final babyId = _requireBaby(sleep, babyIds);
      final start = _requireInt(sleep['started_at'], '睡眠开始时间');
      final end = sleep['ended_at'];
      if (end == null) {
        ongoingCount[babyId] = (ongoingCount[babyId] ?? 0) + 1;
        if (ongoingCount[babyId]! > 1) {
          throw BackupException('同一宝宝存在多条进行中睡眠');
        }
        continue;
      }
      final endMs = _requireInt(end, '睡眠结束时间');
      if (endMs <= start) throw BackupException('睡眠结束时间必须晚于开始时间');
      sleepByBaby.putIfAbsent(babyId, () => []).add([start, endMs]);
    }
    for (final entry in sleepByBaby.entries) {
      final ranges = entry.value..sort((a, b) => a[0].compareTo(b[0]));
      for (var i = 1; i < ranges.length; i++) {
        if (ranges[i][0] < ranges[i - 1][1]) {
          throw BackupException('备份中存在重叠的睡眠记录');
        }
      }
    }

    final activeBabies = <String>{};
    for (final session in active) {
      final babyId = _requireBaby(session, babyIds);
      if (!activeBabies.add(babyId)) {
        throw BackupException('同一宝宝存在多条进行中亲喂');
      }
      final feedingId = session['feeding_id'];
      if (feedingId is! String || !feedingIds.contains(feedingId)) {
        throw BackupException('进行中亲喂引用了不存在的记录');
      }
      if (feedingModes[feedingId] != 'direct') {
        throw BackupException('进行中亲喂记录类型不一致');
      }
      final side = session['current_side'];
      if (side != null && side != 'left' && side != 'right') {
        throw BackupException('进行中亲喂侧别无效');
      }
    }

    _validateGrowths(growths, babyIds);
    _validateCheckups(checkups, babyIds);
    _validateVaccines(vaccines, babyIds);

    return BackupPayload(
      exportedAt: decoded['exported_at'] is int
          ? decoded['exported_at']! as int
          : DateTime.now().millisecondsSinceEpoch,
      babies: babies,
      feedings: feedings,
      segments: segments,
      stools: stools,
      sleeps: sleeps,
      activeSessions: active,
      growths: growths,
      checkups: checkups,
      vaccines: vaccines,
      settings: settings,
      attachments: attachments,
    );
  }

  Future<void> restore(BackupPayload payload) async {
    await db.transaction((txn) async {
      for (final table in _tables.reversed) {
        await txn.delete(table);
      }
      for (final table in _tables) {
        final rows = switch (table) {
          'babies' => payload.babies,
          'feeding_records' => payload.feedings,
          'breastfeeding_segments' => payload.segments,
          'stool_records' => payload.stools,
          'sleep_records' => payload.sleeps,
          'active_feeding_sessions' => payload.activeSessions,
          'growth_records' => payload.growths,
          'checkup_plans' => payload.checkups,
          'vaccine_records' => payload.vaccines,
          _ => payload.settings,
        };
        for (final row in rows) {
          await txn.insert(table, row);
        }
      }
    });
    await _writeAttachments(payload.attachments);
    await _pruneAttachments(await _referencedImagePaths());
  }

  Future<Set<String>> _referencedImagePaths() async {
    final paths = <String>{};
    for (final table in ['stool_records', 'checkup_plans']) {
      final rows = await db.query(
        table,
        columns: ['image_path'],
        where: "image_path IS NOT NULL AND image_path != ''",
      );
      for (final row in rows) {
        final path = row['image_path'];
        if (path is String) {
          paths.add(path.replaceAll('\\', '/'));
        }
      }
    }
    return paths;
  }

  static Map<String, String> _attachments(Object? raw) {
    if (raw == null) return const {};
    if (raw is! Map) throw BackupException('备份附件格式错误');
    final result = <String, String>{};
    var totalBytes = 0;
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || key.trim().isEmpty) {
        throw BackupException('备份附件路径无效');
      }
      _checkRelativePath(key, '备份附件路径');
      if (value is! String) throw BackupException('备份附件内容格式错误');
      final List<int> bytes;
      try {
        bytes = base64Decode(value);
      } on FormatException {
        throw BackupException('备份附件不是有效的 base64 内容');
      }
      totalBytes += bytes.length;
      if (totalBytes > kMaxBackupBytes) {
        throw BackupException('备份内图片超过 60MB 限制');
      }
      result[key] = value;
    }
    return result;
  }

  static void _validateGrowths(
    List<Map<String, Object?>> growths,
    Set<String> babyIds,
  ) {
    final ids = <String>{};
    for (final growth in growths) {
      final id = growth['id'];
      if (id is! String || !ids.add(id)) {
        throw BackupException('生长记录 ID 无效或重复');
      }
      _requireBaby(growth, babyIds);
      _requireInt(growth['measured_at'], '生长记录测量时间');
    }
  }

  static void _validateCheckups(
    List<Map<String, Object?>> checkups,
    Set<String> babyIds,
  ) {
    final ids = <String>{};
    for (final checkup in checkups) {
      final id = checkup['id'];
      if (id is! String || !ids.add(id)) {
        throw BackupException('儿保计划 ID 无效或重复');
      }
      _requireBaby(checkup, babyIds);
      _requireInt(checkup['scheduled_at'], '儿保计划时间');
      if (!_careStatuses.contains(checkup['status'])) {
        throw BackupException('儿保计划状态无效');
      }
      final items = checkup['items'];
      if (items != null) {
        if (items is! String) throw BackupException('儿保检查项格式错误');
        if (items.trim().isNotEmpty) {
          Object? parsed;
          try {
            parsed = jsonDecode(items);
          } on FormatException {
            throw BackupException('儿保检查项格式错误');
          }
          if (parsed is! List) throw BackupException('儿保检查项格式错误');
        }
      }
      _checkRelativePath(checkup['image_path'], '儿保图片路径');
    }
  }

  static void _validateVaccines(
    List<Map<String, Object?>> vaccines,
    Set<String> babyIds,
  ) {
    final ids = <String>{};
    for (final vaccine in vaccines) {
      final id = vaccine['id'];
      if (id is! String || !ids.add(id)) {
        throw BackupException('疫苗记录 ID 无效或重复');
      }
      _requireBaby(vaccine, babyIds);
      _requireInt(vaccine['scheduled_at'], '疫苗计划时间');
      if (!_careStatuses.contains(vaccine['status'])) {
        throw BackupException('疫苗记录状态无效');
      }
      final dose = vaccine['dose'];
      if (dose is! int || dose <= 0) {
        throw BackupException('疫苗剂次必须为正整数');
      }
      final fever = vaccine['fever'];
      if (fever == null) {
        vaccine['fever'] = 0;
      } else if (fever is bool) {
        vaccine['fever'] = fever ? 1 : 0;
      } else if (fever is int && (fever == 0 || fever == 1)) {
        vaccine['fever'] = fever;
      } else {
        throw BackupException('疫苗发烧标记无效');
      }
      final temperature = vaccine['temperature'];
      if (temperature != null) {
        if (temperature is! num || temperature < 30 || temperature > 45) {
          throw BackupException('疫苗体温无效');
        }
        vaccine['temperature'] = temperature.toDouble();
      }
    }
  }

  static List<Map<String, Object?>> _rows(Object? value, String label) {
    if (value is! List) throw BackupException('$label 数据缺失或格式错误');
    return value.map((item) {
      if (item is! Map<String, Object?>) {
        throw BackupException('$label 数据格式错误');
      }
      return item;
    }).toList();
  }

  static String _requireBaby(Map<String, Object?> row, Set<String> babyIds) {
    final babyId = row['baby_id'];
    if (babyId is! String || !babyIds.contains(babyId)) {
      throw BackupException('记录引用了不存在的宝宝');
    }
    return babyId;
  }

  static int _requireInt(Object? value, String label) {
    if (value is! int) throw BackupException('$label 格式错误');
    return value;
  }

  static void _checkRelativePath(Object? value, String label) {
    if (value == null) return;
    if (value is! String) throw BackupException('$label格式错误');
    final normalized = value.replaceAll('\\', '/');
    if (normalized.startsWith('/') || normalized.split('/').contains('..')) {
      throw BackupException('$label必须是相对路径');
    }
  }
}
