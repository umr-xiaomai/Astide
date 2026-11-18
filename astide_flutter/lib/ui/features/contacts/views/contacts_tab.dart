import 'package:flutter/material.dart';

import '../../../../app_scope.dart';
import '../../../core/theme/wechat_theme.dart';
import '../../../core/widgets/wechat_avatar.dart';
import '../../../core/widgets/weui_widgets.dart';
import '../../chat_detail/views/chat_detail_screen.dart';
import 'character_form_screen.dart';
import 'character_profile_screen.dart';

/// Tab 2 ("通讯录"): manages core pinned 星汐 Astide and all user-created AI characters.
class ContactsTab extends StatelessWidget {
  const ContactsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final characters = app.characters;

    return Scaffold(
      backgroundColor: WeuiColors.bg0,
      appBar: AppBar(
        title: const Text('通讯录'),
        actions: [
          IconButton(
            tooltip: '创建人物',
            icon: const Icon(Icons.person_add_outlined, size: 23),
            onPressed: () => _openCharacterForm(context, app),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: WeuiColors.fg3),
        ),
      ),
      body: ListView(
        children: [
          WeuiCellGroup(
            marginTop: 0,
            children: [
              WeuiCell(
                title: '一句话 AI 自动创建人物',
                subtitle: '输入一句话或粘贴整段提示词，AI 自动填表生成角色',
                leading: const _WechatBadgeIcon(
                  icon: Icons.auto_awesome,
                  color: WeuiColors.brand,
                ),
                showArrow: true,
                onTap: () => _openCharacterForm(context, app, focusAiPrompt: true),
              ),
              WeuiCell(
                title: '手动填表新建人物',
                subtitle: '精细定制头像、性格、背景、口癖与开场白',
                leading: const _WechatBadgeIcon(
                  icon: Icons.person_add_alt_1,
                  color: WeuiColors.orange,
                ),
                showArrow: true,
                onTap: () => _openCharacterForm(context, app),
              ),
            ],
          ),
          WeuiCellGroup(
            title: '默认置顶角色',
            children: [
              WeuiCell(
                title: '星汐 Astide',
                subtitle: '始终置顶的通用日常伴聊角色',
                leading: const WechatAvatar(
                  name: '星汐 Astide',
                  imagePath: WechatAvatar.coreAstideAvatarAsset,
                  backgroundColor: 0xFF07C160,
                  size: 42,
                  radius: 6,
                ),
                showArrow: true,
                onTap: () async {
                  final conv = await app.getCoreAstideConversation();
                  if (context.mounted) {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ChatDetailScreen(conversation: conv)),
                    );
                  }
                },
              ),
            ],
          ),
          if (characters.isNotEmpty)
            WeuiCellGroup(
              title: '我创建的人物 (${characters.length})',
              children: [
                for (final char in characters)
                  WeuiCell(
                    title: char.displayName,
                    subtitle: _buildCharSubtitle(char),
                    leading: WechatAvatar(
                      name: char.displayName,
                      imagePath: char.avatarPath,
                      backgroundColor: char.avatarColor,
                      size: 42,
                      radius: 6,
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
            )
          else
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 36, 24, 24),
              child: Column(
                children: [
                  Icon(Icons.people_outline, size: 44, color: WeuiColors.fg2),
                  SizedBox(height: 10),
                  Text(
                    '还没有额外创建的人物\n试试“一句话 AI 自动创建人物”快速捏一个吧',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: WeuiColors.fg1, height: 1.5),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _openCharacterForm(
    BuildContext context,
    AppController app, {
    bool focusAiPrompt = false,
  }) async {
    final created = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CharacterFormScreen(focusAiPrompt: focusAiPrompt),
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
  }

  String _buildCharSubtitle(dynamic char) {
    final parts = <String>[
      if (char.relationship.isNotEmpty) char.relationship,
      if (char.occupation.isNotEmpty) char.occupation,
      if (char.personality.isNotEmpty) char.personality,
    ];
    return parts.join(' · ');
  }
}

class _WechatBadgeIcon extends StatelessWidget {
  const _WechatBadgeIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, color: Colors.white, size: 22),
    );
  }
}
