import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Procedural Nature overlays. No network assets or new dependencies are used.
/// Positions are deterministic functions of the effect-local playback time:
/// seeking and thumbnail previews therefore reproduce the same scene.
class TiniNatureEffectsPreview {
  static const category = 'الطبيعة';
  static const supported = <String>{
    'Fluffy Snow', 'Snowfall', 'Snow', 'Snowflake', 'Snow II',
    'Flying Snow', 'Rain FX', 'Rain', 'Falling Leaves', 'Petals',
    'Rose Petals', 'Soft Rose', 'Pink Petals', 'Sakura',
    'Sunset 1', 'Sunset 2', 'Sunshine', 'Tree Shade 2', 'Heat Wave', 'Smog',
  };

  static double thumbnailSeconds(String name) =>
      {'Falling Leaves', 'Rose Petals', 'Sakura', 'Sunshine'}.contains(name)
          ? 1.17 : .83;

  static Widget apply({required String name, required Widget child,
      required double elapsed, required double start, required double end}) {
    if (!supported.contains(name)) return child;
    final t = math.max(0.0, elapsed - start);
    Widget base = child;
    switch (name) {
      case 'Sunset 1':
        base = ColorFiltered(colorFilter: const ColorFilter.matrix([
          1.12, .04, 0, 0, 11, 0, 1.02, 0, 0, 2,
          0, 0, .79, 0, 0, 0, 0, 0, 1, 0,
        ]), child: base);
        break;
      case 'Sunset 2':
        base = ColorFiltered(colorFilter: const ColorFilter.matrix([
          1.08, .03, .02, 0, 10, 0, .92, .02, 0, 0,
          .02, 0, .91, 0, 3, 0, 0, 0, 1, 0,
        ]), child: base);
        break;
      case 'Sunshine':
        base = ColorFiltered(colorFilter: const ColorFilter.mode(
          Color(0x1CFFCA65), BlendMode.screen), child: base);
        break;
      case 'Snow II':
        // Match the subtly cool sleet palette used by the export recipe.
        base = ColorFiltered(colorFilter: const ColorFilter.matrix([
          .96, 0, 0, 0, 0, 0, 1.0, 0, 0, 0,
          0, 0, 1.05, 0, 2, 0, 0, 0, 1, 0,
        ]), child: base);
        break;
      case 'Smog':
        base = ImageFiltered(imageFilter: ui.ImageFilter.blur(
          sigmaX: 1.15, sigmaY: 1.15), child: base);
        break;
      case 'Heat Wave':
        // Mild live wobble; the export uses actual sample displacement.
        base = Transform.translate(offset: Offset(
          1.5 * math.sin(t * 7.5), .9 * math.cos(t * 8.4)), child: base);
        break;
    }
    return ClipRect(child: Stack(fit: StackFit.passthrough, children: [
      base,
      Positioned.fill(child: IgnorePointer(child: CustomPaint(
        painter: _NaturePainter(name, t),
      ))),
    ]));
  }
}

class _NaturePainter extends CustomPainter {
  final String name;
  final double time;
  const _NaturePainter(this.name, this.time);

