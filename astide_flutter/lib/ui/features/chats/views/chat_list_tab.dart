import 'package:flutter/material.dart';

import '../../../../app_scope.dart';
import '../../../../domain/models/conversation.dart';
import '../../../core/theme/wechat_theme.dart';
import '../../../core/widgets/wechat_avatar.dart';
import '../../../core/widgets/weui_swipe_cell.dart';
import '../../../core/widgets/weui_widgets.dart';
import '../../chat_detail/views/chat_detail_screen.dart';
import '../../contacts/views/character_form_screen.dart';
import '../../me/views/api_settings_screen.dart';
import '../../me/views/chat_export_screen.dart';
import '../../me/views/deepseek_import_screen.dart';
import 'global_search_screen.dart';

/// Tab 1 ("星汐"): WeChat-style conversation list with search, `+` menu, and left-swipe pin/delete.
class ChatListTab extends StatefulWidget {
  const ChatListTab({super.key});

  @override
  State<ChatListTab> createState() => _ChatListTabState();
}

class _ChatListTabState extends State<ChatListTab> {
  String? _swipedConversationId;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final conversations = app.conversations;
    final unread = app.totalUnreadCount;
    final titleText = unread > 0 ? '星汐($unread)' : '星汐';

    return Scaffold(
      backgroundColor: WeuiColors.bg0,
      appBar: AppBar(
        backgroundColor: WeuiColors.bg0,
        automaticallyImplyLeading: false,
        title: Text(titleText),
        actions: [
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search, size: 24),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const GlobalSearchScreen()),
              );
            },
          ),
          PopupMenuButton<String>(
            tooltip: '更多操作',
            color: WeuiColors.bg4,
            offset: const Offset(0, 44),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            icon: const Icon(Icons.add_circle_outline, size: 23),
            onSelected: (value) => _handleMenuSelect(context, app, value),
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'ai_character',
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                    SizedBox(width: 12),
                    Text('一句话创建人物', style: TextStyle(color: Colors.white, fontSize: 15.5)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'new_character',
                child: Row(
                  children: [
                    Icon(Icons.person_add_outlined, color: Colors.white, size: 20),
                    SizedBox(width: 12),
                    Text('填表创建人物', style: TextStyle(color: Colors.white, fontSize: 15.5)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'import_deepseek',
                child: Row(
                  children: [
                    Icon(Icons.download_for_offline_outlined, color: Colors.white, size: 20),
                    SizedBox(width: 12),
                    Text('导入 DeepSeek 历史', style: TextStyle(color: Colors.white, fontSize: 15.5)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'export_chats',
                child: Row(
                  children: [
                    Icon(Icons.upload_file_outlined, color: Colors.white, size: 20),
                    SizedBox(width: 12),
                    Text('导出本地会话', style: TextStyle(color: Colors.white, fontSize: 15.5)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'api_settings',
                child: Row(
                  children: [
                    Icon(Icons.tune, color: Colors.white, size: 20),
                    SizedBox(width: 12),
                    Text('API 与模型设置', style: TextStyle(color: Colors.white, fontSize: 15.5)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: WeuiColors.fg3),
        ),
      ),
      body: conversations.isEmpty
          ? _buildEmptyState(context, app)
          : Container(
              color: WeuiColors.bg2,
              child: ListView.separated(
                itemCount: conversations.length,
                separatorBuilder: (_, _) => Padding(
                  padding: const EdgeInsets.only(left: 76),
                  child: Container(height: 0.5, color: WeuiColors.fg3),
                ),
                itemBuilder: (context, index) {
                  final conv = conversations[index];
                  final isCorePinned = app.isCorePinnedConversation(conv);
                  return WeuiSwipeCell(
                    key: ValueKey('swipe_${conv.id}'),
                    isOpen: _swipedConversationId == conv.id,
                    onSwipeStart: () {
                      if (_swipedConversationId != null && _swipedConversationId != conv.id) {
                        setState(() => _swipedConversationId = null);
                      }
                    },
                    onOpenChanged: (open) {
                      setState(() {
                        if (open) {
                          _swipedConversationId = conv.id;
                        } else if (_swipedConversationId == conv.id) {
                          _swipedConversationId = null;
                        }
                      });
                    },
                    actions: isCorePinned
                        ? [
                            WeuiSwipeAction(
                              label: conv.isMuted ? '开启提醒' : '免打扰',
                              width: 82,
                              backgroundColor: const Color(0xFF8E8E93),
                              onTap: () => app.toggleMuteConversation(conv),
                            ),
                          ]
                        : [
                            WeuiSwipeAction(
                              label: conv.isPinned ? '取消置顶' : '置顶',
                              width: conv.isPinned ? 84 : 74,
                              backgroundColor: const Color(0xFF8E8E93),
                              onTap: () => app.togglePinConversation(conv),
                            ),
                            WeuiSwipeAction(
                              label: '删除',
                              width: 74,
                              backgroundColor: WeuiColors.red,
                              onTap: () => _confirmDeleteConversation(context, app, conv),
                            ),
                          ],
                    child: _ConversationTile(
                      conversation: conv,
                      onTap: () {
                        if (_swipedConversationId != null) {
                          setState(() => _swipedConversationId = null);
                          return;
                        }
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ChatDetailScreen(conversation: conv),
                          ),
                        );
                      },
                      onLongPress: () => _showConversationActions(context, app, conv),
                    ),
                  );
                },
              ),
            ),
    );
  }

  Widget _buildEmptyState(BuildContext context, AppController app) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.chat_bubble_outline, size: 48, color: WeuiColors.fg2),
            const SizedBox(height: 12),
            const Text(
              '还没有聊天会话',
              style: TextStyle(fontSize: 16, color: WeuiColors.fg1),
            ),
            const SizedBox(height: 20),
            WeuiButton(
              label: '和星汐开始聊天',
              fullWidth: false,
              onPressed: () async {
                final conv = await app.createDirectConversation(
                  title: '星汐 Astide',
                  openingLine: '嗨，我在呢，今天想聊点什么呀？',
                );
                if (context.mounted) {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ChatDetailScreen(conversation: conv)),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleMenuSelect(BuildContext context, AppController app, String value) async {
    switch (value) {
      case 'ai_character':
      case 'new_character':
        final created = await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CharacterFormScreen(focusAiPrompt: value == 'ai_character'),
          ),
        );
        if (created != null && context.mounted) {
          final conv = await app.openOrCreateCharacterConversation(created);
          if (context.mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ChatDetailScreen(conversation: conv)),
            );
          }
        }
      case 'import_deepseek':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DeepSeekImportScreen()),
        );
      case 'export_chats':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ChatExportScreen()),
        );
      case 'api_settings':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ApiSettingsScreen()),
        );
    }
  }

  void _showConversationActions(
    BuildContext context,
    AppController app,
    Conversation conv,
  ) {
    final isCorePinned = app.isCorePinnedConversation(conv);
    WeuiActionSheet.show(
      context,
      title: isCorePinned ? '${conv.title}（默认置顶角色）' : conv.title,
      actions: [
        if (!isCorePinned)
          WeuiSheetAction(
            label: conv.isPinned ? '取消置顶' : '置顶聊天',
            onTap: () => app.togglePinConversation(conv),
          ),
        WeuiSheetAction(
          label: conv.isMuted ? '关闭免打扰' : '消息免打扰',
          onTap: () => app.toggleMuteConversation(conv),
        ),
        if (!isCorePinned)
          WeuiSheetAction(
            label: '删除该聊天',
            destructive: true,
            onTap: () => _confirmDeleteConversation(context, app, conv),
          ),
      ],
    );
  }

  Future<void> _confirmDeleteConversation(
    BuildContext context,
    AppController app,
    Conversation conv,
  ) async {
    final ok = await WeuiDialog.confirm(
      context,
      title: '删除聊天',
      content: '确定删除「${conv.title}」及其全部本地消息吗？',
      confirmText: '删除',
      destructive: true,
    );
    if (ok) {
      await app.deleteConversation(conv.id);
    }
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.onTap,
    required this.onLongPress,
  });

  final Conversation conversation;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final bgColor = conversation.isPinned ? WeuiColors.pinnedCellBg : WeuiColors.bg2;
    return Material(
      color: bgColor,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        highlightColor: WeuiColors.activeBg,
        splashColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              WechatAvatar(
                name: conversation.title,
                imagePath: conversation.avatarPath,
                backgroundColor: conversation.avatarColor,
                sourceType: conversation.sourceType,
                unreadCount: conversation.unreadCount,
                size: 48,
                radius: 6,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  conversation.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.w500,
                                    color: WeuiColors.textPrimary,
                                  ),
                                ),
                              ),
                              if (conversation.sourceType ==
                                  ConversationSourceType.deepseekImport) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0x1A4D6BFE),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: const Text(
                                    'DS',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF4D6BFE),
                                    ),
                                  ),
                                ),
                              ] else if (conversation.sourceType ==
                                  ConversationSourceType.roleplay) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0x1A07C160),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: const Text(
                                    '角色',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: WeuiColors.brandPressed,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formatWechatListTime(conversation.lastMessageAt),
                          style: const TextStyle(
                            fontSize: 12,
                            color: WeuiColors.textTimestamp,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            conversation.lastMessagePreview.isNotEmpty
                                ? conversation.lastMessagePreview
                                : '暂无消息',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              color: WeuiColors.textSecondary,
                            ),
                          ),
                        ),
                        if (conversation.isMuted) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.notifications_off_outlined,
                            size: 14,
                            color: WeuiColors.textTimestamp,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
