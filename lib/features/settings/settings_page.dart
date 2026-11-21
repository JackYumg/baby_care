import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/backup_service.dart';
import '../../domain/feeding_reminder.dart';
import '../../domain/time_rules.dart';
import '../../platform/document_storage.dart';
import '../../platform/feed_notifications.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.state,
    this.storage = const DocumentStorage(),
  });

  final AppState state;
  final DocumentStorage storage;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _busy = false;
  String _busyLabel = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('设置与备份')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          if (_busy) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.greenSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _busyLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.greenDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
          ],
          const SectionHeader('喂奶提醒'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: widget.state.feedReminderEnabled,
                  onChanged: (value) async {
                    await widget.state.setFeedReminderEnabled(value);
                    if (mounted) setState(() {});
                  },
                  secondary: const Icon(Icons.alarm_rounded),
                  title: const Text('到点闹钟提醒'),
                  subtitle: const Text('按奶量估算下次喂奶时间，到点发送通知'),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: widget.state.feedStatusEnabled,
                  onChanged: (value) async {
                    await widget.state.setFeedStatusEnabled(value);
                    if (mounted) setState(() {});
                  },
                  secondary: const Icon(Icons.notifications_active_outlined),
                  title: const Text('锁屏状态栏'),
                  subtitle: const Text('常驻通知展示上次喝奶时间与下次倒计时'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.verified_outlined),
                  title: const Text('检查通知与闹钟权限'),
                  subtitle: Text(_feedStatusText()),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    await FeedNotifications.requestPermissions();
                    if (!context.mounted) return;
                    showSuccessSnack(context, '已请求通知与精确闹钟权限');
                  },
                ),
              ],
            ),
          ),
          const SectionHeader('数据备份'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '备份包含全部宝宝与记录，是未加密的 JSON 文件，请妥善保管。'
                '导出时由系统文件面板选择保存位置。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.subtle,
                  height: 1.6,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _export,
            icon: const Icon(Icons.file_upload_outlined),
            label: const Text('导出备份文件'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _restore,
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('从备份文件恢复'),
          ),
          const SectionHeader('统计口径'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '所有记录按北京时间（Asia/Shanghai）分日统计。'
                '睡眠与亲喂跨过零点时，按实际时长拆分到两天。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.subtle,
                  height: 1.6,
                ),
              ),
            ),
          ),
          const SectionHeader('隐私与数据'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _privacyLine(theme, '应用完全离线运行，不联网、不收集、不上传任何数据。'),
                  const SizedBox(height: 8),
                  _privacyLine(theme, '所有记录保存在本机应用私有目录，已关闭系统自动云备份。'),
                  const SizedBox(height: 8),
                  _privacyLine(theme, '恢复备份会覆盖当前全部数据，不会合并。'),
                  const SizedBox(height: 8),
                  _privacyLine(theme, '卸载应用或清除应用数据会丢失本地记录，请自行保管导出的备份文件。'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _feedStatusText() {
    final state = widget.state;
    final last = state.lastFeedingMs;
    if (last == null) return '还没有喝奶记录';
    final next = state.nextReminderMs;
    if (next == null) return '上次 ${formatClock(last)} 喝奶 · 未设置提醒';
    return '上次 ${formatClock(last)} · 下次 ${formatClock(next)} · '
        '${feedRemainText(next, DateTime.now().millisecondsSinceEpoch)}';
  }

  Widget _privacyLine(ThemeData theme, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Icon(Icons.circle, size: 5, color: AppColors.green),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.subtle,
              height: 1.6,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _busyLabel = '正在导出备份…';
    });
    try {
      final json = await widget.state.exportBackupJson();
      final fileName = _backupFileName();
      final uri = await widget.storage.pickSaveLocation(fileName);
      if (uri == null) return;
      setState(() => _busyLabel = '正在写入文件…');
      await widget.storage.writeText(uri, json);
      if (!mounted) return;
      showSuccessSnack(context, '已导出备份：$fileName');
    } catch (error) {
      if (!mounted) return;
      showErrorSnack(context, error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = '';
        });
      }
    }
  }

  Future<void> _restore() async {
    try {
      final uri = await widget.storage.pickOpenFile();
      if (uri == null || !mounted) return;
      final source = await widget.storage.readText(uri);
      final payload = await widget.state.parseBackup(source);
      if (!mounted) return;
      final proceed = await _confirmRestore(payload);
      if (proceed != true || !mounted) return;

      setState(() {
        _busy = true;
        _busyLabel = '请先保存当前数据的安全备份…';
      });
      final safetyJson = await widget.state.exportBackupJson();
      final safetyName = _backupFileName(prefix: 'yuying_before_restore');
      final saveUri = await widget.storage.pickSaveLocation(safetyName);
      if (saveUri == null) {
        if (!mounted) return;
        showSuccessSnack(context, '已取消安全备份，恢复未执行');
        return;
      }
      await widget.storage.writeText(saveUri, safetyJson);

      if (!mounted) return;
      setState(() => _busyLabel = '正在恢复数据…');
      await widget.state.restoreBackup(payload);
      if (!mounted) return;
      final hasTimer = widget.state.hasActiveTimer;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('恢复完成'),
          content: Text(
            hasTimer
                ? '已恢复全部数据。备份中的进行中计时保留了原始开始时间，'
                      '请到今日页核对是否仍在进行。'
                : '已恢复全部数据，可以开始记录或查看统计。',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      showErrorSnack(context, error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = '';
        });
      }
    }
  }

  Future<bool?> _confirmRestore(BackupPayload payload) {
    final (date, hour, minute) = splitStatDateTime(payload.exportedAt);
    final exportedAt =
        '${date.year}年${date.month}月${date.day}日 '
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    final recordCount =
        payload.feedings.length + payload.stools.length + payload.sleeps.length;
    final theme = Theme.of(context);
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认恢复备份'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('备份时间：$exportedAt'),
            const SizedBox(height: 6),
            Text('宝宝 ${payload.babies.length} 位 · 记录 $recordCount 条'),
            const SizedBox(height: 14),
            Text(
              '恢复会覆盖当前全部数据，不会合并。',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '继续前需要先导出当前数据的安全备份，取消保存将取消本次恢复。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.subtle,
                height: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('继续恢复'),
          ),
        ],
      ),
    );
  }

  String _backupFileName({String prefix = 'yuying_backup'}) {
    final t = DateTime.now().add(kStatOffset);
    String two(int value) => value.toString().padLeft(2, '0');
    return '${prefix}_${t.year}${two(t.month)}${two(t.day)}'
        '_${two(t.hour)}${two(t.minute)}${two(t.second)}.json';
  }
}
