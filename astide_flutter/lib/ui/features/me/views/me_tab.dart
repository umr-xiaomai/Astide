import 'package:flutter/material.dart';

import '../../../../app_scope.dart';
import '../../../core/theme/wechat_theme.dart';
import '../../../core/widgets/wechat_avatar.dart';
import '../../../core/widgets/weui_widgets.dart';
import 'api_settings_screen.dart';
import 'autonomous_settings_screen.dart';
import 'deepseek_import_screen.dart';
import 'storage_management_screen.dart';
import 'user_profile_edit_screen.dart';

/// Tab 4 ("我"): user profile header, Roleplay master toggle, API settings, DeepSeek import, and AGPL about dialog.
class MeTab extends StatelessWidget {
  const MeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final settings = app.settings;
    final profile = app.activeApiProfile;

    final apiStatusText = profile == null || !profile.isConfigured
        ? '未配置 Key'
        : profile.model;

    return Scaffold(
      backgroundColor: WeuiColors.bg0,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Material(
            color: WeuiColors.bg2,
            child: InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const UserProfileEditScreen()),
                );
              },
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 22, 16, 26),
                  child: Row(
                    children: [
                      WechatAvatar(
                        name: settings.userNickname,
                        imagePath: settings.userAvatarPath,
                        backgroundColor: 0xFF576B95,
                        isUserSelf: true,
                        size: 64,
                        radius: 8,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              settings.userNickname,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: WeuiColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              settings.userPersona.trim().isNotEmpty
                                  ? '星汐号：astide_local · ${settings.userPersona.trim()}'
                                  : '星汐号：astide_local（本地离线存储）',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13.5,
                                color: WeuiColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Color(0x55000000)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          WeuiCellGroup(
            children: [
              WeuiCell(
                title: 'AI 自主发消息与常驻后台',
                subtitle: settings.autonomousEnabled
                    ? '已开启：每 ${settings.autonomousIntervalMinutes} 分钟自主判断发送'
                    : '根据时间与情境主动找你聊天',
                leading: const Icon(Icons.notifications_active_outlined,
                    color: WeuiColors.purple, size: 24),
                trailingText: settings.keepAliveEnabled
                    ? '常驻中'
                    : (settings.autonomousEnabled ? '已开启' : '未开启'),
                showArrow: true,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AutonomousSettingsScreen()),
                  );
                },
              ),
            ],
          ),
          WeuiCellGroup(
            children: [
              WeuiCell(
                title: 'API 与模型设置',
                leading: const Icon(Icons.api_outlined, color: WeuiColors.blue, size: 24),
                trailingText: apiStatusText,
                trailing: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: (profile != null && profile.isConfigured)
                        ? WeuiColors.brand
                        : WeuiColors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                showArrow: true,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ApiSettingsScreen()),
                  );
                },
              ),
              WeuiCell(
                title: '导入 DeepSeek 官方历史',
                leading: const Icon(Icons.download_for_offline_outlined,
                    color: Color(0xFF4D6BFE), size: 24),
                trailingText: 'URL / ZIP',
                showArrow: true,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DeepSeekImportScreen()),
                  );
                },
              ),
            ],
          ),
          WeuiCellGroup(
            children: [
              WeuiCell(
                title: '本地存储与数据管理',
                leading: const Icon(Icons.storage_outlined, color: WeuiColors.orange, size: 24),
                trailingText: 'SQLite',
                showArrow: true,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const StorageManagementScreen()),
                  );
                },
              ),
              WeuiCell(
                title: '关于星汐 Astide',
                leading: const Icon(Icons.info_outline, color: WeuiColors.link, size: 24),
                trailingText: 'v0.1.0',
                showArrow: true,
                onTap: () => _showAboutDialog(context),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: WeuiColors.bg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '星汐 Astide',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: WeuiColors.fg0),
              ),
              const SizedBox(height: 8),
              const Text(
                '版本：0.1.0\n包名：com.hoilai.mm.astide\n数据存储：全本地 SQLite（无需登录）\n开源协议：GNU AGPL-3.0\n项目主页：https://github.com/umr-xiaomai/Astide',
                style: TextStyle(fontSize: 14, color: WeuiColors.fg1, height: 1.55),
              ),
              const SizedBox(height: 18),
              WeuiButton(
                label: '关闭',
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
