import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../../app_scope.dart';
import '../../../../domain/models/character_profile.dart';
import '../../../../domain/models/chat_attachment.dart';
import '../../../../domain/models/chat_message.dart';
import '../../../../domain/models/conversation.dart';
import '../../../core/theme/wechat_theme.dart';
import '../../../core/widgets/bubble_tail_painter.dart';
import '../../../core/widgets/wechat_avatar.dart';
import '../../../core/widgets/weui_widgets.dart';
import '../../contacts/views/character_form_screen.dart';
import '../../contacts/views/character_profile_screen.dart';
import '../../me/views/api_settings_screen.dart';
import '../../me/views/user_profile_edit_screen.dart';
import '../view_models/chat_detail_view_model.dart';
import 'chat_info_screen.dart';
import 'file_preview_screen.dart';
import 'image_viewer_screen.dart';

/// Authentic WeChat-style chat room supporting text, images, files, reasoning blocks, and RP bubbles.
class ChatDetailScreen extends StatefulWidget {
  const ChatDetailScreen({
    super.key,
    required this.conversation,
  });

  final Conversation conversation;

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

enum _ComposerPanel { none, emoji, more }

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  late ChatDetailViewModel _viewModel;
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  _ComposerPanel _activePanel = _ComposerPanel.none;
  final Set<String> _expandedThoughts = {};
  String? _lastBottomMsgId;

  static const List<String> _emojis = [
    '😊', '😂', '🥹', '😍', '🥰', '😋', '😜', '🤔',
    '🤗', '🤫', '😳', '🥺', '😭', '😤', '😴', '🤯',
    '👍', '👏', '🙏', '🤝', '❤️', '🧡', '✨', '🔥',
    '🎉', '🌙', '☕', '🍵', '🌸', '🐱', '🐶', '💫',
  ];

