import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Official Tencent WeUI light palette tokens mapped from `weui/src/style/base/theme/vars/light.less`.
abstract final class WeuiColors {
  static const Color bg0 = Color(0xFFEDEDED); // --weui-BG-0: default page & navbar bg
  static const Color bg1 = Color(0xFFF7F7F7); // --weui-BG-1: tabbar, input bar, sheet bg
  static const Color bg2 = Color(0xFFFFFFFF); // --weui-BG-2: cells, white bubbles, dialogs
  static const Color bg4 = Color(0xFF4C4C4C); // --weui-BG-4: dark popover menu & toast

  static const Color brand = Color(0xFF07C160); // --weui-BRAND
  static const Color brandPressed = Color(0xFF06AE56); // --weui-BRAND-90 / TEXTGREEN
  static const Color lightGreen = Color(0xFF95EC69); // --weui-LIGHTGREEN (user chat bubble)
  static const Color link = Color(0xFF576B95); // --weui-LINK
  static const Color red = Color(0xFFFA5151); // --weui-RED
  static const Color orange = Color(0xFFFA9D3B); // --weui-ORANGE
  static const Color blue = Color(0xFF10AEFF); // --weui-BLUE
  static const Color indigo = Color(0xFF1485EE); // --weui-INDIGO
  static const Color purple = Color(0xFF6467F0); // --weui-PURPLE

  static const Color fg0 = Color(0xE6000000); // --weui-FG-0 (primary text)
  static const Color fg1 = Color(0x8C000000); // --weui-FG-1 (desc / subtitle)
  static const Color fg2 = Color(0x4D000000); // --weui-FG-2 (tips / timestamps)
  static const Color fg3 = Color(0x1A000000); // --weui-FG-3 (0.5dp hairline separator)
  static const Color fg4 = Color(0x26000000); // --weui-FG-4 (disabled text)
  static const Color fg5 = Color(0x0D000000); // --weui-FG-5 (default button fill)

  static const Color activeBg = Color(0xFFECECEC); // --weui-BG-COLOR-ACTIVE
  static const Color pinnedCellBg = Color(0xFFF7F7F7); // pinned chat item subtle surface
  static const Color textPrimary = Color(0xFF191919);
  static const Color textSecondary = Color(0xFF888888);
  static const Color textTimestamp = Color(0xFFB2B2B2);
}

/// Builds the global WeChat / WeUI Flutter [ThemeData].
ThemeData buildWeuiTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primaryColor: WeuiColors.brand,
    scaffoldBackgroundColor: WeuiColors.bg0,
    dividerColor: WeuiColors.fg3,
    splashFactory: NoSplash.splashFactory,
    highlightColor: WeuiColors.activeBg,
    colorScheme: const ColorScheme.light(
      primary: WeuiColors.brand,
      secondary: WeuiColors.brand,
      surface: WeuiColors.bg2,
      error: WeuiColors.red,
      onPrimary: Colors.white,
      onSurface: WeuiColors.textPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: WeuiColors.bg0,
      foregroundColor: WeuiColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: WeuiColors.textPrimary,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: IconThemeData(
        color: WeuiColors.textPrimary,
        size: 22,
      ),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: WeuiColors.brand,
      selectionColor: Color(0x4407C160),
      selectionHandleColor: WeuiColors.brand,
    ),
  );
}

/// Formats timestamps in exact WeChat style (e.g. `00:36`, `昨天`, `周二`, `5月8日`).
String formatWechatListTime(DateTime time) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(time.year, time.month, time.day);
  final diffDays = today.difference(target).inDays;

  if (diffDays == 0) {
    return DateFormat('HH:mm').format(time);
  }
  if (diffDays == 1) {
    return '昨天';
  }
  if (diffDays > 1 && diffDays < 7) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return weekdays[time.weekday - 1];
  }
  if (time.year == now.year) {
    return '${time.month}月${time.day}日';
  }
  return '${time.year}年${time.month}月${time.day}日';
}

/// Formats centered message divider timestamps in WeChat chat rooms.
String formatWechatChatTime(DateTime time) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(time.year, time.month, time.day);
  final diffDays = today.difference(target).inDays;
  final hm = DateFormat('HH:mm').format(time);

  if (diffDays == 0) {
    return hm;
  }
  if (diffDays == 1) {
    return '昨天 $hm';
  }
  if (diffDays > 1 && diffDays < 7) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return '${weekdays[time.weekday - 1]} $hm';
  }
  if (time.year == now.year) {
    return '${time.month}月${time.day}日 $hm';
  }
  return '${time.year}年${time.month}月${time.day}日 $hm';
}
