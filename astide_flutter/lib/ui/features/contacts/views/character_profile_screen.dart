import 'package:flutter/material.dart';

import '../../../../app_scope.dart';
import '../../../../domain/models/character_profile.dart';
import '../../../core/theme/wechat_theme.dart';
import '../../../core/widgets/wechat_avatar.dart';
import '../../../core/widgets/weui_widgets.dart';
import '../../chat_detail/views/chat_detail_screen.dart';
import 'character_form_screen.dart';

/// WeChat-style contact details card for a generated roleplay character.
class CharacterProfileScreen extends StatefulWidget {
  const CharacterProfileScreen({super.key, required this.character});

  final CharacterProfile character;

  @override
  State<CharacterProfileScreen> createState() => _CharacterProfileScreenState();
}

class _CharacterProfileScreenState extends State<CharacterProfileScreen> {
  late CharacterProfile _character;

  @override
  void initState() {
    super.initState();
    _character = widget.character;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final meta = [
      if (_character.gender.isNotEmpty) _character.gender,
      if (_character.age.isNotEmpty) _character.age,
      if (_character.occupation.isNotEmpty) _character.occupation,
    ].join(' · ');

    return Scaffold(
      backgroundColor: WeuiColors.bg0,
      appBar: AppBar(
        title: const Text('人物资料'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 22),
            onPressed: () async {
              final updated = await Navigator.of(context).push<CharacterProfile>(
                MaterialPageRoute(
                  builder: (_) => CharacterFormScreen(initialCharacter: _character),
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
                WechatAvatar(
                  name: _character.displayName,
                  imagePath: _character.avatarPath,
                  backgroundColor: _character.avatarColor,
                  size: 64,
                  radius: 8,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _character.displayName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: WeuiColors.fg0,
                        ),
                      ),
                      if (_character.remark.isNotEmpty && _character.remark != _character.name)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '原名：${_character.name}',
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
          WeuiCellGroup(
            children: [
              if (_character.relationship.isNotEmpty)
                WeuiCell(title: '与我的关系', trailingText: _character.relationship),
              if (_character.personality.isNotEmpty)
                WeuiCell(title: '性格特点', subtitle: _character.personality),
              if (_character.backstory.isNotEmpty)
                WeuiCell(title: '背景故事', subtitle: _character.backstory),
              if (_character.speechStyle.isNotEmpty)
                WeuiCell(title: '说话风格', subtitle: _character.speechStyle),
            ],
          ),
          WeuiCellGroup(
            children: [
              WeuiCell(
                title: '发消息',
                centerTitle: true,
                titleColor: WeuiColors.link,
                onTap: () async {
                  final conv = await app.openOrCreateCharacterConversation(_character);
                  if (context.mounted) {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => ChatDetailScreen(conversation: conv)),
                    );
                  }
                },
              ),
            ],
          ),
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
                    content: '确定要删除「${_character.displayName}」的人物设定吗？已有聊天记录将保留在会话列表中。',
                    confirmText: '删除',
                    destructive: true,
                  );
                  if (!ok || !context.mounted) return;
                  await app.deleteCharacter(_character.id);
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
