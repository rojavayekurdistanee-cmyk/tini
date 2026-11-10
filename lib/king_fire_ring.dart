import 'dart:math' as math;

import 'package:flutter/material.dart';

// دورة رياضية مشتركة تعيد اللهب إلى موضعه الأول دون قفزة،
// مع الحفاظ على سرعات الحركة السابقة (20 × 2600 مللي ثانية).
const int _fireLoopCycles = 20;

/// حلقة لهب مرسومة باستخدام Flutter، دون صورة متحركة أو تدوير صورة الملك.
/// أبقينا واجهة KingFireRing كما هي حتى تظل الشاشات المرتبطة بها تعمل.
class KingFireRing extends StatefulWidget {
  final double size;
  final Widget child;

  const KingFireRing({
    super.key,
    required this.size,
    required this.child,
  });

  @override
  State<KingFireRing> createState() => _KingFireRingState();
}

class _KingFireRingState extends State<KingFireRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flameController;

  @override
  void initState() {
    super.initState();
    _flameController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600 * _fireLoopCycles),
    )..repeat();
  }

  @override
  void dispose() {
    _flameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        SizedBox.square(
          dimension: widget.size,
          child: IgnorePointer(
child: RepaintBoundary(
  child: Transform.scale(
    scale: 1.09,
    child: CustomPaint(
      painter: _FireTonguesPainter(_flameController),
    ),
  ),
),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _FireTonguesPainter extends CustomPainter {
  final Animation<double> motion;

  _FireTonguesPainter(this.motion) : super(repaint: motion);

  static const int _flameCount = 24;
  static const double _twoPi = math.pi * 2;

  @override
  void paint(Canvas canvas, Size size) {
    final double side = math.min(size.width, size.height);
    if (side <= 0) return;

    final Offset center = Offset(size.width / 2, size.height / 2);
    final double baseRadius = side * 0.385;
    final double phase = motion.value * _twoPi * _fireLoopCycles;

    // لا يوجد لون خلفية: كل ما عدا النار شفاف ليتطابق مع أي بطاقة.
    final Rect shaderRect = Rect.fromCircle(
      center: center,
      radius: side * 0.51,
    );

    // هالة خفيفة محصورة حول الدائرة، بلا blur ثقيل على الأجهزة المتوسطة.
    final Paint glow = Paint()
      ..shader = const RadialGradient(
        colors: [
          Color(0x00FF6B10),
          Color(0x00FF6B10),
          Color(0x25FF6B10),
          Color(0x00FF6B10),
        ],
        stops: [0.66, 0.75, 0.88, 1.0],
      ).createShader(shaderRect);
    canvas.drawCircle(center, side * 0.51, glow);

    final Paint emberPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = const RadialGradient(
        colors: [
          Color(0xFFFFD86A),
          Color(0xFFFF971E),
          Color(0xFFF74B0A),
          Color(0x00F74B0A),
        ],
        stops: [0.0, 0.75, 0.94, 1.0],
      ).createShader(shaderRect);

    final Paint innerFlamePaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = const RadialGradient(
        colors: [
          Color(0xFFFFFAD0),
          Color(0xFFFFE16C),
          Color(0xFFFFA82B),
          Color(0x00FF7A12),
        ],
        stops: [0.0, 0.68, 0.88, 1.0],
      ).createShader(shaderRect);

    // ألسنة متفرقة ذات رؤوس مدببة؛ كل لسان يتلوى ويطول ويقصر.
    // الزوايا ثابتة، لذلك لا يحدث دوران للحلقة كاملة.
    for (int i = 0; i < _flameCount; i++) {
      final double variation =
          0.5 + 0.5 * math.sin(i * 2.399963229728653);
      final double angle =
          -math.pi / 2 + _twoPi * (i + 0.12 * variation) / _flameCount;
      final double pulse =
          0.5 + 0.5 * math.sin(phase * 1.4 + i * 1.82);
      final double flutter =
          math.sin(phase * 2.15 + i * 2.77);

final double height = side *
    (0.065 + 0.019 * variation + 0.034 * pulse);
final double width = side * (0.023 + 0.009 * variation);
      final double sideways =
          side * (0.014 * flutter + 0.005 * math.sin(phase + i));

      final Offset radial = Offset(math.cos(angle), math.sin(angle));
      final Offset tangent = Offset(-radial.dy, radial.dx);
      final Offset base = center + radial * baseRadius;
      final Offset tip =
          base + radial * height + tangent * sideways;

      final Path tongue = _tonguePath(
        base: base,
        tip: tip,
        radial: radial,
        tangent: tangent,
        width: width,
        bend: sideways,
      );
      canvas.drawPath(tongue, emberPaint);

      // قلب أصفر حار داخل كل لسان: يبرز شكل النار بدل الشريط المتموج.
      final Offset hotBase = center + radial * (baseRadius - side * 0.010);
      final Offset hotTip = base +
          radial * (height * (0.60 + 0.06 * pulse)) +
          tangent * (sideways * 0.52);
      canvas.drawPath(
        _tonguePath(
          base: hotBase,
          tip: hotTip,
          radial: radial,
          tangent: tangent,
          width: width * 0.53,
          bend: sideways * 0.45,
        ),
        innerFlamePaint,
      );
    }

    // جمر متوهج حول قاعدة اللهب ليوصل الألسنة بصورة ناعمة.
    final Paint baseRing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = side * 0.036
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        colors: [
          Color(0xFFFFB32D),
          Color(0xFFFFE58C),
          Color(0xFFFF6A14),
          Color(0xFFFFCC51),
          Color(0xFFFFB32D),
        ],
      ).createShader(shaderRect);
    canvas.drawCircle(center, baseRadius, baseRing);

    final Paint hotRing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = side * 0.010
      ..color = const Color(0xFFFFF0A0).withValues(alpha: 0.78);
    canvas.drawCircle(center, baseRadius - side * 0.011, hotRing);

    // شرارات صغيرة صاعدة، قليلة العدد لتجنب الضغط على المعالج الرسومي.
    final Paint spark = Paint()..color = const Color(0xFFFFC65B);
    for (int i = 0; i < 6; i++) {
      final double a = -math.pi / 2 + _twoPi * (i + 0.2) / 6;
      final double cycle = (motion.value * _fireLoopCycles + i * 0.19) % 1.0;
      final Offset radial = Offset(math.cos(a), math.sin(a));
      final Offset p = center +
          radial * (side * (0.446 + cycle * 0.043)) +
          Offset(side * 0.006 * math.sin(i + phase), -side * 0.008 * cycle);
      // تظهر الشرارة وتختفي بسلاسة عند كل دورة، فلا تقفز بإضاءة مفاجئة.
      final double sparkFade = math.sin(math.pi * cycle);
      spark.color = const Color(0xFFFFC65B)
          .withValues(alpha: 0.55 * sparkFade * sparkFade);
      canvas.drawCircle(p, side * (0.0035 + 0.003 * (1.0 - cycle)), spark);
    }
  }

  Path _tonguePath({
    required Offset base,
    required Offset tip,
    required Offset radial,
    required Offset tangent,
    required double width,
    required double bend,
  }) {
    final Offset left = base - tangent * width;
    final Offset right = base + tangent * width;
    final Offset startLeft = base + radial * (width * 1.2) - tangent * width;
    final Offset middleLeft =
        base + (tip - base) * 0.64 - tangent * (width * 0.7) +
        tangent * (bend * 0.25);
    final Offset middleRight =
        base + (tip - base) * 0.56 + tangent * (width * 0.62) +
        tangent * (bend * 0.15);
    final Offset startRight =
        base + radial * (width * 0.85) + tangent * width;

    return Path()
      ..moveTo(left.dx, left.dy)
      ..cubicTo(
        startLeft.dx,
        startLeft.dy,
        middleLeft.dx,
        middleLeft.dy,
        tip.dx,
        tip.dy,
      )
      ..cubicTo(
        middleRight.dx,
        middleRight.dy,
        startRight.dx,
        startRight.dy,
        right.dx,
        right.dy,
      )
      ..quadraticBezierTo(
        base.dx - radial.dx * width * 0.3,
        base.dy - radial.dy * width * 0.3,
        left.dx,
        left.dy,
      )
      ..close();
  }

  @override
  bool shouldRepaint(covariant _FireTonguesPainter oldDelegate) =>
      oldDelegate.motion != motion;
}
