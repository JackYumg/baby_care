import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/app_state.dart';
import 'privacy_policy_page.dart';

/// 首次启动的隐私政策确认门：未同意前不进入主界面。
class PrivacyGate extends StatefulWidget {
  const PrivacyGate({super.key, required this.state, required this.child});

  /// 记录已同意的政策版本；条款更新时递增即可再次弹出。
  static const String storageKey = 'privacy_agreed_version';
  static const String currentVersion = '1';

  final AppState state;
  final Widget child;

  @override
  State<PrivacyGate> createState() => _PrivacyGateState();
}

class _PrivacyGateState extends State<PrivacyGate> {
  bool _agreed = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    String? saved;
    try {
      saved = await widget.state.settingsRepo.get(PrivacyGate.storageKey);
    } on Object catch (_) {
      saved = null;
    }
    if (!mounted) return;
    setState(() {
      _agreed = saved == PrivacyGate.currentVersion;
    });
    if (!_agreed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _prompt());
    }
  }

  Future<void> _prompt() async {
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('隐私政策与数据说明'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '育婴完全离线运行：不联网、不上传，宝宝档案、喂养记录与照片只保存在你的手机里。',
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '为了在到点提醒喂奶和儿保计划，应用会使用通知、精确闹钟、开机自启与前台服务权限。',
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () => Navigator.of(dialogContext).push(
                      MaterialPageRoute(
                        builder: (_) => const PrivacyPolicyPage(),
                      ),
                    ),
                    child: Text(
                      '查看完整隐私政策',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop('exit'),
                child: const Text('不同意并退出'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop('agree'),
                child: const Text('同意并继续'),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted) return;
    if (choice != 'agree') {
      await SystemNavigator.pop();
      return;
    }
    await widget.state.settingsRepo.set(
      PrivacyGate.storageKey,
      PrivacyGate.currentVersion,
    );
    if (!mounted) return;
    setState(() => _agreed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_agreed) return widget.child;
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: const SizedBox.expand(),
    );
  }
}
