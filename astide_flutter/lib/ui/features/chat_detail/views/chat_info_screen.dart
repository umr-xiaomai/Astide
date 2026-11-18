import 'package:flutter/material.dart';

import '../../../../app_scope.dart';
import '../../../../domain/models/character_profile.dart';
import '../../../../domain/models/conversation.dart';
import '../../../core/theme/wechat_theme.dart';
import '../../../core/widgets/wechat_avatar.dart';
import '../../../core/widgets/weui_widgets.dart';
import '../../contacts/views/character_form_screen.dart';
import '../../me/views/chat_export_screen.dart';

/// WeChat-style "聊天信息" screen reachable via the `...` button in a chat room.
class ChatInfoScreen extends StatefulWidget {
  const ChatInfoScreen({
    super.key,
    required this.conversation,
    this.character,
  });

  final Conversation conversation;
  final CharacterProfile? character;

  @override
  State<ChatInfoScreen> createState() => _ChatInfoScreenState();
}

class _ChatInfoScreenState extends State<ChatInfoScreen> {
  late Conversation _conversation;
  CharacterProfile? _character;

  @override
  void initState() {
    super.initState();
    _conversation = widget.conversation;
    _character = widget.character;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final isRoleplay = _character != null;

    return Scaffold(
      backgroundColor: WeuiColors.bg0,
      appBar: AppBar(
        title: const Text('聊天信息'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: WeuiColors.fg3),
        ),
      ),
      body: ListView(
        children: [
          Container(
            color: WeuiColors.bg2,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              children: [
                Column(
                  children: [
                    WechatAvatar(
                      name: _conversation.title,
                      imagePath: _character?.avatarPath ?? _conversation.avatarPath,
                      backgroundColor: _character?.avatarColor ?? _conversation.avatarColor,
                      sourceType: _conversation.sourceType,
                      size: 56,
                      radius: 8,
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 80),
                      child: Text(
                        _conversation.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: WeuiColors.fg1),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          WeuiCellGroup(
            children: [
              if (isRoleplay)
                WeuiCell(
                  title: '查看 / 编辑人物设定',
                  subtitle: _character!.relationship.isNotEmpty
                      ? '关系：${_character!.relationship}'
                      : '点击修改角色资料与说话风格',
                  showArrow: true,
                  onTap: () async {
                    final saved = await Navigator.of(context).push<CharacterProfile>(
                      MaterialPageRoute(
                        builder: (_) => CharacterFormScreen(initialCharacter: _character),
                      ),
                    );
                    if (saved != null && mounted) {
                      final updatedConv = _conversation.copyWith(
                        title: saved.displayName,
                        avatarPath: () => saved.avatarPath,
                        avatarColor: saved.avatarColor,
                      );
                      await app.chatRepository.updateConversation(updatedConv);
                      await app.reloadConversations();
                      setState(() {
                        _character = saved;
                        _conversation = updatedConv;
                      });
                    }
                  },
                ),
              WeuiCell(
                title: '会话名称',
                trailingText: _conversation.title,
                showArrow: true,
                onTap: () => _renameConversation(app),
              ),
            ],
          ),
          WeuiCellGroup(
            children: [
              if (!app.isCorePinnedConversation(_conversation))
                WeuiCell(
                  title: '置顶聊天',
                  trailing: WeuiSwitch(
                    value: _conversation.isPinned,
                    onChanged: (val) async {
                      final updated = _conversation.copyWith(isPinned: val);
                      await app.chatRepository.updateConversation(updated);
                      await app.reloadConversations();
                      setState(() => _conversation = updated);
                    },
                  ),
                ),
              WeuiCell(
                title: '消息免打扰',
                trailing: WeuiSwitch(
                  value: _conversation.isMuted,
                  onChanged: (val) async {
                    final updated = _conversation.copyWith(isMuted: val);
                    await app.chatRepository.updateConversation(updated);
                    await app.reloadConversations();
                    setState(() => _conversation = updated);
                  },
                ),
              ),
            ],
          ),
          if (_conversation.sourceType == ConversationSourceType.deepseekImport)
            WeuiCellGroup(
              tips: '可以将这段 DeepSeek 历史主题直接转换为一个新的人物设定继续扮演',
              children: [
                WeuiCell(
                  title: '基于此会话创建角色',
                  titleColor: WeuiColors.link,
                  showArrow: true,
                  onTap: () async {
                    await Navigator.of(context).push<CharacterProfile>(
                      MaterialPageRoute(
                        builder: (_) => CharacterFormScreen(
                          prefillName: _conversation.title,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          WeuiCellGroup(
            children: [
              WeuiCell(
                title: '导出聊天记录',
                subtitle: '导出为 SQLite、XML、JSON、TXT 等格式',
                showArrow: true,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChatExportScreen(
                        initialConversationIds: [_conversation.id],
                      ),
                    ),
                  );
                },
              ),
              WeuiCell(
                title: '清空聊天记录',
                centerTitle: true,
                titleColor: WeuiColors.red,
                onTap: () async {
                  final ok = await WeuiDialog.confirm(
                    context,
                    title: '清空聊天记录',
                    content: '确定要清空与「${_conversation.title}」的所有本地消息吗？此操作不可撤销。',
                    confirmText: '清空',
                    destructive: true,
                  );
                  if (!ok) return;
                  await app.chatRepository.clearConversationMessages(_conversation.id);
                  await app.reloadConversations();
                  if (!context.mounted) return;
                  showWeuiToast(context, '聊天记录已清空');
                  Navigator.of(context).pop(true);
                },
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _renameConversation(AppController app) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => _RenameConversationDialog(initialTitle: _conversation.title),
    );
    if (newName == null || newName.isEmpty) return;

    final updated = _conversation.copyWith(title: newName);
    await app.chatRepository.updateConversation(updated);
    await app.reloadConversations();
    if (mounted) {
      setState(() => _conversation = updated);
    }
  }
}

class _RenameConversationDialog extends StatefulWidget {
  const _RenameConversationDialog({required this.initialTitle});

  final String initialTitle;

  @override
  State<_RenameConversationDialog> createState() => _RenameConversationDialogState();
}

class _RenameConversationDialogState extends State<_RenameConversationDialog> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.initialTitle);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: WeuiColors.bg2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '修改会话名称',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: WeuiColors.bg1,
                borderRadius: BorderRadius.circular(6),
              ),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                decoration: const InputDecoration(border: InputBorder.none),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消', style: TextStyle(color: WeuiColors.fg1)),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(_ctrl.text.trim()),
                  child: const Text('保存', style: TextStyle(color: WeuiColors.link)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
