import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';

import '../../../../app_scope.dart';
import '../../../../data/services/chat_export_service.dart';
import '../../../../domain/models/conversation.dart';
import '../../../core/theme/wechat_theme.dart';
import '../../../core/widgets/weui_widgets.dart';

/// Exports one, selected, or all local conversations into SQLite, XML, JSON, TXT, Markdown, or HTML.
class ChatExportScreen extends StatefulWidget {
  const ChatExportScreen({
    super.key,
    this.initialConversationIds,
  });

  final List<String>? initialConversationIds;

  @override
  State<ChatExportScreen> createState() => _ChatExportScreenState();
}

class _ChatExportScreenState extends State<ChatExportScreen> {
  final Set<String> _selectedIds = {};
  bool _selectionInitialized = false;
  ChatExportFormat _selectedFormat = ChatExportFormat.json;
  bool _includeReasoning = true;
  bool _exporting = false;
  ChatExportArtifact? _lastArtifact;
  String? _lastTempPath;
  String? _lastSavedLocation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_selectionInitialized) return;
    _selectionInitialized = true;
    final app = AppScope.of(context);
    final initial = widget.initialConversationIds;
    if (initial != null && initial.isNotEmpty) {
      _selectedIds.addAll(initial);
    } else {
      _selectedIds.addAll(app.conversations.map((c) => c.id));
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _buildScopeLabel(List<Conversation> all) {
    if (_selectedIds.isEmpty) return '未选择会话';
    if (_selectedIds.length == all.length && all.isNotEmpty) {
      return '全部会话 (${all.length} 个)';
    }
    final picked = all.where((c) => _selectedIds.contains(c.id)).toList();
    if (picked.length == 1) return picked.first.title;
    return '已选 ${picked.length} 个会话';
  }

  Future<ChatExportArtifact?> _generateArtifact(AppController app) async {
    if (_selectedIds.isEmpty) {
      showWeuiToast(context, '请先选择至少一个会话', isError: true);
      return null;
    }
    setState(() => _exporting = true);
    try {
      final selectedList = app.conversations
          .map((c) => c.id)
          .where(_selectedIds.contains)
          .toList();
      final artifact = await app.exportConversations(
        format: _selectedFormat,
        conversationIds: selectedList,
        includeReasoning: _includeReasoning,
      );
      final tempPath = await app.chatExportService.writeTempArtifactFile(artifact);
      if (mounted) {
        setState(() {
          _lastArtifact = artifact;
          _lastTempPath = tempPath;
        });
      }
      return artifact;
    } catch (e) {
      if (mounted) {
        showWeuiToast(
          context,
          '导出失败：${e.toString().replaceFirst('FormatException: ', '')}',
          isError: true,
        );
      }
      return null;
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  Future<void> _exportAndSave(AppController app) async {
    final artifact = await _generateArtifact(app);
    if (artifact == null || !mounted) return;

    try {
      final savedUri = await FilePicker.saveFile(
        fileName: artifact.fileName,
        bytes: artifact.bytes,
        mimeType: artifact.mimeType,
        dialogTitle: '保存导出文件 (${artifact.format.shortLabel})',
      );
      if (!mounted) return;
      if (savedUri == null) {
        showWeuiToast(context, '已取消保存（可从下方结果卡片预览或用其他应用打开）');
        return;
      }
      setState(() {
        _lastSavedLocation = savedUri.toString();
      });
      showWeuiToast(context, '已保存 ${artifact.fileName}');
    } catch (e) {
      if (mounted) {
        showWeuiToast(context, '调用系统保存对话框失败：$e', isError: true);
      }
    }
  }

  Future<void> _openWithOtherApp(AppController app) async {
    final existingTemp = _lastTempPath;
    if (existingTemp != null && File(existingTemp).existsSync()) {
      final res = await OpenFilex.open(existingTemp);
      if (mounted && res.type != ResultType.done) {
        showWeuiToast(context, '无法打开文件：${res.message}', isError: true);
      }
      return;
    }
    final artifact = await _generateArtifact(app);
    if (artifact == null || !mounted || _lastTempPath == null) return;
    final res = await OpenFilex.open(_lastTempPath!);
    if (mounted && res.type != ResultType.done) {
      showWeuiToast(context, '无法打开文件：${res.message}', isError: true);
    }
  }

  Future<void> _pickConversationsSheet(AppController app) async {
    final all = app.conversations;
    final draft = Set<String>.from(_selectedIds);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: WeuiColors.bg1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.72,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      color: WeuiColors.bg2,
                      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '选择要导出的会话',
                              style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setSheetState(() {
                                if (draft.length == all.length) {
                                  draft.clear();
                                } else {
                                  draft
                                    ..clear()
                                    ..addAll(all.map((c) => c.id));
                                }
                              });
                            },
                            child: Text(
                              draft.length == all.length ? '清空全选' : '全选',
                              style: const TextStyle(color: WeuiColors.link),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setSheetState(() {
                                draft
                                  ..clear()
                                  ..addAll(
                                    all
                                        .where(
                                          (c) => c.sourceType != ConversationSourceType.deepseekImport,
                                        )
                                        .map((c) => c.id),
                                  );
                              });
                            },
                            child: const Text(
                              '仅人物对话',
                              style: TextStyle(color: WeuiColors.link),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(height: 0.5, color: WeuiColors.fg3),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: all.length,
                        separatorBuilder: (_, _) => Container(height: 0.5, color: WeuiColors.fg3),
                        itemBuilder: (_, idx) {
                          final conv = all[idx];
                          final checked = draft.contains(conv.id);
                          return CheckboxListTile(
                            value: checked,
                            activeColor: WeuiColors.brand,
                            title: Text(
                              conv.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 15.5, color: WeuiColors.fg0),
                            ),
                            subtitle: conv.lastMessagePreview.isNotEmpty
                                ? Text(
                                    conv.lastMessagePreview,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12.5, color: WeuiColors.fg1),
                                  )
                                : null,
                            onChanged: (val) {
                              setSheetState(() {
                                if (val == true) {
                                  draft.add(conv.id);
                                } else {
                                  draft.remove(conv.id);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                      child: WeuiButton(
                        label: '确定 (${draft.length} 个)',
                        onPressed: () {
                          setState(() {
                            _selectedIds
                              ..clear()
                              ..addAll(draft);
                          });
                          Navigator.of(ctx).pop();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final allConvs = app.conversations;

    return Scaffold(
      backgroundColor: WeuiColors.bg0,
      appBar: AppBar(
        title: const Text('导出本地会话'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: WeuiColors.fg3),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 36),
        children: [
          WeuiCellGroup(
            title: '导出范围与内容',
            insetForm: true,
            children: [
              WeuiCell(
                title: '选择会话',
                trailingText: _buildScopeLabel(allConvs),
                showArrow: true,
                onTap: () => _pickConversationsSheet(app),
              ),
              WeuiCell(
                title: '包含深度思考过程',
                subtitle: '导出模型 Reasoning / Thinking 内容与思考用时',
                trailing: WeuiSwitch(
                  value: _includeReasoning,
                  onChanged: (val) => setState(() => _includeReasoning = val),
                ),
              ),
            ],
          ),
          WeuiCellGroup(
            title: '导出格式',
            tips: '导出文件仅包含所选会话、消息、附件记录及关联人物信息，不包含任何 API Key。',
            insetForm: true,
            children: [
              for (final format in ChatExportFormat.values)
                WeuiCell(
                  title: format.label,
                  subtitle: format.description,
                  trailing: Icon(
                    _selectedFormat == format
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: _selectedFormat == format ? WeuiColors.brand : WeuiColors.fg3,
                    size: 22,
                  ),
                  onTap: () => setState(() => _selectedFormat = format),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Column(
              children: [
                WeuiButton(
                  label: _exporting ? '正在生成导出文件...' : '导出并保存文件',
                  isLoading: _exporting,
                  onPressed: _exporting ? null : () => _exportAndSave(app),
                ),
                const SizedBox(height: 12),
                WeuiButton(
                  label: '生成并用其他应用打开',
                  type: WeuiButtonType.secondary,
                  onPressed: _exporting
                      ? null
                      : () async {
                          final artifact = await _generateArtifact(app);
                          if (artifact != null && mounted) {
                            await _openWithOtherApp(app);
                          }
                        },
                ),
              ],
            ),
          ),
          if (_lastArtifact != null)
            WeuiCellGroup(
              title: '最近一次导出结果',
              insetForm: true,
              children: [
                WeuiCell(title: '文件名', trailingText: _lastArtifact!.fileName),
                WeuiCell(
                  title: '数据统计',
                  trailingText:
                      '${_lastArtifact!.conversationCount} 会话 · ${_lastArtifact!.messageCount} 消息',
                ),
                WeuiCell(
                  title: '文件大小',
                  trailingText: _formatBytes(_lastArtifact!.bytes.length),
                ),
                if (_lastSavedLocation != null && _lastSavedLocation!.isNotEmpty)
                  WeuiCell(
                    title: '保存位置',
                    subtitle: _lastSavedLocation!,
                  ),
                WeuiCell(
                  title: '用其他应用打开 / 分享',
                  centerTitle: true,
                  titleColor: WeuiColors.link,
                  onTap: () => _openWithOtherApp(app),
                ),
                if (!_lastArtifact!.format.isBinary && _lastArtifact!.textPreview.isNotEmpty)
                  WeuiCell(
                    title: '预览导出文本内容',
                    centerTitle: true,
                    titleColor: WeuiColors.brand,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => _ExportTextPreviewScreen(
                            title: _lastArtifact!.fileName,
                            content: _lastArtifact!.textPreview,
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ExportTextPreviewScreen extends StatelessWidget {
  const _ExportTextPreviewScreen({
    required this.title,
    required this.content,
  });

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    final truncated = content.length > 120000
        ? '${content.substring(0, 120000)}\n\n...（文本过长，预览截断，导出文件完整）'
        : content;

    return Scaffold(
      backgroundColor: WeuiColors.bg2,
      appBar: AppBar(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: content));
              showWeuiToast(context, '已复制全部导出文本');
            },
            child: const Text('复制', style: TextStyle(color: WeuiColors.link, fontSize: 15)),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: WeuiColors.fg3),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          truncated,
          style: const TextStyle(
            fontSize: 13.5,
            height: 1.55,
            color: WeuiColors.fg0,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}
