import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/models.dart';
import '../../domain/time_rules.dart';
import '../../platform/care_reminders.dart';
import '../../platform/image_store.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../stool/stool_sheet.dart' show StoolImageThumbnail;

/// 儿保待办详情：新增与查看 / 编辑共用。
class CheckupDetailPage extends StatefulWidget {
  const CheckupDetailPage({super.key, required this.state, this.plan});

  final AppState state;

  /// 为空表示新增儿保待办。
  final CheckupPlan? plan;

  @override
  State<CheckupDetailPage> createState() => _CheckupDetailPageState();
}

class _CheckupDetailPageState extends State<CheckupDetailPage> {
  late final TextEditingController _title;
  late final TextEditingController _note;
  late int _scheduledAt;
  late List<CheckupItem> _items;
  String? _imagePath;
  String? _originalImagePath;
  bool _saving = false;
  bool _pickingImage = false;

  bool get _isNew => widget.plan == null;

  CareTaskStatus get _status => widget.plan?.status ?? CareTaskStatus.pending;

  bool get _isDone => _status == CareTaskStatus.done;

  @override
  void initState() {
    super.initState();
    final plan = widget.plan;
    _title = TextEditingController(text: plan?.title ?? '儿保');
    _note = TextEditingController(text: plan?.note ?? '');
    _scheduledAt =
        plan?.scheduledAt ?? combineStatDateTime(todayStatDate(), 9, 0);
    _items = [for (final item in plan?.items ?? const <CheckupItem>[]) item];
    _imagePath = plan?.imagePath;
    _originalImagePath = plan?.imagePath;
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  String get _noteText => _note.text.trim();

  /// 已移除的图片用空字符串提交，便于数据库清空引用并删除旧文件。
  String? get _imageForSubmit {
    if (_imagePath != null) return _imagePath;
    return _originalImagePath == null || _originalImagePath!.isEmpty
        ? null
        : '';
  }

  Future<void> _pickScheduledAt() async {
    final today = todayStatDate();
    final picked = await pickStatDateTime(
      context,
      initialMs: _scheduledAt,
      firstDate: DateTime(2018, 1, 1),
      lastDate: DateTime(today.year + 10, 12, 31),
    );
    if (picked != null && mounted) setState(() => _scheduledAt = picked);
  }

  Future<void> _pickImage({required bool camera}) async {
    if (_pickingImage || _saving) return;
    setState(() => _pickingImage = true);
    try {
      final path = await ImageStore.pickAndSave(
        folder: kCheckupImageFolder,
        camera: camera,
      );
      if (path == null || !mounted) return;
      setState(() => _imagePath = path);
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  Future<void> _editItemResult(int index) async {
    final item = _items[index];
    final controller = TextEditingController(text: item.result ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${item.label} 结果'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 2,
          decoration: const InputDecoration(hintText: '例如 6.8kg / 正常 / 轻度贫血'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    final trimmed = result.trim();
    setState(() {
      _items[index] = CheckupItem(
        label: item.label,
        done: item.done || trimmed.isNotEmpty,
        result: trimmed.isEmpty ? null : trimmed,
      );
    });
  }

  Future<void> _addItem() async {
    final controller = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('添加检查项'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如 听力筛查'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = label?.trim() ?? '';
    if (trimmed.isEmpty || !mounted) return;
    setState(() => _items.add(CheckupItem(label: trimmed)));
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      showSuccessSnack(context, '请填写标题');
      return;
    }
    setState(() => _saving = true);
    try {
      final plan = widget.plan;
      if (plan == null) {
        final beforeIds = widget.state.checkups.map((e) => e.id).toSet();
        await widget.state.addCheckup(
          title: title,
          scheduledAt: _scheduledAt,
          items: [for (final item in _items) item.label],
          note: _noteText,
        );
        if (_items.any((item) => item.done || (item.result ?? '').isNotEmpty)) {
          CheckupPlan? created;
          for (final item in widget.state.checkups) {
            if (!beforeIds.contains(item.id)) {
              created = item;
              break;
            }
          }
          if (created != null) {
            await widget.state.updateCheckup(id: created.id, items: _items);
          }
        }
        await syncCareReminders(widget.state);
        if (!mounted) return;
        showSuccessSnack(context, '已新增儿保待办');
        Navigator.of(context).pop();
        return;
      }

      await widget.state.updateCheckup(
        id: plan.id,
        title: title,
        scheduledAt: _scheduledAt,
        items: _items,
        note: _noteText,
      );

      final imageChanged = _imagePath != _originalImagePath;
      String message = '已保存修改';
      if (_isDone) {
        if (imageChanged) {
          await widget.state.completeCheckup(
            id: plan.id,
            items: _items,
            note: _noteText,
            imagePath: _imageForSubmit,
            completedAt: plan.completedAt,
          );
          _originalImagePath = _imagePath;
        }
      } else if (imageChanged && _imagePath != null) {
        // 未完成时检查图片随「标记完成」保存，避免留下无主文件。
        await _discardUnsavedImage();
        message = '已保存，检查图片会在标记完成时保存';
      }
      await syncCareReminders(widget.state);
      if (!mounted) return;
      showSuccessSnack(context, message);
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _discardUnsavedImage() async {
    final path = _imagePath;
    if (path == null || path == _originalImagePath) return;
    _imagePath = _originalImagePath;
    try {
      await ImageStore.delete(path);
    } catch (_) {
      // 图片删除失败不影响已保存的数据。
    }
  }

  Future<void> _complete() async {
    final plan = widget.plan;
    if (plan == null) return;
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year, now.month, now.day),
      firstDate: DateTime(2018, 1, 1),
      lastDate: DateTime(now.year, now.month, now.day),
      helpText: '选择完成日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (picked == null || !mounted) return;
    final completedAt = combineStatDateTime(
      DateTime.utc(picked.year, picked.month, picked.day),
      now.hour,
      now.minute,
    );
    setState(() => _saving = true);
    try {
      await widget.state.completeCheckup(
        id: plan.id,
        items: _items,
        note: _noteText,
        imagePath: _imageForSubmit,
        completedAt: completedAt,
      );
      _originalImagePath = _imagePath;
      await syncCareReminders(widget.state);
      if (!mounted) return;
      showSuccessSnack(context, '已标记完成');
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _skip() async {
    final plan = widget.plan;
    if (plan == null) return;
    final ok = await showConfirmDialog(
      context,
      title: '跳过这条儿保？',
      message: '跳过后会移入「已完成」，不再发送提醒，可以随时改回完成状态。',
      confirmText: '跳过',
    );
    if (!ok) return;
    try {
      await widget.state.skipCheckup(plan.id);
      await syncCareReminders(widget.state);
      if (!mounted) return;
      showSuccessSnack(context, '已跳过这条儿保');
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    }
  }

  Future<void> _delete() async {
    final plan = widget.plan;
    if (plan == null) return;
    final ok = await showConfirmDialog(
      context,
      title: '删除这条儿保？',
      message: '删除后无法恢复，检查图片也会一并清理，其他待办不受影响。',
      confirmText: '删除',
      destructive: true,
    );
    if (!ok) return;
    try {
      await widget.state.deleteCheckup(plan.id);
      await syncCareReminders(widget.state);
      if (!mounted) return;
      showSuccessSnack(context, '已删除');
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final completedAt = plan?.completedAt;
    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? '新增儿保' : '儿保详情')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          if (_isDone && completedAt != null)
            _StatusBanner(
              icon: Icons.check_circle_rounded,
              color: AppColors.green,
              text:
                  '已完成 · ${formatMonthDay(statDateFromMs(completedAt))} '
                  '${formatClock(completedAt)}',
            ),
          if (_status == CareTaskStatus.skipped)
            const _StatusBanner(
              icon: Icons.remove_circle_outline_rounded,
              color: AppColors.subtle,
              text: '已跳过，不会发送提醒',
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _title,
            maxLength: 40,
            decoration: const InputDecoration(
              labelText: '标题',
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          _ScheduleField(
            valueMs: _scheduledAt,
            onTap: _pickScheduledAt,
          ),
          SectionHeader(
            '检查项',
            trailing: TextButton.icon(
              onPressed: _saving ? null : _addItem,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('添加'),
            ),
          ),
          Card(
            child: Column(
              children: [
                if (_items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(18),
                    child: Text(
                      '还没有检查项，可以点击「添加」补充。',
                      style: TextStyle(fontSize: 13, color: AppColors.subtle),
                    ),
                  )
                else
                  for (var i = 0; i < _items.length; i++) ...[
                    if (i > 0) const Divider(indent: 16, endIndent: 16),
                    _CheckupItemTile(
                      item: _items[i],
                      onDoneChanged: (value) => setState(() {
                        _items[i] = CheckupItem(
                          label: _items[i].label,
                          done: value,
                          result: _items[i].result,
                        );
                      }),
                      onEditResult: () => _editItemResult(i),
                    ),
                  ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            maxLength: 500,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '备注（可选）',
              counterText: '',
            ),
          ),
          const SizedBox(height: 16),
          _PhotoSection(
            imagePath: _imagePath,
            picking: _pickingImage,
            hint: _isDone ? '保存后一并更新' : '标记完成时一并保存',
            onPickCamera: () => _pickImage(camera: true),
            onPickGallery: () => _pickImage(camera: false),
            onRemove: () => setState(() => _imagePath = null),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_isNew ? '保存' : '保存修改'),
          ),
          if (plan != null && !_isDone) ...[
            const SizedBox(height: 10),
            FilledButton.tonal(
              onPressed: _saving ? null : _complete,
              child: const Text('标记完成'),
            ),
          ],
          if (plan != null && _status == CareTaskStatus.pending) ...[
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _saving ? null : _skip,
              child: const Text('跳过'),
            ),
          ],
          if (plan != null) ...[
            const SizedBox(height: 6),
            TextButton(
              onPressed: _saving ? null : _delete,
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('删除待办'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScheduleField extends StatelessWidget {
  const _ScheduleField({required this.valueMs, required this.onTap});

  final int valueMs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (date, hour, minute) = splitStatDateTime(valueMs);
    final isToday = date == todayStatDate();
    final text =
        '${isToday ? '今天' : formatMonthDay(date)} · ${weekdayLabel(date)} '
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: '计划日期',
          suffixIcon: Icon(Icons.event_rounded, size: 20),
        ),
        child: Text(text, style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}

class _CheckupItemTile extends StatelessWidget {
  const _CheckupItemTile({
    required this.item,
    required this.onDoneChanged,
    required this.onEditResult,
  });

  final CheckupItem item;
  final ValueChanged<bool> onDoneChanged;
  final VoidCallback onEditResult;

  @override
  Widget build(BuildContext context) {
    final result = item.result ?? '';
    final hasResult = result.isNotEmpty;
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 6, right: 6),
      leading: Checkbox(
        value: item.done,
        onChanged: (value) => onDoneChanged(value ?? false),
      ),
      title: Text(
        item.label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        hasResult ? result : '未填写结果',
        style: TextStyle(
          fontSize: 12,
          color: hasResult ? AppColors.ink : AppColors.subtle,
        ),
      ),
      trailing: IconButton(
        tooltip: '填写结果',
        onPressed: onEditResult,
        icon: const Icon(Icons.edit_note_rounded),
      ),
      onTap: onEditResult,
    );
  }
}

class _PhotoSection extends StatelessWidget {
  const _PhotoSection({
    required this.imagePath,
    required this.picking,
    required this.hint,
    required this.onPickCamera,
    required this.onPickGallery,
    required this.onRemove,
  });

  final String? imagePath;
  final bool picking;
  final String hint;
  final VoidCallback onPickCamera;
  final VoidCallback onPickGallery;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final path = imagePath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('检查图片（可选）', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(width: 8),
            Text(
              hint,
              style: const TextStyle(fontSize: 11, color: AppColors.subtle),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (path == null || path.isEmpty)
          Row(
            children: [
              _photoPickerTile(
                context,
                icon: Icons.photo_camera_rounded,
                label: '拍照',
                onTap: onPickCamera,
              ),
              const SizedBox(width: 10),
              _photoPickerTile(
                context,
                icon: Icons.photo_library_rounded,
                label: '从相册选择',
                onTap: onPickGallery,
              ),
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StoolImageThumbnail(relativePath: path, size: 96),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    const Text(
                      '点击缩略图可查看大图',
                      style: TextStyle(fontSize: 12, color: AppColors.subtle),
                    ),
                    Wrap(
                      spacing: 4,
                      children: [
                        TextButton.icon(
                          onPressed: picking ? null : onPickGallery,
                          icon: const Icon(
                            Icons.photo_library_rounded,
                            size: 18,
                          ),
                          label: const Text('更换'),
                        ),
                        TextButton.icon(
                          onPressed: picking ? null : onRemove,
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                          ),
                          label: const Text('移除'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _photoPickerTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final color = Theme.of(context).colorScheme.primary;
    final contentColor = picking ? color.withValues(alpha: 0.4) : color;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: picking ? null : onTap,
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: contentColor),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontSize: 11, color: contentColor)),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