  @override
  void initState() {
    super.initState();
    _inputFocusNode.addListener(() {
      if (_inputFocusNode.hasFocus && _activePanel != _ComposerPanel.none) {
        setState(() => _activePanel = _ComposerPanel.none);
      }
    });
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients || !_initializedVm) return;
    final pos = _scrollController.position;
    if (_viewModel.hasMoreHistory &&
        !_viewModel.isLoadingOlder &&
        pos.pixels >= pos.maxScrollExtent - 240) {
      _viewModel.loadOlderMessages();
    }
  }

  bool _initializedVm = false;
  late AppController _appRef;
  int _seenAutonomousEpoch = 0;

  void _ensureVm(BuildContext context) {
    if (_initializedVm) return;
    _initializedVm = true;
    _appRef = AppScope.of(context);
    _seenAutonomousEpoch = _appRef.autonomousUpdateEpoch;
    _appRef.setActiveConversationId(widget.conversation.id);
    _appRef.addListener(_onAppAutonomousUpdate);
    _viewModel = ChatDetailViewModel(
      appController: _appRef,
      conversation: widget.conversation,
    );
    _viewModel.addListener(_onViewModelChanged);
    _viewModel.load();
  }

  void _onAppAutonomousUpdate() {
    if (!mounted) return;
    if (_appRef.autonomousUpdateEpoch != _seenAutonomousEpoch) {
      _seenAutonomousEpoch = _appRef.autonomousUpdateEpoch;
      if (!_viewModel.isStreaming) {
        _viewModel.reloadMeta();
      }
    }
  }

  void _onViewModelChanged() {
    if (!mounted) return;
    final msgs = _viewModel.messages;
    if (msgs.isEmpty) {
      _lastBottomMsgId = null;
      return;
    }
    final bottomId = msgs.last.id;
    if (_lastBottomMsgId == null) {
      _lastBottomMsgId = bottomId;
      return;
    }
    // Only auto-scroll when a new message is appended at the bottom, never during older-page loads.
    if (bottomId != _lastBottomMsgId) {
      _lastBottomMsgId = bottomId;
      if (_scrollController.hasClients && _scrollController.position.pixels > 160) {
        _scrollToBottom(animated: true);
      }
    }
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (animated) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(0.0);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    if (_initializedVm) {
      _appRef.removeListener(_onAppAutonomousUpdate);
      if (_appRef.activeConversationId == widget.conversation.id) {
        _appRef.setActiveConversationId(null);
      }
      _viewModel.removeListener(_onViewModelChanged);
      _viewModel.dispose();
    }
    _inputController.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _ensureVm(context);
    final app = AppScope.of(context);

    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final conv = _viewModel.conversation;
        final title = _viewModel.isStreaming ? '对方正在输入...' : conv.title;

        return Scaffold(
          backgroundColor: WeuiColors.bg0,
          appBar: AppBar(
            backgroundColor: WeuiColors.bg0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              if (_viewModel.isStreaming)
                TextButton(
                  onPressed: _viewModel.stopGenerating,
                  child: const Text(
                    '停止',
                    style: TextStyle(color: WeuiColors.red, fontSize: 15),
                  ),
                )
              else
                IconButton(
                  icon: const Icon(Icons.more_horiz, size: 24),
                  onPressed: () async {
                    final cleared = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => ChatInfoScreen(
                          conversation: _viewModel.conversation,
                          character: _viewModel.character,
                        ),
                      ),
                    );
                    await _viewModel.reloadMeta();
                    if (cleared == true && mounted) {
                      _lastBottomMsgId = null;
                    }
                  },
                ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(0.5),
              child: Container(height: 0.5, color: WeuiColors.fg3),
            ),
          ),
          body: GestureDetector(
            onTap: () {
              _inputFocusNode.unfocus();
              if (_activePanel != _ComposerPanel.none) {
                setState(() => _activePanel = _ComposerPanel.none);
              }
            },
            child: Column(
              children: [
                if (_viewModel.statusNotice != null) _buildNoticeBanner(_viewModel.statusNotice!),
                if (app.activeApiProfile == null || !app.activeApiProfile!.isConfigured)
                  _buildApiMissingBanner(context),
                Expanded(
                  child: _viewModel.isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: WeuiColors.brand,
                            strokeWidth: 2.5,
                          ),
                        )
                      : _buildMessageList(app),
                ),
                _buildPendingAttachmentsBar(),
                _buildInputBar(),
                if (_activePanel == _ComposerPanel.emoji) _buildEmojiTray(),
                if (_activePanel == _ComposerPanel.more) _buildMoreActionTray(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNoticeBanner(String notice) {
    return Container(
      color: const Color(0xFFFFFBE6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: WeuiColors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              notice,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF7A5618)),
            ),
          ),
          GestureDetector(
            onTap: _viewModel.dismissStatusNotice,
            child: const Icon(Icons.close, size: 16, color: WeuiColors.fg1),
          ),
        ],
      ),
    );
  }

  Widget _buildApiMissingBanner(BuildContext context) {
    return Material(
      color: const Color(0xFFFDF2F2),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ApiSettingsScreen()),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: const [
              Icon(Icons.warning_amber_rounded, size: 17, color: WeuiColors.red),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '尚未配置 API Key，点击前往「API 与模型设置」后即可开始对话',
                  style: TextStyle(fontSize: 13, color: WeuiColors.red),
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: WeuiColors.red),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageList(AppController app) {
    final msgs = _viewModel.messages;
    if (msgs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            '发条消息开始和${_viewModel.conversation.title}聊天吧',
            style: const TextStyle(color: WeuiColors.fg2, fontSize: 14),
          ),
        ),
      );
    }

    final showLoaderItem = _viewModel.hasMoreHistory;
    final totalItems = msgs.length + (showLoaderItem ? 1 : 0);
    // Keep short threads top-aligned (like WeChat), while longer threads use pure virtualized reverse SliverList with zero jump.
    final useShrinkWrapForShortChat = !showLoaderItem && msgs.length <= 15;

    final listView = ListView.builder(
      controller: _scrollController,
      reverse: true,
      shrinkWrap: useShrinkWrapForShortChat,
      scrollCacheExtent: const ScrollCacheExtent.pixels(600),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      itemCount: totalItems,
      itemBuilder: (context, reversedIndex) {
        if (showLoaderItem && reversedIndex == msgs.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: _viewModel.isLoadingOlder
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: WeuiColors.brand),
                    )
                  : const Text(
                      '上拉加载更早消息',
                      style: TextStyle(fontSize: 12, color: WeuiColors.fg2),
                    ),
            ),
          );
        }

        final origIndex = msgs.length - 1 - reversedIndex;
        final msg = msgs[origIndex];
        final showTimestamp = origIndex == 0 ||
            msg.createdAt.difference(msgs[origIndex - 1].createdAt).inMinutes >= 5;

        return RepaintBoundary(
          key: ValueKey(msg.id),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showTimestamp)
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 14),
                  child: Center(
                    child: Text(
                      formatWechatChatTime(msg.createdAt),
                      style: const TextStyle(
                        color: WeuiColors.textTimestamp,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              _buildMessageRow(context, app, msg),
              const SizedBox(height: 14),
            ],
          ),
        );
      },
    );

    if (useShrinkWrapForShortChat) {
      return Align(
        alignment: Alignment.topCenter,
        child: listView,
      );
    }
    return listView;
  }

  Future<void> _openOpponentProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CharacterProfileScreen(
          character: _viewModel.character,
          conversation: _viewModel.conversation,
          fromChat: true,
        ),
      ),
    );
    await _viewModel.reloadMeta();
  }

  Widget _buildMessageRow(BuildContext context, AppController app, ChatMessage msg) {
    if (msg.role == MessageRole.system) {
      return GestureDetector(
        onLongPress: () => _showMessageActions(context, msg),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
          child: Center(
            child: Text(
              msg.content,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: WeuiColors.textTimestamp,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
        ),
      );
    }

    final isUser = msg.isUser;
    final avatarWidget = WechatAvatar(
      name: isUser ? app.settings.userNickname : _viewModel.conversation.title,
      imagePath: isUser
          ? app.settings.userAvatarPath
          : (_viewModel.character?.avatarPath ?? _viewModel.conversation.avatarPath),
      backgroundColor: isUser
          ? 0xFF576B95
          : (_viewModel.character?.avatarColor ?? _viewModel.conversation.avatarColor),
      sourceType: isUser ? null : _viewModel.conversation.sourceType,
      isUserSelf: isUser,
      size: 40,
      radius: 5,
    );

    final avatar = isUser
        ? GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const UserProfileEditScreen()),
              );
            },
            child: avatarWidget,
          )
        : _ChatInteractiveAvatar(
            onTap: _openOpponentProfile,
            onDoubleTap: () {
              unawaited(app.autonomousService.triggerPokeVibration());
              unawaited(_viewModel.pokeOpponent());
            },
            child: avatarWidget,
          );

    final contentColumn = Column(
      crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        for (final att in msg.attachments) ...[
          _buildAttachmentBubble(context, att, isUser: isUser),
          if (msg.content.trim().isNotEmpty || att != msg.attachments.last)
            const SizedBox(height: 8),
        ],
        if (msg.status == MessageStatus.error && msg.content.trim().isEmpty)
          _buildErrorBubble(msg)
        else if (msg.content.trim().isNotEmpty ||
            msg.hasReasoning ||
            msg.status == MessageStatus.streaming)
          _buildTextBubble(context, msg, isUser: isUser),
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: isUser
          ? [
              if (msg.status == MessageStatus.error)
                Padding(
                  padding: const EdgeInsets.only(top: 10, right: 8),
                  child: GestureDetector(
                    onTap: () => _viewModel.retryMessage(msg),
                    child: const Icon(Icons.error, color: WeuiColors.red, size: 22),
                  ),
                ),
              Flexible(child: contentColumn),
              const SizedBox(width: 6),
              avatar,
            ]
          : [
              avatar,
              const SizedBox(width: 6),
              Flexible(child: contentColumn),
              if (msg.status == MessageStatus.error)
                Padding(
                  padding: const EdgeInsets.only(top: 10, left: 8),
                  child: GestureDetector(
                    onTap: () => _viewModel.retryMessage(msg),
                    child: const Icon(Icons.error, color: WeuiColors.red, size: 22),
                  ),
                ),
            ],
    );
  }

  Widget _buildAttachmentBubble(
    BuildContext context,
    ChatAttachment att, {
    required bool isUser,
  }) {
    if (att.isImage && att.filePath != null && File(att.filePath!).existsSync()) {
      // Matches WeChat screenshots: borderless rounded thumbnail without green/white bubble.
      return GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ImageViewerScreen(
                imagePath: att.filePath!,
                title: att.fileName,
              ),
            ),
          );
        },
        child: Padding(
          padding: EdgeInsets.only(left: isUser ? 0 : 6, right: isUser ? 6 : 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 205, maxHeight: 260),
              child: Image.file(
                File(att.filePath!),
                fit: BoxFit.cover,
                cacheWidth: 600,
              ),
            ),
          ),
        ),
      );
    }

    // Authentic WeChat white file card bubble.
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => FilePreviewScreen(attachment: att)),
        );
      },
      child: WechatSpeechBubble(
        isUser: isUser,
        color: WeuiColors.bg2,
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: 215,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      att.fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                        color: WeuiColors.fg0,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      att.formattedSize,
                      style: const TextStyle(fontSize: 12, color: WeuiColors.fg1),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 40,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF10AEFF).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.center,
                child: Text(
                  att.fileExtension,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: WeuiColors.indigo,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBubble(ChatMessage msg) {
    final app = AppScope.of(context);
    final missingKey = app.activeApiProfile == null || !app.activeApiProfile!.isConfigured;

    return GestureDetector(
      onTap: () {
        if (missingKey) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ApiSettingsScreen()),
          );
        } else {
          _viewModel.retryMessage(msg);
        }
      },
      child: WechatSpeechBubble(
        isUser: false,
        color: WeuiColors.bg2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              msg.errorMessage.isNotEmpty ? msg.errorMessage : '发送失败，点击重试',
              style: const TextStyle(fontSize: 14.5, color: WeuiColors.red, height: 1.4),
            ),
            const SizedBox(height: 6),
            Text(
              missingKey ? '去配置 API Key' : '点击重试',
              style: const TextStyle(
                fontSize: 13,
                color: WeuiColors.link,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextBubble(
    BuildContext context,
    ChatMessage msg, {
    required bool isUser,
  }) {
    final bubbleColor = isUser ? WeuiColors.lightGreen : WeuiColors.bg2;
    final isExpanded = _expandedThoughts.contains(msg.id);

    return GestureDetector(
      onLongPress: () => _showMessageActions(context, msg),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        child: WechatSpeechBubble(
          isUser: isUser,
          color: bubbleColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isUser && msg.hasReasoning) ...[
                GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isExpanded) {
                        _expandedThoughts.remove(msg.id);
                      } else {
                        _expandedThoughts.add(msg.id);
                      }
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: WeuiColors.bg1,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.psychology_outlined, size: 15, color: WeuiColors.fg1),
                        const SizedBox(width: 4),
                        Text(
                          msg.thinkingSeconds > 0
                              ? '已深度思考 (${msg.thinkingSeconds.toStringAsFixed(1)}s)'
                              : '已深度思考',
                          style: const TextStyle(fontSize: 12.5, color: WeuiColors.fg1),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                          size: 16,
                          color: WeuiColors.fg1,
                        ),
                      ],
                    ),
                  ),
                ),
                if (isExpanded) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.only(left: 8),
                    decoration: const BoxDecoration(
                      border: Border(
                        left: BorderSide(color: WeuiColors.fg3, width: 2),
                      ),
                    ),
                    child: SelectableText(
                      msg.reasoningContent,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: WeuiColors.fg1,
                      ),
                    ),
                  ),
                ],
                if (msg.content.trim().isNotEmpty) const SizedBox(height: 8),
              ],
              if (msg.status == MessageStatus.streaming && msg.content.trim().isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: WeuiColors.brand,
                    ),
                  ),
                )
              else if (msg.content.trim().isNotEmpty)
                _buildMessageTextBody(msg, isUser: isUser),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageTextBody(ChatMessage msg, {required bool isUser}) {
    if (isUser || !_looksLikeMarkdown(msg.content)) {
      return SelectableText(
        msg.content,
        style: const TextStyle(
          fontSize: 16,
          height: 1.45,
          color: WeuiColors.textPrimary,
        ),
      );
    }

    return MarkdownBody(
      data: msg.content,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: const TextStyle(fontSize: 15.5, height: 1.5, color: WeuiColors.textPrimary),
        h1: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: WeuiColors.textPrimary),
        h2: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: WeuiColors.textPrimary),
        h3: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: WeuiColors.textPrimary),
        code: const TextStyle(
          fontSize: 13.5,
          backgroundColor: WeuiColors.bg1,
          color: Color(0xFF24292E),
        ),
        codeblockDecoration: BoxDecoration(
          color: WeuiColors.bg1,
          borderRadius: BorderRadius.circular(6),
        ),
        blockquoteDecoration: const BoxDecoration(
          border: Border(left: BorderSide(color: WeuiColors.brand, width: 3)),
        ),
      ),
    );
  }

  bool _looksLikeMarkdown(String text) {
    return text.contains('```') ||
        text.contains('**') ||
        text.contains('##') ||
        text.contains('\n- ') ||
        text.contains('\n1. ');
  }

  void _showMessageActions(BuildContext context, ChatMessage msg) {
    final isLastAssistant =
        !msg.isUser && _viewModel.messages.isNotEmpty && _viewModel.messages.last.id == msg.id;
    WeuiActionSheet.show(
      context,
      actions: [
        if (msg.content.trim().isNotEmpty)
          WeuiSheetAction(
            label: '复制内容',
            onTap: () {
              Clipboard.setData(ClipboardData(text: msg.content));
              showWeuiToast(context, '已复制到剪贴板');
            },
          ),
        if (isLastAssistant)
          WeuiSheetAction(
            label: '重新生成回复',
            onTap: () => _viewModel.regenerateLastReply(),
          ),
        WeuiSheetAction(
          label: '删除该消息',
          destructive: true,
          onTap: () => _viewModel.deleteMessage(msg),
        ),
      ],
    );
  }

  Widget _buildPendingAttachmentsBar() {
    final pending = _viewModel.pendingAttachments;
    if (pending.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: WeuiColors.bg1,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final item in pending)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (item.isImage)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(
                          File(item.filePath),
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                        ),
                      )
                    else
                      Container(
                        width: 140,
                        height: 56,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: WeuiColors.bg2,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: WeuiColors.fg3, width: 0.5),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.description_outlined, size: 22, color: WeuiColors.indigo),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                item.fileName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, color: WeuiColors.fg0),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Positioned(
                      top: -6,
                      right: -6,
                      child: GestureDetector(
                        onTap: () => _viewModel.removePendingAttachment(item.id),
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: const BoxDecoration(
                            color: Color(0xCC000000),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, size: 12, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      decoration: const BoxDecoration(
        color: WeuiColors.bg1,
        border: Border(top: BorderSide(color: WeuiColors.fg3, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        bottom: _activePanel == _ComposerPanel.none,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 38, maxHeight: 112),
                  decoration: BoxDecoration(
                    color: WeuiColors.bg2,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  child: TextField(
                    controller: _inputController,
                    focusNode: _inputFocusNode,
                    maxLines: 5,
                    minLines: 1,
                    textInputAction: TextInputAction.newline,
                    style: const TextStyle(fontSize: 16, color: WeuiColors.fg0, height: 1.35),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: GestureDetector(
                  onTap: () => _togglePanel(_ComposerPanel.emoji),
                  child: Icon(
                    _activePanel == _ComposerPanel.emoji
                        ? Icons.keyboard_alt_outlined
                        : Icons.sentiment_satisfied_alt_outlined,
                    size: 29,
                    color: WeuiColors.fg0,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _inputController,
                builder: (_, val, _) {
                  final canSend = val.text.trim().isNotEmpty ||
                      _viewModel.pendingAttachments.isNotEmpty;
                  if (canSend && !_viewModel.isStreaming) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: SizedBox(
                        height: 34,
                        child: Material(
                          color: WeuiColors.brand,
                          borderRadius: BorderRadius.circular(5),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(5),
                            onTap: _handleSend,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 14),
                              child: Center(
                                child: Text(
                                  '发送',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: GestureDetector(
                      onTap: () => _togglePanel(_ComposerPanel.more),
                      child: const Icon(
                        Icons.add_circle_outline,
                        size: 29,
                        color: WeuiColors.fg0,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _togglePanel(_ComposerPanel target) {
    if (_activePanel == target) {
      setState(() => _activePanel = _ComposerPanel.none);
      _inputFocusNode.requestFocus();
    } else {
      _inputFocusNode.unfocus();
      setState(() => _activePanel = target);
      _scrollToBottom();
    }
  }

  Future<void> _handleSend() async {
    final text = _inputController.text;
    _inputController.clear();
    await _viewModel.sendMessage(text);
  }

  Widget _buildEmojiTray() {
    return Container(
      height: 230,
      decoration: const BoxDecoration(
        color: WeuiColors.bg1,
        border: Border(top: BorderSide(color: WeuiColors.fg3, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 8,
            mainAxisSpacing: 12,
            crossAxisSpacing: 8,
          ),
          itemCount: _emojis.length,
          itemBuilder: (context, index) {
            final emoji = _emojis[index];
            return GestureDetector(
              onTap: () {
                final text = _inputController.text;
                final sel = _inputController.selection;
                final start = sel.start >= 0 ? sel.start : text.length;
                final end = sel.end >= 0 ? sel.end : text.length;
                final next = text.replaceRange(start, end, emoji);
                _inputController.value = TextEditingValue(
                  text: next,
                  selection: TextSelection.collapsed(offset: start + emoji.length),
                );
              },
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 26)),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Attachment & chat action grid mirroring screenshot 4, containing ONLY working features.
  Widget _buildMoreActionTray() {
    final actions = <({IconData icon, String label, VoidCallback onTap})>[
      (
        icon: Icons.photo_outlined,
        label: '相册',
        onTap: () async {
          await _viewModel.pickFromGallery();
          setState(() => _activePanel = _ComposerPanel.none);
        },
      ),
      (
        icon: Icons.camera_alt_outlined,
        label: '拍摄',
        onTap: () async {
          await _viewModel.pickFromCamera();
          setState(() => _activePanel = _ComposerPanel.none);
        },
      ),
      (
        icon: Icons.folder_open_outlined,
        label: '文件',
        onTap: () async {
          await _viewModel.pickDocuments();
          setState(() => _activePanel = _ComposerPanel.none);
        },
      ),
      if (_viewModel.character != null)
        (
          icon: Icons.person_outline,
          label: '人物设定',
          onTap: () async {
            final saved = await Navigator.of(context).push<CharacterProfile>(
              MaterialPageRoute(
                builder: (_) => CharacterFormScreen(initialCharacter: _viewModel.character),
              ),
            );
            if (saved != null) {
              await _viewModel.reloadMeta();
            }
          },
        )
      else
        (
          icon: Icons.refresh_rounded,
          label: '重新生成',
          onTap: () async {
            setState(() => _activePanel = _ComposerPanel.none);
            await _viewModel.regenerateLastReply();
          },
        ),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: WeuiColors.bg1,
        border: Border(top: BorderSide(color: WeuiColors.fg3, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final item in actions)
                GestureDetector(
                  onTap: item.onTap,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: WeuiColors.bg2,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(item.icon, size: 28, color: WeuiColors.fg0),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.label,
                        style: const TextStyle(fontSize: 12, color: WeuiColors.fg1),
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

/// Interactive opponent avatar supporting single-tap profile view and double-tap haptic poke shake.
class _ChatInteractiveAvatar extends StatefulWidget {
  const _ChatInteractiveAvatar({
    required this.onTap,
    required this.onDoubleTap,
    required this.child,
  });

  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final Widget child;

  @override
  State<_ChatInteractiveAvatar> createState() => _ChatInteractiveAvatarState();
}

class _ChatInteractiveAvatarState extends State<_ChatInteractiveAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pokeCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  late final Animation<double> _shakeOffset = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: -4.0), weight: 25),
    TweenSequenceItem(tween: Tween(begin: -4.0, end: 4.5), weight: 30),
    TweenSequenceItem(tween: Tween(begin: 4.5, end: -2.0), weight: 25),
    TweenSequenceItem(tween: Tween(begin: -2.0, end: 0.0), weight: 20),
  ]).animate(CurvedAnimation(parent: _pokeCtrl, curve: Curves.easeOut));

  @override
  void dispose() {
    _pokeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onDoubleTap: () {
        _pokeCtrl.forward(from: 0.0);
        widget.onDoubleTap();
      },
      child: AnimatedBuilder(
        animation: _shakeOffset,
        builder: (context, child) => Transform.translate(
          offset: Offset(_shakeOffset.value, 0),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}
