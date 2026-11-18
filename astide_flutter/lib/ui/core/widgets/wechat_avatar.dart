import 'dart:io';

import 'package:flutter/material.dart';

import '../../../domain/models/conversation.dart';
import '../theme/wechat_theme.dart';

/// WeChat-style rounded-square avatar supporting local image files, stylized initials, and unread badges.
class WechatAvatar extends StatelessWidget {
  const WechatAvatar({
    super.key,
    required this.name,
    this.imagePath,
    this.backgroundColor = 0xFF07C160,
    this.size = 48,
    this.radius = 6,
    this.unreadCount = 0,
    this.sourceType,
    this.isUserSelf = false,
  });

  static const String coreAstideAvatarAsset = 'asset:assets/images/astide_avatar.jpg';

  final String name;
  final String? imagePath;
  final int backgroundColor;
  final double size;
  final double radius;
  final int unreadCount;
  final ConversationSourceType? sourceType;
  final bool isUserSelf;

  @override
  Widget build(BuildContext context) {
    final avatar = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: _buildInner(),
      ),
    );

    if (unreadCount <= 0) return avatar;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          top: -4,
          right: -4,
          child: unreadCount == 1
              ? Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: WeuiColors.red,
                    shape: BoxShape.circle,
                  ),
                )
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  decoration: BoxDecoration(
                    color: WeuiColors.red,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    unreadCount > 99 ? '99+' : '$unreadCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildInner() {
    if (imagePath != null && imagePath!.isNotEmpty) {
      if (imagePath!.startsWith('asset:')) {
        final assetPath = imagePath!.substring('asset:'.length);
        return Image.asset(
          assetPath,
          fit: BoxFit.cover,
          cacheWidth: (size * 3).round(),
          errorBuilder: (_, _, _) => _buildFallback(),
        );
      }
      final file = File(imagePath!);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          cacheWidth: (size * 3).round(),
          errorBuilder: (_, _, _) => _buildFallback(),
        );
      }
    }
    return _buildFallback();
  }

  Widget _buildFallback() {
    if (sourceType == ConversationSourceType.deepseekImport) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4D6BFE), Color(0xFF2845D6)],
          ),
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.auto_awesome,
          color: Colors.white,
          size: size * 0.52,
        ),
      );
    }

    final clean = name.trim();
    final label = clean.isNotEmpty ? clean.characters.first.toUpperCase() : (isUserSelf ? '我' : '星');

    return Container(
      color: Color(backgroundColor),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.44,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
