import 'package:flutter/material.dart';

import '../../../../app_scope.dart';
import '../../../../domain/models/character_profile.dart';
import '../../../../domain/models/conversation.dart';
import '../../../../domain/models/moment_post.dart';
import '../../../core/theme/wechat_theme.dart';
import '../../../core/widgets/wechat_avatar.dart';
import '../../../core/widgets/weui_widgets.dart';
import '../../chat_detail/views/chat_detail_screen.dart';
import '../../chat_detail/views/image_viewer_screen.dart';
import '../../discover/views/moments_screen.dart';
import 'character_form_screen.dart';

/// WeChat-style opponent homepage ("个人主页") for roleplay characters, core 星汐 Astide, or imported chats.
class CharacterProfileScreen extends StatefulWidget {
  const CharacterProfileScreen({
    super.key,
    this.character,
    this.conversation,
    this.fromChat = false,
  }) : assert(character != null || conversation != null);

  final CharacterProfile? character;
  final Conversation? conversation;
  final bool fromChat;

  @override
  State<CharacterProfileScreen> createState() => _CharacterProfileScreenState();
}

class _CharacterProfileScreenState extends State<CharacterProfileScreen> {
  CharacterProfile? _character;

  @override
  void initState() {
    super.initState();
    _character = widget.character;
  }

