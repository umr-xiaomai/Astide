import 'package:flutter/material.dart';

import '../../../../app_scope.dart';
import '../../../core/theme/wechat_theme.dart';
import '../../../core/widgets/wechat_avatar.dart';
import '../../../core/widgets/weui_widgets.dart';
import 'moments_screen.dart';

/// Tab 3 ("发现"): pure WeChat Discover page leading into Moments ("朋友圈").
class DiscoverTab extends StatelessWidget {
  const DiscoverTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final unseenMoment = app.latestUnseenAiMoment;

    return Scaffold(
      backgroundColor: WeuiColors.bg0,
      appBar: AppBar(
        title: const Text('发现'),
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
                title: '朋友圈',
                leading: const _MomentsIrisIcon(),
                trailing: unseenMoment != null
                    ? Stack(
                        clipBehavior: Clip.none,
                        children: [
                          WechatAvatar(
                            name: unseenMoment.authorName,
                            imagePath: unseenMoment.authorAvatarPath,
                            backgroundColor: unseenMoment.authorAvatarColor,
                            size: 32,
                            radius: 4,
                          ),
                          Positioned(
                            top: -3,
                            right: -3,
                            child: Container(
                              width: 9,
                              height: 9,
                              decoration: const BoxDecoration(
                                color: WeuiColors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ],
                      )
                    : null,
                showArrow: true,
                onTap: () {
                  app.markMomentsSeen();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MomentsScreen()),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MomentsIrisIcon extends StatelessWidget {
  const _MomentsIrisIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(
          colors: [
            Color(0xFF07C160),
            Color(0xFF10AEFF),
            Color(0xFF6467F0),
            Color(0xFFFA5151),
            Color(0xFFFA9D3B),
            Color(0xFF07C160),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Container(
        width: 11,
        height: 11,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
