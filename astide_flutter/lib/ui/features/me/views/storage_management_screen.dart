import 'package:flutter/material.dart';

import '../../../../app_scope.dart';
import '../../../../data/repositories/chat_repository.dart';
import '../../../core/theme/wechat_theme.dart';
import '../../../core/widgets/weui_widgets.dart';
import 'chat_export_screen.dart';

/// Displays local SQLite & attachment disk usage with safe cleanup options.
class StorageManagementScreen extends StatefulWidget {
  const StorageManagementScreen({super.key});

  @override
  State<StorageManagementScreen> createState() => _StorageManagementScreenState();
}

class _StorageManagementScreenState extends State<StorageManagementScreen> {
  StorageStats? _stats;
  int _mediaBytes = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refresh();
  }

  Future<void> _refresh() async {
    final app = AppScope.of(context);
    final stats = await app.chatRepository.getStorageStats();
    final bytes = await app.mediaStorage.calculateTotalBytes();
    if (mounted) {
      setState(() {
        _stats = stats;
        _mediaBytes = bytes;
      });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final stats = _stats;

    return Scaffold(
      backgroundColor: WeuiColors.bg0,
      appBar: AppBar(
        title: const Text('本地存储与数据管理'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: WeuiColors.fg3),
        ),
      ),
      body: ListView(
        children: [
          WeuiCellGroup(
            title: 'SQLite 数据库统计',
            tips: '星汐 Astide 所有聊天、人物与设置均安全存储在本地 SQLite 数据库中，无需登录账号。',
            insetForm: true,
            children: [
              WeuiCell(
                title: '会话总数',
                trailingText: stats == null ? '...' : '${stats.conversationCount} 个',
              ),
              WeuiCell(
                title: 'DeepSeek 导入会话',
                trailingText: stats == null ? '...' : '${stats.importedConversationCount} 个',
              ),
              WeuiCell(
                title: '人物角色数量',
                trailingText: stats == null ? '...' : '${stats.characterCount} 位',
              ),
              WeuiCell(
                title: '消息总数',
                trailingText: stats == null ? '...' : '${stats.messageCount} 条',
              ),
              WeuiCell(
                title: '本地媒体与附件缓存',
                trailingText: _formatBytes(_mediaBytes),
              ),
            ],
          ),
          WeuiCellGroup(
            title: '数据备份与导出',
            insetForm: true,
            children: [
              WeuiCell(
                title: '导出本地会话记录',
                subtitle: '支持 SQLite、XML、JSON、TXT、Markdown、HTML',
                trailingText: '导出',
                showArrow: true,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ChatExportScreen()),
                  );
                },
              ),
            ],
          ),
          if (stats != null && stats.importedConversationCount > 0)
            WeuiCellGroup(
              insetForm: true,
              children: [
                WeuiCell(
                  title: '清理已导入的 DeepSeek 历史会话',
                  centerTitle: true,
                  titleColor: WeuiColors.red,
                  onTap: () async {
                    final ok = await WeuiDialog.confirm(
                      context,
                      title: '清理导入记录',
                      content: '将删除所有通过 DeepSeek 压缩包导入的 ${stats.importedConversationCount} 个历史会话，不会影响你新建的聊天和人物设定。',
                      confirmText: '清理',
                      destructive: true,
                    );
                    if (!ok) return;
                    await app.chatRepository.clearImportedConversations();
                    await app.reloadConversations();
                    await _refresh();
                    if (!context.mounted) return;
                    showWeuiToast(context, '已清理导入的历史会话');
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }
}
