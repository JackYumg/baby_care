import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// 完整隐私政策页，作为首次启动弹窗与设置页入口的落地页。
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  static const String appName = '育婴';
  static const String effectiveDate = '2026年11月24日';

  /// 上线前请替换为真实主体信息，并与商店注册资料保持一致。
  static const String developerName = '（请填写开发者姓名或工作室名称）';
  static const String contactEmail = '（请填写联系邮箱）';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('隐私政策')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            '$appName隐私政策',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '生效日期：$effectiveDate',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.subtle,
            ),
          ),
          const _Section(
            title: '一、开发者与适用范围',
            paragraphs: [
              '本应用由$developerName开发并运营，面向家长记录宝宝的喝奶、排便、睡眠等日常信息。',
              '本政策说明应用如何处理你的信息，以及你享有的权利。使用本应用即表示你已阅读并同意本政策。',
            ],
          ),
          const _Section(
            title: '二、我们不会收集的信息',
            paragraphs: [
              '应用完全离线运行，未申请网络权限，不会把你的任何数据上传到服务器。',
              '我们不收集账号、手机号、通讯录、设备标识、位置等信息，也未集成广告、统计或数据采集 SDK。',
            ],
          ),
          const _Section(
            title: '三、仅保存在本机的信息',
            paragraphs: [
              '宝宝档案：昵称、出生日期、性别、头像。',
              '日常记录：喝奶、排便、睡眠的时间与备注，以及身高体重、儿保与疫苗计划。',
              '你主动选择的照片：仅用于头像或记录配图，保存在应用私有目录。',
              '以上信息都只存放于本机，只有你能通过本应用访问。',
            ],
          ),
          const _Section(
            title: '四、系统权限及用途',
            paragraphs: [
              '通知权限：到点展示喝奶提醒、儿保提醒与响铃通知。',
              '精确闹钟权限：按你设定的时间准时唤醒提醒，避免系统延迟。',
              '开机自启权限：手机重启或应用更新后恢复尚未到点的提醒。',
              '前台服务：在状态栏常驻显示下次喂奶倒计时，以及在闹钟到点时持续响铃。',
              '相册访问：仅在你主动更换头像或添加照片时，通过系统文件面板读取所选图片。',
              '你可以随时在系统设置中关闭上述权限，关闭后对应提醒功能将无法使用。',
            ],
          ),
          const _Section(
            title: '五、数据存储、备份与删除',
            paragraphs: [
              '所有数据保存在本机应用私有目录，系统自动云备份与设备迁移备份均已关闭。',
              '你可以在应用内删除单条记录或整个宝宝档案；卸载应用或清除应用数据会删除全部本地数据。',
              '导出的备份文件为未加密 JSON，由你自行选择保存位置和保管，请勿分享给他人。',
            ],
          ),
          const _Section(
            title: '六、第三方组件',
            paragraphs: [
              '应用使用 Flutter 及本地通知等开源组件，它们仅在本机执行功能，不向外传输数据。',
              '如需了解具体组件清单，可通过下方联系方式索取。',
            ],
          ),
          const _Section(
            title: '七、儿童个人信息保护',
            paragraphs: [
              '本应用是供监护人使用的记录工具，不面向儿童独立使用，也不提供社交、广告或付费功能。',
              '宝宝信息仅由监护人在本机录入和查看，我们不会收集或上传任何儿童个人信息。',
            ],
          ),
          const _Section(
            title: '八、你的权利',
            paragraphs: [
              '你可以在应用内查看、修改、删除全部数据，也可以随时卸载应用以停止使用。',
              '由于数据仅在本机，我们无法远程访问、导出或删除你的数据。',
            ],
          ),
          const _Section(
            title: '九、政策更新与联系我们',
            paragraphs: [
              '本政策调整时，我们会在应用更新说明中提示，并在应用内展示最新版本。',
              '如对本政策有疑问，请联系：$contactEmail。',
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '本应用的提醒内容仅供日常记录参考，不能替代医生的诊断与建议。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.subtle,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.paragraphs});

  final String title;
  final List<String> paragraphs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (final paragraph in paragraphs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                paragraph,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.7),
              ),
            ),
        ],
      ),
    );
  }
}
