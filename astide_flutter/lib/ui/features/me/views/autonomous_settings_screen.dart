import 'package:flutter/material.dart';

import '../../../../app_scope.dart';
import '../../../core/theme/wechat_theme.dart';
import '../../../core/widgets/weui_widgets.dart';

/// Configures autonomous proactive messaging, Android foreground keep-alive, and quiet hours.
class AutonomousSettingsScreen extends StatefulWidget {
  const AutonomousSettingsScreen({super.key});

  @override
  State<AutonomousSettingsScreen> createState() => _AutonomousSettingsScreenState();
}

class _AutonomousSettingsScreenState extends State<AutonomousSettingsScreen> {
  bool _testing = false;

  static const List<int> _intervals = [15, 30, 60, 120];

  String _formatInterval(int minutes) {
    if (minutes < 60) return '每 $minutes 分钟';
    return '每 ${minutes ~/ 60} 小时';
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.settings;

    return Scaffold(
      backgroundColor: WeuiColors.bg0,
      appBar: AppBar(
        title: const Text('AI 自主发消息与常驻后台'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: WeuiColors.fg3),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 36),
        children: [
          WeuiCellGroup(
            title: '自主行动开关',
            tips: '开启后，AI 会根据当前时间（早午晚、深夜、周末）与聊天间隔，自主判断是否要主动发 1~3 条微信消息给你。',
            insetForm: true,
            children: [
              WeuiCell(
                title: '允许 AI 自主主动发消息',
                subtitle: s.autonomousEnabled ? '已启用：AI 将按设定频率思考是否联系你' : '未启用',
                trailing: WeuiSwitch(
                  value: s.autonomousEnabled,
                  onChanged: (val) async {
                    if (val) {
                      await app.autonomousService.requestNotificationPermission();
                    }
                    await app.updateSettings(s.copyWith(autonomousEnabled: val));
                  },
                ),
              ),
              WeuiCell(
                title: '自主思考检查频率',
                trailingText: _formatInterval(s.autonomousIntervalMinutes),
                showArrow: true,
                onTap: () => _pickInterval(context, app),
              ),
              WeuiCell(
                title: '夜间免打扰 (00:00 - 07:00)',
                subtitle: '凌晨时段不自动打扰你休息',
                trailing: WeuiSwitch(
                  value: s.quietHoursEnabled,
                  onChanged: (val) => app.updateSettings(s.copyWith(quietHoursEnabled: val)),
                ),
              ),
            ],
          ),
          WeuiCellGroup(
            title: 'Android 后台常驻保活',
            tips: '开启后台常驻后，将在通知栏保留轻量级守护通知，减少系统在切出应用或锁屏后冻结进程，从而稳定接收主动消息提醒。',
            insetForm: true,
            children: [
              WeuiCell(
                title: '常驻后台守护服务',
                subtitle: s.keepAliveEnabled ? '运行中（Android 前台服务）' : '未开启',
                trailing: WeuiSwitch(
                  value: s.keepAliveEnabled,
                  onChanged: (val) async {
                    if (val) {
                      final granted = await app.autonomousService.requestNotificationPermission();
                      if (!granted && context.mounted) {
                        showWeuiToast(context, '请允许通知权限以接收后台消息提醒');
                      }
                    }
                    await app.updateSettings(s.copyWith(keepAliveEnabled: val));
                  },
                ),
              ),
              WeuiCell(
                title: '申请忽略电池优化',
                subtitle: '防止手机熄屏后杀死后台网络与定时器',
                showArrow: true,
                onTap: () => app.autonomousService.requestIgnoreBatteryOptimizations(),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: WeuiButton(
              label: _testing ? 'AI 正在思考主动消息...' : '立即测试一次 AI 主动发消息',
              isLoading: _testing,
              onPressed: _testing
                  ? null
                  : () async {
                      setState(() => _testing = true);
                      await app.autonomousService.requestNotificationPermission();
                      final res = await app.triggerAutonomousNow(forceSend: true);
                      if (!context.mounted) return;
                      setState(() => _testing = false);
                      if (res.sent) {
                        showWeuiToast(context, '「${res.conversationTitle}」主动给你发消息啦');
                      } else {
                        showWeuiToast(
                          context,
                          res.reason.isNotEmpty ? res.reason : '未发送消息',
                          isError: !res.skipped,
                        );
                      }
                    },
            ),
          ),
        ],
      ),
    );
  }

  void _pickInterval(BuildContext context, AppController app) {
    WeuiActionSheet.show(
      context,
      title: '选择 AI 自主检查间隔',
      actions: [
        for (final min in _intervals)
          WeuiSheetAction(
            label: _formatInterval(min),
            onTap: () => app.updateSettings(
              app.settings.copyWith(autonomousIntervalMinutes: min),
            ),
          ),
      ],
    );
  }
}
