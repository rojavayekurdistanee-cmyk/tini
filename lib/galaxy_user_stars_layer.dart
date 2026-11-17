import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'galaxy_user_star.dart';

class GalaxyUserStarsLayer extends StatelessWidget {
  final List<GalaxyUserStar> stars;
  final GalaxyUserStar? ownStar;
  final Offset camera;
  final double zoom;
  final Animation<double> clock;
  final bool reduceMotion;
  final ValueChanged<GalaxyUserStar> onTap;
  const GalaxyUserStarsLayer({
    super.key,
    required this.stars,
    this.ownStar,
    required this.camera,
    required this.zoom,
    required this.clock,
    required this.onTap,
    this.reduceMotion = false,
  });

  static Offset screenPosition(
    GalaxyUserStar star,
    Size size,
    Offset camera,
    double zoom,
  ) => size.center(Offset.zero) + (star.position - camera) * zoom;

  static bool inExplorableArea(Offset point, Size size) =>
      Rect.fromLTRB(24, 76, size.width - 24, size.height - 112).contains(point);

  static GalaxyUserStar? hitTest(
    List<GalaxyUserStar> stars,
    Offset tap,
    Size size,
    Offset camera,
    double zoom,
  ) {
    GalaxyUserStar? nearest;
    var distance = 24.0;
    for (final star in stars) {
      if (!star.visible) continue;
      final point = screenPosition(star, size, camera, zoom);
      if (!inExplorableArea(point, size)) continue;
      final d = (point - tap).distance;
      if (d <= distance) {
        distance = d;
        nearest = star;
      }
    }
    return nearest;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      final displayedStars = [...stars, ?ownStar];
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: (details) {
          final star = hitTest(
            displayedStars,
            details.localPosition,
            size,
            camera,
            zoom,
          );
          if (star != null) onTap(star);
        },
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _UserStarsPainter(
              displayedStars,
              ownStar?.uid,
              camera,
              zoom,
              clock,
              reduceMotion,
            ),
            child: Stack(
              children: [
                if (ownStar != null &&
                    inExplorableArea(
                      screenPosition(ownStar!, size, camera, zoom),
                      size,
                    ))
                  Positioned(
                    left: screenPosition(ownStar!, size, camera, zoom).dx - 48,
                    top: screenPosition(ownStar!, size, camera, zoom).dy + 18,
                    width: 96,
                    child: const IgnorePointer(
                      child: Text(
                        'نجمتك',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF80CBC4),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          shadows: [Shadow(color: Colors.black, blurRadius: 6)],
                        ),
                      ),
                    ),
                  ),
                for (final star in displayedStars)
                  if (star.visible &&
                      inExplorableArea(
                        screenPosition(star, size, camera, zoom),
                        size,
                      ))
                    Positioned(
                      left: screenPosition(star, size, camera, zoom).dx - 24,
                      top: screenPosition(star, size, camera, zoom).dy - 24,
                      width: 48,
                      height: 48,
                      child: Semantics(
                        button: true,
                        label: star.uid == ownStar?.uid
                            ? 'نجمتك، ${star.fullName}'
                            : 'نجمة ${star.fullName}',
                        onTap: () => onTap(star),
                        child: const SizedBox.expand(),
                      ),
                    ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _UserStarsPainter extends CustomPainter {
  final List<GalaxyUserStar> stars;
  final String? ownUid;
  final Offset camera;
  final double zoom;
  final Animation<double> clock;
  final bool reduceMotion;
  _UserStarsPainter(
    this.stars,
    this.ownUid,
    this.camera,
    this.zoom,
    this.clock,
    this.reduceMotion,
  ) : super(repaint: clock);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final star in stars) {
      if (!star.visible) continue;
      final point = GalaxyUserStarsLayer.screenPosition(
        star,
        size,
        camera,
        zoom,
      );
      final isOwn = star.uid == ownUid;
      final radius = isOwn
          ? (3.6 * zoom).clamp(2.8, 8.0)
          : (2.7 * zoom).clamp(2.0, 6.0);
      if (!GalaxyUserStarsLayer.inExplorableArea(point, size)) continue;
      final phase = star.uid.codeUnits.fold(0, (a, b) => a + b) % 100;
      final light = reduceMotion
          ? 0.95
          : 0.88 + 0.12 * math.sin(clock.value * math.pi * 4 + phase);
      canvas.drawCircle(
        point,
        radius * 8,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Color(
                isOwn ? 0xFF00BFA5 : 0xFF80CBC4,
              ).withValues(alpha: (isOwn ? 0.7 : 0.5) * light),
              Colors.transparent,
            ],
          ).createShader(Rect.fromCircle(center: point, radius: radius * 8)),
      );
      for (final vector in [Offset(radius * 7, 0), Offset(0, radius * 9)]) {
        canvas.drawLine(
          point - vector,
          point + vector,
          Paint()
            ..strokeWidth = 0.8
            ..shader =
                LinearGradient(
                  begin: Alignment(-vector.dx.sign, -vector.dy.sign),
                  end: Alignment(vector.dx.sign, vector.dy.sign),
                  colors: [
                    Colors.transparent,
                    Color(
                      isOwn ? 0xFF80CBC4 : 0xFFFFFFFF,
                    ).withValues(alpha: light),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.5, 1],
                ).createShader(
                  Rect.fromPoints(point - vector, point + vector).inflate(0.01),
                ),
        );
      }
      canvas.drawCircle(
        point,
        radius,
        Paint()..color = Colors.white.withValues(alpha: light),
      );
      canvas.drawCircle(point, radius * 0.45, Paint()..color = Colors.white);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _UserStarsPainter old) =>
      old.stars != stars ||
      old.ownUid != ownUid ||
      old.camera != camera ||
      old.zoom != zoom ||
      old.reduceMotion != reduceMotion;
}
