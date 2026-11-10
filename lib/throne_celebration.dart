import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A short, non-modal coronation banner with a bounded twelve-particle painter.
class ThroneCelebration extends StatelessWidget {
  final String name;
  final String? avatar;
  const ThroneCelebration({super.key, required this.name, this.avatar});
  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final content = Row(
      children: [
        CircleAvatar(
          backgroundImage: avatar != null && avatar!.isNotEmpty
              ? NetworkImage(avatar!)
              : null,
          child: avatar == null || avatar!.isEmpty
              ? const Icon(Icons.person)
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '👑 الملك الجديد\n$name',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFFFD36B),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: reduceMotion ? Duration.zero : const Duration(seconds: 2),
      child: Padding(padding: const EdgeInsets.all(8), child: content),
      builder: (context, progress, child) => RepaintBoundary(
        child: CustomPaint(
          painter: _RoyalSparks(reduceMotion ? 0.5 : progress),
          child: child,
        ),
      ),
    );
  }
}

class _RoyalSparks extends CustomPainter {
  final double progress;
  _RoyalSparks(this.progress);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFD36B).withValues(alpha: 1 - 0.7 * progress);
    for (var i = 0; i < 12; i++) {
      final angle = i * math.pi / 6;
      final origin = Offset(size.width / 2, size.height / 2);
      final offset = Offset(
        math.cos(angle) * size.width * 0.46 * progress,
        math.sin(angle) * size.height * 0.46 * progress,
      );
      canvas.drawCircle(origin + offset, 1.5 + (i % 2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RoyalSparks oldDelegate) =>
      oldDelegate.progress != progress;
}
