import 'dart:math' as math;
import 'package:flutter/material.dart';

/// أيقونة "عرض مرة واحدة": دائرة منقّطة بداخلها 1
/// filled = true  => الحالة المفعّلة (دائرة ممتلئة و 1 بداخلها)
class ViewOnceIcon extends StatelessWidget {
  final double size;
  final Color color;
  final bool filled;

  const ViewOnceIcon({
    super.key,
    this.size = 24,
    this.color = Colors.white,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ViewOnceIconPainter(color: color, filled: filled)),
    );
  }
}

class _ViewOnceIconPainter extends CustomPainter {
  final Color color;
  final bool filled;
  const _ViewOnceIconPainter({required this.color, required this.filled});

  @override
  void paint(Canvas canvas, Size size) {
    final double stroke = math.max(1.5, size.width / 12);
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);

    if (filled) {
      canvas.drawOval(rect, Paint()..color = color..style = PaintingStyle.fill);
    } else {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      const int dashes = 9;
      const double sweep = 2 * math.pi / dashes;
      for (int i = 0; i < dashes; i++) {
        canvas.drawArc(rect, i * sweep, sweep * 0.55, false, paint);
      }
    }

    final tp = TextPainter(
      text: TextSpan(
        text: '1',
        style: TextStyle(
          color: filled ? const Color(0xFF111B21) : color,
          fontSize: size.width * 0.54,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2));
  }

  @override
  bool shouldRepaint(covariant _ViewOnceIconPainter old) => old.color != color || old.filled != filled;
}