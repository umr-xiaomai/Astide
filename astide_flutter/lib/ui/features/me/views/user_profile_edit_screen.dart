import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../app_scope.dart';
import '../../../core/theme/wechat_theme.dart';
import '../../../core/widgets/wechat_avatar.dart';
import '../../../core/widgets/weui_widgets.dart';

/// Edits the user's local nickname, avatar, and personal roleplay persona.
class UserProfileEditScreen extends StatefulWidget {
  const UserProfileEditScreen({super.key});

  @override
  State<UserProfileEditScreen> createState() => _UserProfileEditScreenState();
}

class _UserProfileEditScreenState extends State<UserProfileEditScreen> {
  final _nicknameCtrl = TextEditingController();
  final _personaCtrl = TextEditingController();
  String? _avatarPath;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      final s = AppScope.of(context).settings;
      _nicknameCtrl.text = s.userNickname;
      _personaCtrl.text = s.userPersona;
      _avatarPath = s.userAvatarPath;
    }
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    _personaCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar(AppController app) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;
    final saved = await app.mediaStorage.saveFileCopy(picked.path, category: 'avatars');
    if (mounted) setState(() => _avatarPath = saved);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);

    return Scaffold(
      backgroundColor: WeuiColors.bg0,
      appBar: AppBar(
        title: const Text('个人信息'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: WeuiColors.fg3),
        ),
      ),
      body: ListView(
        children: [
          WeuiCellGroup(
            insetForm: true,
            tips: '填写“我的人设”后，开启角色扮演时对方会结合你的身份与称呼和你互动',
            children: [
              WeuiCell(
                title: '头像',
                trailing: WechatAvatar(
                  name: _nicknameCtrl.text,
                  imagePath: _avatarPath,
                  backgroundColor: 0xFF576B95,
                  isUserSelf: true,
                  size: 52,
                  radius: 6,
                ),
                showArrow: true,
                onTap: () => _pickAvatar(app),
              ),
              WeuiFormRow(
                label: '昵称',
                controller: _nicknameCtrl,
                hintText: '如：小埋 / 我',
              ),
              WeuiFormRow(
                label: '我的人设',
                controller: _personaCtrl,
                hintText: '选填，如：正在准备期末的大二工科生...',
                vertical: true,
                minLines: 3,
                maxLines: 5,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: WeuiButton(
              label: '保存',
              onPressed: () async {
                final nick = _nicknameCtrl.text.trim();
                await app.updateSettings(
                  app.settings.copyWith(
                    userNickname: nick.isNotEmpty ? nick : '我',
                    userAvatarPath: () => _avatarPath,
                    userPersona: _personaCtrl.text.trim(),
                  ),
                );
                if (context.mounted) {
                  showWeuiToast(context, '个人信息已保存');
                  Navigator.of(context).pop();
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
