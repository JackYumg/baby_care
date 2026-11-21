import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

const Map<StoolColor, String> kStoolColorLabels = {
  StoolColor.yellow: '黄色',
  StoolColor.green: '绿色',
  StoolColor.brown: '棕色',
  StoolColor.black: '黑色',
  StoolColor.other: '其他',
};

const Map<StoolColor, Color> kStoolColorSwatches = {
  StoolColor.yellow: Color(0xFFE8C56A),
  StoolColor.green: Color(0xFF8FAE7B),
  StoolColor.brown: Color(0xFFA97A4F),
  StoolColor.black: Color(0xFF4A4640),
  StoolColor.other: Color(0xFFB9AFA0),
};

const List<String> kStoolConsistencies = ['稀', '糊状', '条状', '干硬'];

Future<void> showStoolSheet(
  BuildContext context,
  AppState state, {
  StoolRecord? stool,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => StoolSheet(state: state, stool: stool),
  );
}

class StoolSheet extends StatefulWidget {
  const StoolSheet({super.key, required this.state, this.stool});

  final AppState state;
  final StoolRecord? stool;

  @override
  State<StoolSheet> createState() => _StoolSheetState();
}

class _StoolSheetState extends State<StoolSheet> {
  late int _timeMs;
  StoolColor? _color;
  String? _consistency;
  final _noteController = TextEditingController();
  bool _saving = false;

  bool get isEdit => widget.stool != null;

  @override
  void initState() {
    super.initState();
    final stool = widget.stool;
    _timeMs = stool?.occurredAt ?? DateTime.now().millisecondsSinceEpoch;
    _color = stool?.color;
    _consistency = stool?.consistency;
    _noteController.text = stool?.note ?? '';
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_timeMs > DateTime.now().millisecondsSinceEpoch) {
      showSuccessSnack(context, '时间不能晚于当前时间');
      return;
    }
    setState(() => _saving = true);
    try {
      final note = _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim();
      if (isEdit) {
        await widget.state.updateStool(
          id: widget.stool!.id,
          occurredAt: _timeMs,
          color: _color,
          consistency: _consistency,
          note: note,
        );
      } else {
        await widget.state.addStool(
          occurredAt: _timeMs,
          color: _color,
          consistency: _consistency,
          note: note,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      showSuccessSnack(context, isEdit ? '已保存修改' : '已记录排便');
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
                  isEdit ? '编辑排便' : '记录排便',
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
              label: '排便时间',
              valueMs: _timeMs,
              onChanged: (value) => setState(() => _timeMs = value),
            ),
            const SizedBox(height: 18),
            Text('颜色（可选）', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                for (final entry in kStoolColorLabels.entries)
                  ChoiceChip(
                    avatar: CircleAvatar(
                      backgroundColor: kStoolColorSwatches[entry.key],
                    ),
                    label: Text(entry.value),
                    selected: _color == entry.key,
                    onSelected: (selected) =>
                        setState(() => _color = selected ? entry.key : null),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Text('性状（可选）', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              children: [
                for (final item in kStoolConsistencies)
                  ChoiceChip(
                    label: Text(item),
                    selected: _consistency == item,
                    onSelected: (selected) =>
                        setState(() => _consistency = selected ? item : null),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _noteController,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '备注（可选）',
                counterText: '',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(isEdit ? '保存修改' : '保存记录'),
            ),
            if (isEdit) ...[
              const SizedBox(height: 10),
              TextButton(
                onPressed: () async {
                  final ok = await showConfirmDialog(
                    context,
                    title: '删除这条排便记录？',
                    message: '删除后统计会立即更新，且无法恢复。',
                    confirmText: '删除',
                    destructive: true,
                  );
                  if (!ok) return;
                  await widget.state.deleteStool(widget.stool!.id);
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                },
                child: const Text('删除记录'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