  static double _rand(int v) {
    var k = (v * 1103515245 + 12345) & 0x7fffffff;
    k = (k ^ (k >> 13)) & 0x7fffffff;
    return k / 2147483647.0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width, h = size.height;
    final short = math.min(w, h);
    final t = time;
    final soft = Paint()..isAntiAlias = true;

    void softGlow(Offset center, double r, Color color, double intensity) {
      if (intensity <= 0 || r <= 0) return;
      final opacity = intensity.clamp(0.0, 1.0).toDouble();
      canvas.drawCircle(center, r, Paint()
        ..shader = ui.Gradient.radial(center, r, [
          color.withValues(alpha: opacity),
          color.withValues(alpha: opacity * .40),
          color.withValues(alpha: 0),
        ], const [0, .36, 1])
        ..blendMode = BlendMode.screen);
    }

    void leaf(Offset pos, double scale, double angle, Color color) {
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(angle);
      canvas.scale(scale);
      final path = Path()
        ..moveTo(0, -1.4)
        ..cubicTo(1.9, -2.7, 3, -.5, 1.2, 1)
        ..quadraticBezierTo(.7, 2.2, 0, 3.2)
        ..quadraticBezierTo(-.7, 2.2, -1.2, 1)
        ..cubicTo(-3, -.5, -1.9, -2.7, 0, -1.4)
        ..close();
      canvas.drawPath(path, Paint()..color = color);
      canvas.drawLine(const Offset(0,-1.1), const Offset(0,2.8), Paint()
        ..color = const Color(0x66A04412)..strokeWidth = .12);
      canvas.restore();
    }

    void blossom(Offset pos, double radius, double angle,
        Color color, {bool sakura = false}) {
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(angle);
      if (sakura) {
        for (var petal = 0; petal < 5; petal++) {
          canvas.save();
          canvas.rotate(petal * 2 * math.pi / 5);
          canvas.drawOval(Rect.fromCenter(center: Offset(0, -radius*.68),
              width: radius*.93, height: radius*1.26),
            Paint()..color = color);
          canvas.restore();
        }
        canvas.drawCircle(Offset.zero, radius*.20,
          Paint()..color = const Color(0xFFFFDB77));
      } else {
        final path = Path()
          ..moveTo(0, -radius)
          ..cubicTo(radius * 1.4, -radius*.9, radius*1.4,
              radius*.45, 0, radius)
          ..cubicTo(-radius*1.3, radius*.42, -radius*.95,
              -radius*.75, 0, -radius)
          ..close();
        canvas.drawPath(path, Paint()..color = color);
        canvas.drawLine(Offset(0,-radius*.8), Offset(0,radius*.75),
          Paint()..color = Colors.white.withValues(alpha: .28)
            ..strokeWidth = math.max(.35,radius*.08));
      }
      canvas.restore();
    }


    if (name == 'Sunset 1' || name == 'Sunset 2' || name == 'Sunshine') {
      final warm = name != 'Sunset 2';
      final cx = name == 'Sunset 2' ? w*.76 : w*.05;
      final cy = name == 'Sunshine' ? h*.10 : h*.23;
      softGlow(Offset(cx,cy), math.max(w,h)*.78,
          warm ? const Color(0xFFFFA133) : const Color(0xFFFF8396),
          name == 'Sunshine' ? .42 : .35);
      softGlow(Offset(cx,cy), short*.62,
          name == 'Sunset 2' ? const Color(0xFFFFC7BF) : const Color(0xFFFFEF9D), .35);
      if (name == 'Sunshine') {
        for (var i=0;i<12;i++) {
          final angle=i*math.pi/6+math.sin(t*.55)*.06;
          final dir=Offset(math.cos(angle),math.sin(angle));
          canvas.drawLine(Offset(cx,cy),
            Offset(cx+dir.dx*math.max(w,h),cy+dir.dy*math.max(w,h)),Paint()
            ..color=const Color(0x1DFFF7CA)
            ..strokeWidth=short*(.013+.025*_rand(i+3))
            ..blendMode=BlendMode.screen);
        }
      }
      return;
    }

    if (name == 'Tree Shade 2') {
      canvas.save();
      canvas.translate(w*.05 + math.sin(t*.6)*short*.035, -h*.05);
      canvas.rotate(.23);
      final trunk = Path()..moveTo(-w*.2,0)
        ..cubicTo(w*.15,h*.17,w*.27,h*.29,w*.59,h*.42);
      canvas.drawPath(trunk,Paint()..color=const Color(0x39232319)
        ..strokeWidth=short*.065..style=PaintingStyle.stroke
        ..strokeCap=StrokeCap.round);
      for (var i=0;i<12;i++) {
        final x=.03+i*.058;
        final y=.08+math.sin(i*2.8)*.13+i*.015;
        canvas.drawOval(Rect.fromCenter(center: Offset(w*x,h*y),
          width:short*(.09+.06*_rand(i+31)),
          height:short*(.19+.09*_rand(i+38))), Paint()
          ..color=const Color(0x222D3420));
      }
      canvas.restore();
      return;
    }

    if (name == 'Heat Wave') {
      for (var band=0;band<9;band++) {
        final y=h*(.07+band*.11);
        final path=Path();
        for (var j=0;j<=28;j++) {
          final x=w*j/28;
          final py=y+short*.018*math.sin(j*.67+band*.9-t*8.0);
          if (j==0) path.moveTo(x,py); else path.lineTo(x,py);
        }
        canvas.drawPath(path,Paint()..color=const Color(0x26FFF3E3)
          ..style=PaintingStyle.stroke..strokeWidth=short*.011);
      }
      return;
    }
    if (name == 'Smog') {
      canvas.drawRect(Offset.zero & size,
        Paint()..color=const Color(0x209FA5A5));
      for(var i=0;i<9;i++) {
        final x=w*(_rand(i*3+2)*1.5-.2)+t*short*(.01+.015*i);
        final y=h*(.13+i*.105);
        softGlow(Offset(x% (w*1.8),y),short*(.35+_rand(i+4)*.55),
          const Color(0xFFD9DCD7),.17);
      }
      return;
    }

    // Independent snow animations. These six styles deliberately do not share
    // the rain/petal particle recipe: each has its own geometry and motion.
    if (const <String>{
      'Fluffy Snow', 'Snowfall', 'Snow', 'Snowflake', 'Snow II',
      'Flying Snow',
    }.contains(name)) {
      _paintSnow(canvas, size);
      return;
    }

    final isRain = name == 'Rain' || name == 'Rain FX';
    final isLeaves = name == 'Falling Leaves';
    final isPetals = {'Petals','Rose Petals','Soft Rose',
      'Pink Petals','Sakura'}.contains(name);
    final dense = name == 'Rain FX';
    final count = isRain ? (dense ? 92 : 65) : isLeaves ? 13 : 25;
    for (var i=0;i<count;i++) {
      final seed=_rand(i*9+41);
      final spread=_rand(i*7+16);
      final phase=t*(isRain ? (name=='Rain FX' ? .86 : .59) :
          isLeaves ? .115 : .085);
      final y=((seed+phase*(.55+_rand(i+81)))*1.35)%1.35-.17;
      final sway = math.sin(t*(.9+spread*1.1)+seed*15)*
          (isRain ? .009 : isLeaves ? .070 : .038);
      final drift = t*(isRain ? .006 : .011);
      final x=(spread+sway+drift)%1.18-.09;
      final at=Offset(x*w,y*h);
      final r=short*(isRain ? .002 : isLeaves ? (.024+.018*_rand(i+8))
        : (.013+.023*_rand(i+9)));
      final angle=t*(.65+_rand(i+11)*1.8)+seed*9;
      if (isRain) {
        final length=h*(name=='Rain FX' ? .065 : .035)*(.55+_rand(i+10));
        soft.color = name=='Rain FX' ? const Color(0xAAE2F5FF)
            : const Color(0x8AB6D3E3);
        soft.strokeWidth=math.max(.6,short*(name=='Rain FX' ? .0033 : .0018));
        soft.strokeCap=StrokeCap.round;
        canvas.drawLine(at,at.translate(-length*.23,length),soft);
      } else if (isLeaves) {
        const colors = <Color>[Color(0xFFF3B128),Color(0xFFE86421),
          Color(0xFFC83A1E),Color(0xFFFFD950),Color(0xFFB57925)];
        leaf(at,r,angle,colors[i%colors.length]);
      } else if (isPetals) {
        final palette = name=='Soft Rose'
          ? const <Color>[Color(0xFFEADAE3),Color(0xFFFFECF5),Color(0xFFE5A7BC)]
          : name=='Rose Petals'
            ? const <Color>[Color(0xFFE94D68),Color(0xFFF792A7),Color(0xFFB82544)]
            : const <Color>[Color(0xFFFFB5D2),Color(0xFFEE76A6),Color(0xFFFFD0E3)];
        blossom(at,r,angle,palette[i%palette.length],sakura:name=='Sakura');

      }
    }
  }

