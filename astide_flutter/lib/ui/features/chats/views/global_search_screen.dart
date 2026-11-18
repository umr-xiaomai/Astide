import 'package:flutter/material.dart';

import '../../../../app_scope.dart';
import '../../../../data/repositories/chat_repository.dart';
import '../../../core/theme/wechat_theme.dart';
import '../../../core/widgets/wechat_avatar.dart';
import '../../../core/widgets/weui_widgets.dart';
import '../../chat_detail/views/chat_detail_screen.dart';
import '../../contacts/views/character_profile_screen.dart';

/// Real local full-text search across conversations, characters, and message history.
class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  GlobalSearchResults _results = const GlobalSearchResults();
  String _query = '';

  Future<void> _onQueryChanged(String value) async {
    final trimmed = value.trim();
    _query = trimmed;
    if (trimmed.isEmpty) {
      setState(() => _results = const GlobalSearchResults());
      return;
    }
    final app = AppScope.of(context);
    final res = await app.chatRepository.searchAll(trimmed);
    if (mounted && _query == trimmed) {
      setState(() => _results = res);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WeuiColors.bg0,
      body: SafeArea(
        child: Column(
          children: [
            WeuiSearchBar(
              controller: _searchController,
              hintText: '搜索聊天记录、人物、会话',
              autofocus: true,
              onChanged: _onQueryChanged,
              onCancel: () => Navigator.of(context).pop(),
            ),
            Container(height: 0.5, color: WeuiColors.fg3),
            Expanded(
              child: _query.isEmpty
                  ? const Center(
                      child: Text(
                        '输入关键词搜索本地聊天记录与人物',
                        style: TextStyle(color: WeuiColors.fg2, fontSize: 14),
                      ),
                    )
                  : _results.isEmpty
                      ? const Center(
                          child: Text(
                            '未找到相关内容',
                            style: TextStyle(color: WeuiColors.fg2, fontSize: 15),
                          ),
                        )
                      : ListView(
                          children: [
                            if (_results.characters.isNotEmpty)
                              WeuiCellGroup(
                                title: '人物角色',
                                children: [
                                  for (final char in _results.characters)
                                    WeuiCell(
                                      title: char.displayName,
                                      subtitle: char.personality,
                                      leading: WechatAvatar(
                                        name: char.displayName,
                                        imagePath: char.avatarPath,
                                        backgroundColor: char.avatarColor,
                                        size: 40,
                                        radius: 5,
                                      ),
                                      showArrow: true,
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => CharacterProfileScreen(character: char),
                                          ),
                                        );
                                      },
                                    ),
                                ],
                              ),
                            if (_results.conversations.isNotEmpty)
                              WeuiCellGroup(
                                title: '会话列表',
                                children: [
                                  for (final conv in _results.conversations)
                                    WeuiCell(
                                      title: conv.title,
                                      subtitle: conv.lastMessagePreview,
                                      leading: WechatAvatar(
                                        name: conv.title,
                                        imagePath: conv.avatarPath,
                                        backgroundColor: conv.avatarColor,
                                        sourceType: conv.sourceType,
                                        size: 40,
                                        radius: 5,
                                      ),
                                      showArrow: true,
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => ChatDetailScreen(conversation: conv),
                                          ),
                                        );
                                      },
                                    ),
                                ],
                              ),
                            if (_results.messageHits.isNotEmpty)
                              WeuiCellGroup(
                                title: '聊天记录',
                                children: [
                                  for (final hit in _results.messageHits)
                                    WeuiCell(
                                      title: hit.conversation.title,
                                      subtitle: hit.message.content,
                                      trailingText: formatWechatListTime(hit.message.createdAt),
                                      leading: WechatAvatar(
                                        name: hit.conversation.title,
                                        imagePath: hit.conversation.avatarPath,
                                        backgroundColor: hit.conversation.avatarColor,
                                        sourceType: hit.conversation.sourceType,
                                        size: 40,
                                        radius: 5,
                                      ),
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                ChatDetailScreen(conversation: hit.conversation),
                                          ),
                                        );
                                      },
                                    ),
                                ],
                              ),
                            const SizedBox(height: 24),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
