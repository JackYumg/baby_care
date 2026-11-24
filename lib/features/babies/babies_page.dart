import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/models.dart';
import '../../platform/care_reminders.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../growth/growth_page.dart';
import '../settings/settings_page.dart';
import 'baby_form_page.dart';

class BabiesPage extends StatelessWidget {
  const BabiesPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('宝宝'),
            actions: [
              IconButton(
                tooltip: '设置与备份',
                onPressed: () => _openSettings(context),
                icon: const Icon(Icons.settings_outlined),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              Text(
                '点按卡片切换当前宝宝，每个宝宝的记录与统计相互独立。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.subtle,
                  height: 1.5,
                ),
              ),
              const SectionHeader('宝宝档案'),
              for (final baby in state.babies) ...[
                _babyCard(context, baby),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: () => _addBaby(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('添加宝宝'),
              ),
              const SectionHeader('更多'),
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.greenSoft,
                    child: Icon(
                      Icons.backup_outlined,
                      color: AppColors.greenDark,
                      size: 20,
                    ),
                  ),
                  title: const Text('设置与备份'),
                  subtitle: const Text('导出数据、从文件恢复'),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.subtle,
                  ),
                  onTap: () => _openSettings(context),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '卸载应用或清除应用数据会删除全部本地记录，建议定期导出备份。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.subtle,
                  height: 1.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _babyCard(BuildContext context, Baby baby) {
    final theme = Theme.of(context);
    final isCurrent = state.currentBaby?.id == baby.id;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          state.selectBaby(baby.id);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: isCurrent
                    ? AppColors.greenSoft
                    : AppColors.apricot,
                child: Icon(
                  kAvatarIcons[baby.avatarKey] ?? Icons.child_care_rounded,
                  color: isCurrent ? AppColors.greenDark : AppColors.subtle,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            baby.nickname,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (isCurrent) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.greenSoft,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              '当前',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.greenDark,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_birthText(baby.birthDate)} · ${_ageText(baby.birthDate)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.subtle,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '更多操作',
                icon: const Icon(
                  Icons.more_horiz_rounded,
                  color: AppColors.subtle,
                ),
                onSelected: (value) {
                  if (value == 'growth') _openGrowth(context, baby);
                  if (value == 'edit') _editBaby(context, baby);
                  if (value == 'delete') _deleteBaby(context, baby);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'growth', child: Text('生长记录')),
                  PopupMenuItem(value: 'edit', child: Text('编辑资料')),
                  PopupMenuItem(value: 'delete', child: Text('删除宝宝')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addBaby(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => BabyFormPage(state: state)));
  }

  Future<void> _openGrowth(BuildContext context, Baby baby) async {
    if (state.currentBaby?.id != baby.id) {
      await state.selectBaby(baby.id);
    }
    if (!context.mounted) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => GrowthPage(state: state)));
  }

  void _editBaby(BuildContext context, Baby baby) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BabyFormPage(state: state, baby: baby),
      ),
    );
  }

  Future<void> _deleteBaby(BuildContext context, Baby baby) async {
    final hasTimer = baby.id == state.currentBaby?.id
        ? state.hasActiveTimer
        : (await state.recordRepo.ongoingSleep(baby.id)) != null ||
              (await state.recordRepo.activeFeeding(baby.id)) != null;
    if (!context.mounted) return;
    if (hasTimer) {
      showSuccessSnack(context, '请先结束或放弃「${baby.nickname}」进行中的计时，再删除');
      return;
    }
    final confirmed = await showConfirmDialog(
      context,
      title: '删除「${baby.nickname}」？',
      message: 'TA 的全部喝奶、睡眠、排便、生长记录，以及儿保 / 疫苗待办会一并删除，且无法恢复。',
      confirmText: '删除',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    try {
      await state.deleteBaby(baby.id);
      await syncCareReminders(state);
      if (!context.mounted) return;
      showSuccessSnack(context, '已删除「${baby.nickname}」');
    } catch (error) {
      if (!context.mounted) return;
      showErrorSnack(context, error);
    }
  }

  void _openSettings(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => SettingsPage(state: state)));
  }

  static String _birthText(DateTime birth) =>
      '${birth.year}年${birth.month}月${birth.day}日出生';

  static String _ageText(DateTime birth) {
    final now = DateTime.now();
    var months = (now.year - birth.year) * 12 + now.month - birth.month;
    if (now.day < birth.day) months -= 1;
    if (months < 1) return '未满月';
    if (months < 12) return '$months 个月';
    final years = months ~/ 12;
    final rest = months % 12;
    return rest == 0 ? '$years 岁' : '$years 岁 $rest 个月';
  }
}