  /// Six distinct deterministic snow styles. The preview is independent of
  /// the render frame rate and can be evaluated at arbitrary seek positions.
  void _paintSnow(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final s = math.min(w, h);
    final t = time;
    double wrap(double n) => n - n.floorToDouble();

    void pearl(Offset p, double r, double alpha, {bool halo = false,
        Color tint = const Color(0xFFF8FCFF)}) {
      final opacity = alpha.clamp(0.0, 1.0).toDouble();
      if (halo) {
        canvas.drawCircle(p, r * 2.8, Paint()
          ..shader = ui.Gradient.radial(p, r * 2.8, [
            tint.withValues(alpha: opacity * .56),
            tint.withValues(alpha: opacity * .16),
            tint.withValues(alpha: 0),
          ], const [0.0, .42, 1.0])
          ..blendMode = BlendMode.screen);
      }
      canvas.drawCircle(p, r, Paint()
        ..color = tint.withValues(alpha: opacity)
        ..isAntiAlias = true);
    }

    void crystal(Offset at, double r, double spin, double opacity,
        {bool elaborate = false}) {
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(spin);
      final ink = Paint()
        ..color = const Color(0xFFE9F6FF).withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(.65, r * (elaborate ? .13 : .16));
      for (var arm = 0; arm < 6; arm++) {
        final a = arm * math.pi / 3;
        final dx = math.cos(a), dy = math.sin(a);
        canvas.drawLine(Offset.zero, Offset(dx * r, dy * r), ink);
        if (elaborate || r > 3.2) {
          final bx = dx * r * .64, by = dy * r * .64;
          for (final sign in <double>[-1, 1]) {
            final side = a + math.pi + sign * .63;
            canvas.drawLine(Offset(bx, by), Offset(
              bx + math.cos(side) * r * .30,
              by + math.sin(side) * r * .30), ink);
          }
        }
      }
      if (elaborate) {
        canvas.drawCircle(Offset.zero, r * .12,
            Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: opacity));
      }
      canvas.restore();
    }

