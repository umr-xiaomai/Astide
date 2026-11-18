import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';

import '../../../../domain/models/chat_attachment.dart';
import '../../../core/theme/wechat_theme.dart';
import '../../../core/widgets/weui_widgets.dart';

/// Displays attachment metadata, extracted text preview, and an option to open via system viewer.
class FilePreviewScreen extends StatelessWidget {
  const FilePreviewScreen({super.key, required this.attachment});

  final ChatAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final hasFile = attachment.filePath != null && File(attachment.filePath!).existsSync();
    final hasText = attachment.extractedText.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: WeuiColors.bg0,
      appBar: AppBar(
        title: const Text('文件详情'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: WeuiColors.fg3),
        ),
      ),
      body: ListView(
        children: [
          Container(
            color: WeuiColors.bg2,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 76,
                  decoration: BoxDecoration(
                    color: const Color(0xFF10AEFF).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF10AEFF).withValues(alpha: 0.3)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    attachment.fileExtension,
                    style: const TextStyle(
                      color: WeuiColors.indigo,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  attachment.fileName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    color: WeuiColors.fg0,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${attachment.formattedSize} · ${attachment.mimeType}',
                  style: const TextStyle(fontSize: 13.5, color: WeuiColors.fg1),
                ),
                if (hasFile) ...[
                  const SizedBox(height: 20),
                  WeuiButton(
                    label: '用其他应用打开',
                    onPressed: () async {
                      final res = await OpenFilex.open(attachment.filePath!);
                      if (context.mounted && res.type != ResultType.done) {
                        showWeuiToast(context, '无法打开文件: ${res.message}', isError: true);
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
          if (hasText)
            WeuiCellGroup(
              title: '提取的文本内容（已随消息发送给 AI）',
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SelectableText(
                        attachment.extractedText,
                        style: const TextStyle(
                          fontSize: 14.5,
                          height: 1.55,
                          color: WeuiColors.fg0,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: attachment.extractedText));
                            showWeuiToast(context, '已复制提取文本');
                          },
                          child: const Text('复制文本', style: TextStyle(color: WeuiColors.link)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