  List<MomentPost> _authorMoments(AppController app, {required bool isCoreAstide}) {
    final char = _character;
    if (char != null) {
      return app.moments
          .where((m) => m.authorId == char.id || m.authorName == char.displayName || m.authorName == char.name)
          .toList();
    }
    if (isCoreAstide) {
      return app.moments
          .where((m) => m.authorId == 'astide_core' || m.authorName.contains('星汐'))
          .toList();
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final conv = widget.conversation;
    final char = _character;
    final isImported = char == null && conv?.sourceType == ConversationSourceType.deepseekImport;
    final isCoreAstide = char == null && !isImported;

    final displayName = char?.displayName ?? conv?.title ?? '星汐 Astide';
    final avatarPath = char?.avatarPath ??
        conv?.avatarPath ??
        (isCoreAstide ? WechatAvatar.coreAstideAvatarAsset : null);
    final avatarColor = char?.avatarColor ?? conv?.avatarColor ?? 0xFF07C160;
    final sourceType = conv?.sourceType ?? ConversationSourceType.roleplay;

    final meta = char != null
        ? [
            if (char.gender.isNotEmpty) char.gender,
            if (char.age.isNotEmpty) char.age,
            if (char.occupation.isNotEmpty) char.occupation,
          ].join(' · ')
        : (isImported ? 'DeepSeek 官方历史会话' : '星汐号：astide_core · 默认伴聊好友');

    final moments = _authorMoments(app, isCoreAstide: isCoreAstide);

    return Scaffold(
      backgroundColor: WeuiColors.bg0,
      appBar: AppBar(
        title: const Text('对方主页'),
        actions: [
          if (char != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 22),
              onPressed: () async {
                final updated = await Navigator.of(context).push<CharacterProfile>(
                  MaterialPageRoute(
                    builder: (_) => CharacterFormScreen(initialCharacter: char),
                  ),
                );
                if (updated != null && mounted) {
                  setState(() => _character = updated);
                }
              },
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: WeuiColors.fg3),
        ),
      ),
      body: ListView(
        children: [
          Container(
            color: WeuiColors.bg2,
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
            child: Row(
              children: [
                GestureDetector(
                  onTap: avatarPath != null && avatarPath.isNotEmpty
                      ? () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ImageViewerScreen(
                                imagePath: avatarPath,
                                title: displayName,
                              ),
                            ),
                          );
                        }
                      : null,
                  child: WechatAvatar(
                    name: displayName,
                    imagePath: avatarPath,
                    backgroundColor: avatarColor,
                    sourceType: sourceType,
                    size: 64,
                    radius: 8,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: WeuiColors.fg0,
                        ),
                      ),
                      if (char != null && char.remark.isNotEmpty && char.remark != char.name)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '原名：${char.name}',
                            style: const TextStyle(fontSize: 13.5, color: WeuiColors.fg1),
                          ),
                        ),
                      if (meta.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            meta,
                            style: const TextStyle(fontSize: 13.5, color: WeuiColors.fg1),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (char != null)
            WeuiCellGroup(
              children: [
                if (char.relationship.isNotEmpty)
                  WeuiCell(title: '与我的关系', trailingText: char.relationship),
                if (char.personality.isNotEmpty)
                  WeuiCell(title: '性格特点', subtitle: char.personality),
                if (char.backstory.isNotEmpty)
                  WeuiCell(title: '背景故事', subtitle: char.backstory),
                if (char.speechStyle.isNotEmpty)
                  WeuiCell(title: '说话风格', subtitle: char.speechStyle),
              ],
            )
          else if (isCoreAstide)
            WeuiCellGroup(
              children: [
                const WeuiCell(title: '角色定位', trailingText: '默认置顶好友'),
                WeuiCell(
                  title: '人物设定',
                  subtitle: app.settings.defaultAssistantPrompt,
                ),
              ],
            )
          else if (conv != null)
            WeuiCellGroup(
              children: [
                const WeuiCell(title: '会话来源', trailingText: 'DeepSeek 导入'),
                if (conv.contextSummary.trim().isNotEmpty)
                  WeuiCell(title: '记忆摘要', subtitle: conv.contextSummary.trim()),
              ],
            ),
          if (!isImported)
            WeuiCellGroup(
              children: [
                WeuiCell(
                  title: '朋友圈',
                  subtitle: moments.isEmpty
                      ? '暂无公开发布的朋友圈动态'
                      : moments.first.content.replaceAll('\n', ' '),
                  trailingText: moments.isEmpty ? null : '${moments.length} 条动态',
                  showArrow: true,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const MomentsScreen()),
                    );
                  },
                ),
              ],
            ),
          WeuiCellGroup(
            children: [
              WeuiCell(
                title: '发消息',
                centerTitle: true,
                titleColor: WeuiColors.link,
                onTap: () async {
                  if (widget.fromChat) {
                    Navigator.of(context).pop();
                    return;
                  }
                  final targetConv = char != null
                      ? await app.openOrCreateCharacterConversation(char)
                      : (conv ?? await app.getCoreAstideConversation());
                  if (context.mounted) {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => ChatDetailScreen(conversation: targetConv)),
                    );
                  }
                },
              ),
            ],
          ),
          if (isImported && conv != null)
            WeuiCellGroup(
              children: [
                WeuiCell(
                  title: '基于此会话创建角色',
                  centerTitle: true,
                  titleColor: WeuiColors.brand,
                  onTap: () async {
                    final created = await Navigator.of(context).push<CharacterProfile>(
                      MaterialPageRoute(
                        builder: (_) => CharacterFormScreen(prefillName: conv.title),
                      ),
                    );
                    if (created != null && context.mounted) {
                      final newConv = await app.openOrCreateCharacterConversation(created);
                      if (context.mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => ChatDetailScreen(conversation: newConv)),
                          (route) => route.isFirst,
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          if (char != null)
            WeuiCellGroup(
              children: [
                WeuiCell(
                  title: '删除人物',
                  centerTitle: true,
                  titleColor: WeuiColors.red,
                  onTap: () async {
                    final ok = await WeuiDialog.confirm(
                      context,
                      title: '删除人物',
                      content: '确定要删除「${char.displayName}」的人物设定吗？已有聊天记录将保留在会话列表中。',
                      confirmText: '删除',
                      destructive: true,
                    );
                    if (!ok || !context.mounted) return;
                    await app.deleteCharacter(char.id);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
