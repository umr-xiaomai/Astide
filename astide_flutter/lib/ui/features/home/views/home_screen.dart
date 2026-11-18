import 'package:flutter/material.dart';

import '../../../../app_scope.dart';
import '../../../core/theme/wechat_theme.dart';
import '../../chats/views/chat_list_tab.dart';
import '../../contacts/views/contacts_tab.dart';
import '../../discover/views/discover_tab.dart';
import '../../me/views/me_tab.dart';

/// Main 4-tab WeChat-style shell (`星汐` / `通讯录` / `发现` / `我`).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final idx = app.currentTabIndex;
    final unread = app.totalUnreadCount;

    const pages = <Widget>[
      ChatListTab(),
      ContactsTab(),
      DiscoverTab(),
      MeTab(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: idx,
        children: pages,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: WeuiColors.bg1,
          border: Border(top: BorderSide(color: WeuiColors.fg3, width: 0.5)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 54,
            child: Row(
              children: [
                _WechatTabItem(
                  label: '星汐',
                  icon: Icons.chat_bubble_outline,
                  activeIcon: Icons.chat_bubble,
                  selected: idx == 0,
                  badgeCount: unread,
                  onTap: () => app.setTabIndex(0),
                ),
                _WechatTabItem(
                  label: '通讯录',
                  icon: Icons.perm_contact_calendar_outlined,
                  activeIcon: Icons.perm_contact_calendar,
                  selected: idx == 1,
                  onTap: () => app.setTabIndex(1),
                ),
                _WechatTabItem(
                  label: '发现',
                  icon: Icons.explore_outlined,
                  activeIcon: Icons.explore,
                  selected: idx == 2,
                  badgeCount: app.latestUnseenAiMoment != null ? 1 : 0,
                  onTap: () => app.setTabIndex(2),
                ),
                _WechatTabItem(
                  label: '我',
                  icon: Icons.person_outline,
                  activeIcon: Icons.person,
                  selected: idx == 3,
                  onTap: () => app.setTabIndex(3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WechatTabItem extends StatelessWidget {
  const _WechatTabItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool selected;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final color = selected ? WeuiColors.brand : WeuiColors.textPrimary;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(selected ? activeIcon : icon, size: 24, color: color),
                if (badgeCount > 0)
                  Positioned(
                    top: -2,
                    right: -6,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: WeuiColors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                color: selected ? WeuiColors.brand : WeuiColors.fg0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
