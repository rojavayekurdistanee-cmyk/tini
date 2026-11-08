import 'package:flutter/material.dart';

class CroupTransitionWidget extends StatelessWidget {
  final VoidCallback? onTap;
  const CroupTransitionWidget({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(7), // نفس تدويرة تيك توك
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha:0.25),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // المثلث اليسار
              CustomPaint(
                size: const Size(6, 8),
                painter: _TrianglePainter(isLeft: true),
              ),
              const SizedBox(width: 2),
              // المثلث اليمين
              CustomPaint(
                size: const Size(6, 8),
                painter: _TrianglePainter(isLeft: false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  final bool isLeft;
  _TrianglePainter({required this.isLeft});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFB0B0B0) // نفس الرمادي تبع تيك توك
      ..style = PaintingStyle.fill;

    final path = Path();
    if (isLeft) {
      // مثلث يشير لليسار
      path.moveTo(0, size.height / 2);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height);
    } else {
      // مثلث يشير لليمين
      path.moveTo(size.width, size.height / 2);
      path.lineTo(0, 0);
      path.lineTo(0, size.height);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}