import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

const Map<String, IconData> kAvatarIcons = {
  'default': Icons.child_care_rounded,
  'sun': Icons.wb_sunny_rounded,
  'moon': Icons.nightlight_round,
  'star': Icons.star_rounded,
  'leaf': Icons.eco_rounded,
};

class BabyFormPage extends StatefulWidget {
  const BabyFormPage({super.key, required this.state, this.baby});

  final AppState state;
  final Baby? baby;

  @override
  State<BabyFormPage> createState() => _BabyFormPageState();
}

class _BabyFormPageState extends State<BabyFormPage> {
  late final TextEditingController _nickname;
  late DateTime _birthDate;
  late String _avatarKey;
  String? _sex;
  bool _saving = false;

  bool get isEdit => widget.baby != null;

  @override
  void initState() {
    super.initState();
    final baby = widget.baby;
    _nickname = TextEditingController(text: baby?.nickname ?? '');
    _birthDate = baby?.birthDate ?? DateTime.now();
    _avatarKey = baby?.avatarKey ?? 'default';
    _sex = baby?.sex;
  }

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate,
      firstDate: DateTime(2010),
      lastDate: DateTime(now.year, now.month, now.day),
      helpText: '选择出生日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  Future<void> _save() async {
    final nickname = _nickname.text.trim();
    if (nickname.isEmpty) {
      showSuccessSnack(context, '请填写宝宝昵称');
      return;
    }
    if (_birthDate.isAfter(DateTime.now())) {
      showSuccessSnack(context, '出生日期不能晚于今天');
      return;
    }
    setState(() => _saving = true);
    try {
      if (isEdit) {
        await widget.state.updateBaby(
          widget.baby!.copyWith(
            nickname: nickname,
            birthDate: _birthDate,
            sex: _sex,
            avatarKey: _avatarKey,
          ),
        );
      } else {
        await widget.state.createBaby(
          nickname: nickname,
          birthDate: _birthDate,
          sex: _sex,
          avatarKey: _avatarKey,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final months = _ageInMonths(_birthDate);
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? '编辑宝宝' : '添加宝宝')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const SectionHeader('基本信息'),
          TextField(
            controller: _nickname,
            textInputAction: TextInputAction.done,
            maxLength: 20,
            decoration: const InputDecoration(
              labelText: '昵称',
              hintText: '例如：小满',
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _pickBirthDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: '出生日期',
                suffixIcon: Icon(Icons.calendar_today_rounded, size: 20),
              ),
              child: Text(
                '${_birthDate.year}年${_birthDate.month}月${_birthDate.day}日'
                ' · ${months >= 0 ? '$months 个月' : '未满月'}',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('性别（可选）', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            children: [
              for (final entry in const [
                ('male', '男宝宝'),
                ('female', '女宝宝'),
                ('none', '不填写'),
              ])
                ChoiceChip(
                  label: Text(entry.$2),
                  selected: (_sex ?? 'none') == entry.$1,
                  onSelected: (_) => setState(
                    () => _sex = entry.$1 == 'none' ? null : entry.$1,
                  ),
                ),
            ],
          ),
          const SectionHeader('头像'),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final entry in kAvatarIcons.entries)
                InkWell(
                  borderRadius: BorderRadius.circular(40),
                  onTap: () => setState(() => _avatarKey = entry.key),
                  child: Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _avatarKey == entry.key
                          ? AppColors.greenSoft
                          : Colors.transparent,
                      border: Border.all(
                        color: _avatarKey == entry.key
                            ? AppColors.green
                            : AppColors.border,
                        width: _avatarKey == entry.key ? 2 : 1,
                      ),
                    ),
                    child: Icon(
                      entry.value,
                      color: _avatarKey == entry.key
                          ? AppColors.greenDark
                          : AppColors.subtle,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(isEdit ? '保存修改' : '创建宝宝档案'),
          ),
        ],
      ),
    );
  }

  int _ageInMonths(DateTime birth) {
    final now = DateTime.now();
    var months = (now.year - birth.year) * 12 + now.month - birth.month;
    if (now.day < birth.day) months -= 1;
    return months;
  }
}
