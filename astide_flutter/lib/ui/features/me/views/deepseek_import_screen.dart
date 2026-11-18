import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../app_scope.dart';
import '../../../../domain/models/deepseek_import.dart';
import '../../../core/theme/wechat_theme.dart';
import '../../../core/widgets/weui_widgets.dart';

/// Imports DeepSeek official client export `.zip` archives from URL or local file into SQLite.
class DeepSeekImportScreen extends StatefulWidget {
  const DeepSeekImportScreen({super.key});

  @override
  State<DeepSeekImportScreen> createState() => _DeepSeekImportScreenState();
}

class _DeepSeekImportScreenState extends State<DeepSeekImportScreen> {
  final _urlCtrl = TextEditingController();
  bool _importing = false;
  DeepSeekImportProgress? _progress;
  DeepSeekImportResult? _result;
  String? _error;

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _importFromUrl() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      showWeuiToast(context, '请先粘贴 DeepSeek 导出压缩包 URL', isError: true);
      return;
    }
    final app = AppScope.of(context);
    setState(() {
      _importing = true;
      _error = null;
      _result = null;
      _progress = const DeepSeekImportProgress(stage: '准备连接...', progress: 0.02);
    });

    try {
      final parsed = await app.deepSeekImportService.parseFromUrl(
        url,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      await _persistImported(app, parsed.userInfo, parsed.sessions);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('FormatException: ', ''));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _importFromLocalZip() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    final path = picked?.path;
    if (path == null) return;

    if (!mounted) return;
    final app = AppScope.of(context);
    setState(() {
      _importing = true;
      _error = null;
      _result = null;
      _progress = const DeepSeekImportProgress(stage: '准备读取本地文件...', progress: 0.1);
    });

    try {
      final parsed = await app.deepSeekImportService.parseFromZipFile(
        path,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      await _persistImported(app, parsed.userInfo, parsed.sessions);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('FormatException: ', ''));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _persistImported(
    AppController app,
    DeepSeekUserInfo userInfo,
    List<ParsedDeepSeekSession> sessions,
  ) async {
    if (mounted) {
      setState(() {
        _progress = const DeepSeekImportProgress(
          stage: '正在写入本地 SQLite 数据库...',
          progress: 0.94,
        );
      });
    }

    final summary = await app.chatRepository.importDeepSeekSessions(
      userInfo: userInfo,
      sessions: sessions,
    );
    await app.reloadConversations();

    if (mounted) {
      setState(() {
        _progress = const DeepSeekImportProgress(stage: '导入完成', progress: 1.0);
        _result = summary;
      });
      showWeuiToast(context, '成功导入 ${summary.importedConversations} 个历史会话');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WeuiColors.bg0,
      appBar: AppBar(
        title: const Text('导入 DeepSeek 历史'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: WeuiColors.fg3),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          WeuiCellGroup(
            title: '从导出链接导入',
            tips: '在 DeepSeek 官方 App / 网页端「设置 -> 隐私与数据 -> 导出数据」生成导出文件后，复制下载链接粘贴到下方，会自动解析会话、深度思考与图片附件。',
            insetForm: true,
            children: [
              WeuiFormRow(
                label: '导出 URL',
                controller: _urlCtrl,
                hintText: 'https://deepseek-chat-history-exports-...zip?...',
                vertical: true,
                minLines: 3,
                maxLines: 6,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
            child: Column(
              children: [
                WeuiButton(
                  label: _importing ? '正在导入...' : '从 URL 下载并导入',
                  isLoading: _importing,
                  onPressed: _importing ? null : _importFromUrl,
                ),
                const SizedBox(height: 12),
                WeuiButton(
                  label: '选择本地 .zip 导出包导入',
                  type: WeuiButtonType.secondary,
                  onPressed: _importing ? null : _importFromLocalZip,
                ),
              ],
            ),
          ),
          if (_progress != null)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: WeuiColors.bg2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: WeuiColors.fg3, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _progress!.stage,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                      Text(
                        '${(_progress!.progress * 100).toInt()}%',
                        style: const TextStyle(fontSize: 13.5, color: WeuiColors.brand),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _progress!.progress,
                      minHeight: 6,
                      backgroundColor: WeuiColors.fg5,
                      color: WeuiColors.brand,
                    ),
                  ),
                  if (_progress!.detail.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _progress!.detail,
                      style: const TextStyle(fontSize: 12.5, color: WeuiColors.fg1),
                    ),
                  ],
                ],
              ),
            ),
          if (_error != null)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFDF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0x44FA5151)),
              ),
              child: Text(
                '导入失败：$_error',
                style: const TextStyle(color: WeuiColors.red, fontSize: 14, height: 1.4),
              ),
            ),
          if (_result != null)
            WeuiCellGroup(
              title: '导入结果',
              insetForm: true,
              children: [
                WeuiCell(title: '新增会话', trailingText: '${_result!.importedConversations} 个'),
                WeuiCell(title: '消息条数', trailingText: '${_result!.importedMessages} 条'),
                WeuiCell(title: '图片附件', trailingText: '${_result!.importedImages} 张'),
                if (_result!.skippedDuplicates > 0)
                  WeuiCell(title: '跳过重复会话', trailingText: '${_result!.skippedDuplicates} 个'),
                WeuiCell(
                  title: '回到聊天列表查看',
                  centerTitle: true,
                  titleColor: WeuiColors.link,
                  onTap: () {
                    AppScope.of(context).setTabIndex(0);
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }
}
