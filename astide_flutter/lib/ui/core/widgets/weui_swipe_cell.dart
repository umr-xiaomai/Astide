import 'package:flutter/material.dart';

import '../theme/wechat_theme.dart';

/// Action descriptor for [WeuiSwipeCell], styled after `.weui-swiped-btn`.
class WeuiSwipeAction {
  const WeuiSwipeAction({
    required this.label,
    required this.backgroundColor,
    required this.onTap,
    this.textColor = Colors.white,
    this.width = 76,
  });

  final String label;
  final Color backgroundColor;
  final Color textColor;
  final double width;
  final VoidCallback onTap;
}

/// WeChat-style left-swipeable list cell (`.weui-cell_swiped`) revealing trailing actions.
class WeuiSwipeCell extends StatefulWidget {
  const WeuiSwipeCell({
    super.key,
    required this.child,
    required this.actions,
    this.isOpen = false,
    this.onOpenChanged,
    this.onSwipeStart,
  });

  final Widget child;
  final List<WeuiSwipeAction> actions;
  final bool isOpen;
  final ValueChanged<bool>? onOpenChanged;
  final VoidCallback? onSwipeStart;

  @override
  State<WeuiSwipeCell> createState() => _WeuiSwipeCellState();
}

class _WeuiSwipeCellState extends State<WeuiSwipeCell> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _dragOffset = 0;

  double get _totalActionWidth =>
      widget.actions.fold<double>(0, (sum, a) => sum + a.width);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: widget.isOpen ? 1.0 : 0.0,
    );
    _dragOffset = widget.isOpen ? -_totalActionWidth : 0.0;
    _controller.addListener(() {
      setState(() {
        _dragOffset = -_totalActionWidth * _controller.value;
      });
    });
  }

  @override
  void didUpdateWidget(covariant WeuiSwipeCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOpen != oldWidget.isOpen && !_controller.isAnimating) {
      if (widget.isOpen) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _settle(bool open) {
    if (open) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
    widget.onOpenChanged?.call(open);
  }

  @override
  Widget build(BuildContext context) {
    final maxExtent = _totalActionWidth;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) {
        _controller.stop();
        widget.onSwipeStart?.call();
      },
      onHorizontalDragUpdate: (details) {
        final next = (_dragOffset + details.delta.dx).clamp(-maxExtent, 0.0);
        if (next != _dragOffset) {
          setState(() {
            _dragOffset = next;
            _controller.value = maxExtent > 0 ? (-_dragOffset / maxExtent) : 0.0;
          });
        }
      },
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        final shouldOpen = velocity < -300 ||
            (velocity <= 300 && -_dragOffset > maxExtent * 0.42);
        _settle(shouldOpen);
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              color: WeuiColors.bg2,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final action in widget.actions)
                    GestureDetector(
                      onTap: () {
                        _settle(false);
                        action.onTap();
                      },
                      child: Container(
                        width: action.width,
                        color: action.backgroundColor,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          action.label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: action.textColor,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _dragOffset < -4 ? () => _settle(false) : null,
              child: AbsorbPointer(
                absorbing: _dragOffset < -4,
                child: widget.child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
