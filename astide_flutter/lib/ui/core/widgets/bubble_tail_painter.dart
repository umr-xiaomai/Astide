import 'package:flutter/material.dart';

/// Renders an authentic WeChat speech bubble with a top-aligned triangular tail.
class WechatSpeechBubble extends StatelessWidget {
  const WechatSpeechBubble({
    super.key,
    required this.isUser,
    required this.color,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
  });

  final bool isUser;
  final Color color;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final bubble = Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(5),
      ),
      padding: padding,
      child: child,
    );

    final tail = CustomPaint(
      size: const Size(6, 12),
      painter: _BubbleTailPainter(color: color, pointRight: isUser),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: isUser
          ? [
              Flexible(child: bubble),
              Padding(
                padding: const EdgeInsets.only(top: 13),
                child: tail,
              ),
            ]
          : [
              Padding(
                padding: const EdgeInsets.only(top: 13),
                child: tail,
              ),
              Flexible(child: bubble),
            ],
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  const _BubbleTailPainter({required this.color, required this.pointRight});

  final Color color;
  final bool pointRight;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    if (pointRight) {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, size.height / 2)
        ..lineTo(0, size.height)
        ..close();
    } else {
      path
        ..moveTo(size.width, 0)
        ..lineTo(0, size.height / 2)
        ..lineTo(size.width, size.height)
        ..close();
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.pointRight != pointRight;
  }
}