    // Particle seeds and normalized paths match the FFmpeg export formulas.
    int particleSeed(int i, int salt) => (i * 131 + salt * 73 + 29) % 997;
    double x0(int i, int salt) =>
        ((particleSeed(i, salt) * 47 + 31) % 997) / 997.0;
    double y0(int i, int salt) =>
        ((particleSeed(i, salt) * 191 + 19) % 997) / 997.0;
    double phase(int i, int salt) =>
        (particleSeed(i, salt) % 67) / 11.0;

    switch (name) {
      case 'Fluffy Snow':
        // Large soft snow-bokeh plus small crisp flakes in two depth layers.
        for (var i = 0; i < 23; i++) {
          final big = i % 3 == 0;
          final x = wrap(x0(i, 1) + .026 * math.sin(
              (big ? .43 : .70) * t + phase(i, 1)));
          final y = wrap(y0(i, 1) + t * (big ? .036 : .076));
          pearl(Offset(x * w, y * h),
              s * (big ? .0135 : .0055), big ? .45 : .78,
              halo: big);
        }
        break;
      case 'Snowfall':
        // Falling six-arm crystals, large enough to recognize individually.
        for (var i = 0; i < 26; i++) {
          final x = wrap(x0(i, 2) + t * .008 +
              .045 * math.sin(.7 * t + phase(i, 2)));
          final y = wrap(y0(i, 2) + t * (.09 + (i % 5) * .012));
          final p = Offset(x * w, y * h);
          pearl(p, s * .017, .15, halo: true);
          crystal(p, s * (.016 + (i % 4) * .004),
              t * .17 + i * .57, .75, elaborate: true);
        }
        break;
      case 'Snow':
        // Fine individual snow dots with gentle, unhurried vertical movement.
        for (var i = 0; i < 49; i++) {
          final x = wrap(x0(i, 3) + .012 * math.sin(
              .8 * t + phase(i, 3)));
          final y = wrap(y0(i, 3) + t * (.05 + (i % 5) * .013));
          pearl(Offset(x * w, y * h),
              s * (.0015 + (i % 3) * .0010),
              .55 + (i % 4) * .13);
        }
        break;
      case 'Snowflake':
        // Large sparse crystalline shapes that rotate individually.
        for (var i = 0; i < 13; i++) {
          final x = wrap(x0(i, 4) + .06 * math.sin(
              .65 * t + phase(i, 4)));
          final y = wrap(y0(i, 4) + t * (.05 + (i % 3) * .018));
          final p = Offset(x * w, y * h);
          pearl(p, s * .021, .20, halo: true);
          crystal(p, s * (.031 + (i % 3) * .008),
              t * (.36 + (i % 3) * .11) + phase(i, 4),
              .84, elaborate: true);
        }
        break;
      case 'Snow II':
        // Dense, cool diagonal snow grains and fast short streaks.
        for (var i = 0; i < 65; i++) {
          final x = wrap(x0(i, 5) + t * (.018 + (i % 4) * .004));
          final y = wrap(y0(i, 5) + t * (.125 + (i % 6) * .032));
          final p = Offset(x * w, y * h);
          final r = s * (.0012 + (i % 3) * .0007);
          canvas.drawLine(p.translate(-r * .8, -r * 1.7),
              p.translate(r*.2, r*2), Paint()
                ..color = const Color(0xFFD5E9FF).withValues(
                    alpha: .40 + (i % 5) * .11)
                ..strokeWidth = math.max(.6, r)
                ..strokeCap = StrokeCap.round);
        }
        break;
      case 'Flying Snow':
        // Crosswind rushes flakes horizontally; no slow vertical snowfall.
        for (var i = 0; i < 59; i++) {
          final x = wrap(x0(i, 6) + t * (.19 + (i % 6) * .048)
              + .013 * math.sin(2.4*t + phase(i, 6)));
          final y = wrap(y0(i, 6) + t * (.017 + (i % 5) * .008));
          final p = Offset(x * w, y * h);
          final r = s * (.0013 + (i % 4) * .0005);
          canvas.drawLine(p.translate(-r * (6.0 + i % 4), 0), p,
              Paint()
                ..color = const Color(0xFFEDF8FF).withValues(
                    alpha: .44 + (i % 5)*.11)
                ..strokeWidth = math.max(.6, r)
                ..strokeCap = StrokeCap.round);
          if (i % 8 == 0) pearl(p, r, .75);
        }
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _NaturePainter oldDelegate) =>
      oldDelegate.name!=name || oldDelegate.time!=time;
}
