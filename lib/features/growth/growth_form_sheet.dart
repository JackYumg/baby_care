import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

Future<void> showGrowthFormSheet(
  BuildContext context,
  AppState state, {
  GrowthRecord? record,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => GrowthFormSheet(state: state, record: record),
  );
}

class GrowthFormSheet extends StatefulWidget {
  const GrowthFormSheet({super.key, required this.state, this.record});

  final AppState state;
  final GrowthRecord? record;

  @override
  State<GrowthFormSheet> createState() => _GrowthFormSheetState();
}

class _GrowthFormSheetState extends State<GrowthFormSheet> {
  late int _timeMs;
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  final _headController = TextEditingController();
  final _noteController = TextEditingController();
  bool _saving = false;

  bool get isEdit => widget.record != null;

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    _timeMs = record?.measuredAt ?? DateTime.now().millisecondsSinceEpoch;
    _heightController.text = _initialText(record?.heightCm);
    _weightController.text = _initialText(record?.weightKg);
    _headController.text = _initialText(record?.headCm);
    _noteController.text = record?.note ?? '';
  }

  @override
  void dispose() {
    _heightController.dispose();
    _weightController.dispose();
    _headController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  static String _initialText(double? value) {
    if (value == null) return '';
    final fixed = value.toStringAsFixed(1);
    return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
  }

  static bool _isInvalid(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) return false;
    return double.tryParse(text) == null;
  }

  Future<void> _save() async {
    if (_isInvalid(_heightController)) {
      showSuccessSnack(context, '请输入有效的身高');
      return;
    }
    if (_isInvalid(_weightController)) {
      showSuccessSnack(context, '请输入有效的体重');
      return;
    }
    if (_isInvalid(_headController)) {
      showSuccessSnack(context, '请输入有效的头围');
      return;
    }
    final height = double.tryParse(_heightController.text.trim());
    final weight = double.tryParse(_weightController.text.trim());
    final head = double.tryParse(_headController.text.trim());
    if (height == null && weight == null && head == null) {
      showSuccessSnack(context, '请至少填写身高、体重或头围中的一项');
      return;
    }
    if (height != null && (height < 20 || height > 150)) {
      showSuccessSnack(context, '身高应在 20～150 cm 之间');
      return;
    }
    if (weight != null && (weight < 0.5 || weight > 60)) {
      showSuccessSnack(context, '体重应在 0.5～60 kg 之间');
      return;
    }
    if (head != null && (head < 20 || head > 70)) {
      showSuccessSnack(context, '头围应在 20～70 cm 之间');
      return;
    }
    if (_timeMs > DateTime.now().millisecondsSinceEpoch) {
      showSuccessSnack(context, '测量时间不能晚于当前时间');
      return;
    }
    final note = _noteController.text.trim().isEmpty
        ? null
        : _noteController.text.trim();
    setState(() => _saving = true);
    try {
      if (isEdit) {
        await widget.state.updateGrowth(
          id: widget.record!.id,
          measuredAt: _timeMs,
          heightCm: height,
          weightKg: weight,
          headCm: head,
          note: note,
        );
      } else {
        await widget.state.addGrowth(
          measuredAt: _timeMs,
          heightCm: height,
          weightKg: weight,
          headCm: head,
          note: note,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      showSuccessSnack(context, isEdit ? '已保存修改' : '已保存测量记录');
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showConfirmDialog(
      context,
      title: '删除这条生长记录？',
      message: '删除后生长曲线会立即更新，且无法恢复。',
      confirmText: '删除',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await widget.state.deleteGrowth(widget.record!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  isEdit ? '编辑生长记录' : '记录生长',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TimeField(
              label: '测量时间',
              valueMs: _timeMs,
              onChanged: (value) => setState(() => _timeMs = value),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _heightController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: '身高',
                      suffixText: 'cm',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _weightController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: '体重',
                      suffixText: 'kg',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _headController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: '头围',
                      suffixText: 'cm',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '至少填写一项，可随时补充其余指标。',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.subtle),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: '备注（可选）',
                counterText: '',
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(isEdit ? '保存修改' : '保存测量'),
            ),
            if (isEdit) ...[
              const SizedBox(height: 10),
              TextButton(
                onPressed: _saving ? null : _delete,
                child: const Text('删除记录'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
