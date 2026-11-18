import 'package:flutter/material.dart';

import '../theme/wechat_theme.dart';

/// Grouped container mirroring `.weui-cells` and `.weui-cells__group_form`.
class WeuiCellGroup extends StatelessWidget {
  const WeuiCellGroup({
    super.key,
    required this.children,
    this.title,
    this.tips,
    this.marginTop = 8,
    this.insetForm = false,
  });

  final List<Widget> children;
  final String? title;
  final String? tips;
  final double marginTop;
  final bool insetForm;

  @override
  Widget build(BuildContext context) {
    final visibleChildren = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      visibleChildren.add(children[i]);
      if (i < children.length - 1) {
        visibleChildren.add(
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Container(height: 0.5, color: WeuiColors.fg3),
          ),
        );
      }
    }

    final cellsContainer = Container(
      margin: insetForm ? const EdgeInsets.symmetric(horizontal: 16) : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: WeuiColors.bg2,
        borderRadius: insetForm ? BorderRadius.circular(8) : BorderRadius.zero,
        border: insetForm
            ? Border.all(color: WeuiColors.fg3, width: 0.5)
            : const Border(
                top: BorderSide(color: WeuiColors.fg3, width: 0.5),
                bottom: BorderSide(color: WeuiColors.fg3, width: 0.5),
              ),
      ),
      clipBehavior: insetForm ? Clip.antiAlias : Clip.none,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: visibleChildren,
      ),
    );

    return Padding(
      padding: EdgeInsets.only(top: marginTop),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null && title!.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(insetForm ? 24 : 16, 8, 16, 8),
              child: Text(
                title!,
                style: const TextStyle(
                  color: WeuiColors.fg1,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          cellsContainer,
          if (tips != null && tips!.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(insetForm ? 24 : 16, 8, 16, 4),
              child: Text(
                tips!,
                style: const TextStyle(
                  color: WeuiColors.fg2,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Standard `.weui-cell` row (`56dp` minimum height, `16dp` padding, `17sp` label, optional chevron).
class WeuiCell extends StatelessWidget {
  const WeuiCell({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailingText,
    this.trailing,
    this.showArrow = false,
    this.onTap,
    this.titleColor,
    this.centerTitle = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final String? trailingText;
  final Widget? trailing;
  final bool showArrow;
  final VoidCallback? onTap;
  final Color? titleColor;
  final bool centerTitle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WeuiColors.bg2,
      child: InkWell(
        onTap: onTap,
        highlightColor: WeuiColors.activeBg,
        splashColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                ?leading,
                if (leading != null) const SizedBox(width: 14),
                Expanded(
                  child: centerTitle
                      ? Center(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: titleColor ?? WeuiColors.fg0,
                              fontSize: 17,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: titleColor ?? WeuiColors.fg0,
                                fontSize: 17,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            if (subtitle != null && subtitle!.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                subtitle!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: WeuiColors.fg1,
                                  fontSize: 13.5,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
                if (trailingText != null && trailingText!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(
                      trailingText!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: WeuiColors.fg1,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ],
                if (showArrow) ...[
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: Color(0x55000000),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Official `.weui-switch` pill (`52x32dp`, `#07C160` active track, white thumb).
class WeuiSwitch extends StatelessWidget {
  const WeuiSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: onChanged == null ? 0.35 : 1.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: 52,
          height: 32,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: value ? WeuiColors.brand : WeuiColors.fg3,
            borderRadius: BorderRadius.circular(16),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 3,
                    offset: const Offset(0, 1.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum WeuiButtonType { primary, secondary, warn }

/// Official `.weui-btn` (`48dp` height, `8dp` border radius, `17sp` label).
class WeuiButton extends StatelessWidget {
  const WeuiButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.type = WeuiButtonType.primary,
    this.isLoading = false,
    this.fullWidth = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final WeuiButtonType type;
  final bool isLoading;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || isLoading;
    Color bg;
    Color fg;
    switch (type) {
      case WeuiButtonType.primary:
        bg = disabled ? WeuiColors.fg5 : WeuiColors.brand;
        fg = disabled ? WeuiColors.fg4 : Colors.white;
      case WeuiButtonType.secondary:
        bg = WeuiColors.fg5;
        fg = disabled ? WeuiColors.fg4 : WeuiColors.fg0;
      case WeuiButtonType.warn:
        bg = disabled ? WeuiColors.fg5 : WeuiColors.red;
        fg = disabled ? WeuiColors.fg4 : Colors.white;
    }

    return SizedBox(
      width: fullWidth ? double.infinity : null,
      height: 48,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: disabled ? null : onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLoading) ...[
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(fg),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        color: fg,
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Official `.weui-cell` form input row (`88dp` label column + borderless input).
class WeuiFormRow extends StatelessWidget {
  const WeuiFormRow({
    super.key,
    required this.label,
    required this.controller,
    this.hintText = '',
    this.obscureText = false,
    this.maxLines = 1,
    this.minLines,
    this.vertical = false,
    this.keyboardType,
    this.trailing,
  });

  final String label;
  final TextEditingController controller;
  final String hintText;
  final bool obscureText;
  final int? maxLines;
  final int? minLines;
  final bool vertical;
  final TextInputType? keyboardType;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: controller,
      obscureText: obscureText,
      maxLines: obscureText ? 1 : maxLines,
      minLines: minLines,
      keyboardType: keyboardType,
      style: const TextStyle(color: WeuiColors.fg0, fontSize: 16, height: 1.4),
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        hintText: hintText,
        hintStyle: const TextStyle(color: WeuiColors.fg2, fontSize: 15),
        contentPadding: EdgeInsets.zero,
      ),
    );

    if (vertical) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(color: WeuiColors.fg0, fontSize: 16),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 10),
            field,
          ],
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 54),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 92,
              child: Text(
                label,
                style: const TextStyle(color: WeuiColors.fg0, fontSize: 16),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: field),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Official `.weui-search-bar` (`36dp` white rounded search field on `#EDEDED` bar).
class WeuiSearchBar extends StatelessWidget {
  const WeuiSearchBar({
    super.key,
    required this.controller,
    this.hintText = '搜索',
    this.autofocus = false,
    this.onChanged,
    this.onCancel,
  });

  final TextEditingController controller;
  final String hintText;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: WeuiColors.bg0,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: WeuiColors.bg2,
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 18, color: WeuiColors.fg2),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      autofocus: autofocus,
                      onChanged: onChanged,
                      style: const TextStyle(fontSize: 16, color: WeuiColors.fg0),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: hintText,
                        hintStyle: const TextStyle(color: WeuiColors.fg2, fontSize: 16),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (_, value, _) {
                      if (value.text.isEmpty) return const SizedBox.shrink();
                      return GestureDetector(
                        onTap: () {
                          controller.clear();
                          onChanged?.call('');
                        },
                        child: const Icon(Icons.cancel, size: 18, color: WeuiColors.fg2),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          if (onCancel != null) ...[
            const SizedBox(width: 12),
            GestureDetector(
              onTap: onCancel,
              child: const Text(
                '取消',
                style: TextStyle(color: WeuiColors.link, fontSize: 17),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Official `.weui-dialog` confirmation dialog.
class WeuiDialog {
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    String? content,
    String confirmText = '确定',
    String cancelText = '取消',
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x80000000),
      builder: (ctx) {
        return Dialog(
          backgroundColor: WeuiColors.bg2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 14),
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: WeuiColors.fg0,
                    ),
                  ),
                ),
                if (content != null && content.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Text(
                      content,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15.5,
                        color: WeuiColors.fg1,
                        height: 1.45,
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 14),
                Container(height: 0.5, color: WeuiColors.fg3),
                SizedBox(
                  height: 54,
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => Navigator.of(ctx).pop(false),
                          child: Center(
                            child: Text(
                              cancelText,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w500,
                                color: WeuiColors.fg0,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Container(width: 0.5, color: WeuiColors.fg3),
                      Expanded(
                        child: InkWell(
                          onTap: () => Navigator.of(ctx).pop(true),
                          child: Center(
                            child: Text(
                              confirmText,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: destructive ? WeuiColors.red : WeuiColors.link,
                              ),
                            ),
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
      },
    );
    return result ?? false;
  }
}

/// Option descriptor for [WeuiActionSheet].
class WeuiSheetAction {
  const WeuiSheetAction({
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool destructive;
}

/// Official `.weui-actionsheet` bottom menu sheet (`#F7F7F7`, `12dp` top corners, `56dp` rows).
class WeuiActionSheet {
  static Future<void> show(
    BuildContext context, {
    String? title,
    required List<WeuiSheetAction> actions,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: WeuiColors.bg1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null && title.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  color: WeuiColors.bg2,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: WeuiColors.fg1),
                  ),
                ),
                Container(height: 0.5, color: WeuiColors.fg3),
              ],
              Container(
                color: WeuiColors.bg2,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) Container(height: 0.5, color: WeuiColors.fg3),
                      InkWell(
                        onTap: () {
                          Navigator.of(ctx).pop();
                          actions[i].onTap();
                        },
                        child: Container(
                          width: double.infinity,
                          height: 56,
                          alignment: Alignment.center,
                          child: Text(
                            actions[i].label,
                            style: TextStyle(
                              fontSize: 17,
                              color: actions[i].destructive ? WeuiColors.red : WeuiColors.fg0,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Container(
                color: WeuiColors.bg2,
                child: InkWell(
                  onTap: () => Navigator.of(ctx).pop(),
                  child: Container(
                    width: double.infinity,
                    height: 56,
                    alignment: Alignment.center,
                    child: const Text(
                      '取消',
                      style: TextStyle(fontSize: 17, color: WeuiColors.fg0),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Shows a crisp WeUI charcoal feedback toast (`#4C4C4C`).
void showWeuiToast(BuildContext context, String message, {bool isError = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isError ? const Color(0xFFE04848) : WeuiColors.bg4,
      duration: const Duration(seconds: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      content: Text(
        message,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
    ),
  );
}
