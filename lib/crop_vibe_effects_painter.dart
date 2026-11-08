import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'crop_effects_model.dart';
import 'crop_vibe_effects_spec.dart';

/// Procedural, self-contained Vibe sprites. The SAME painter draws the editor
/// preview and the alpha PNG frames used for the exported video. No downloads,
/// proprietary media, microphone, camera or legacy effects implementation.
class TiniVibeEffectsPainter extends CustomPainter {
  final List<TiniAppliedEffect> effects;
  final double seconds;
  const TiniVibeEffectsPainter({required this.effects, required this.seconds});

  static const String category = TiniVibeEffectsSpec.category;
  static const Set<String> supported = TiniVibeEffectsSpec.supported;

  static double _rand(int x) {
    final v = math.sin(x * 12.9898 + 78.233) * 43758.5453123;
    return v - v.floorToDouble();
  }

  static int _seed(String name) {
    var hash = 17;
    for (final code in name.codeUnits) { hash = ((hash * 31) ^ code) & 0x7fffffff; }
    return hash;
  }

  static Color _color(String name, int index, double alpha) {
    final gold = name.contains('Gold') || name.contains('Glitter') || name.contains('Bling') ||
        name.contains('Gleam') || name.contains('Sequin') || name.contains('Spark');
    final love = name.contains('Love') || name.contains('Heart') || name == 'In Love' ||
        name.contains('Girl');
    final winter = name.contains('Snow') || name.contains('Christmas') || name.contains('Xmas');
    final colors = gold ? const [Color(0xFFFFE8A1), Color(0xFFFFB94A), Color(0xFFFFFFFF)] :
      love ? const [Color(0xFFFF5C9F), Color(0xFFFFB0CA), Color(0xFFFF306A)] :
      winter ? const [Color(0xFFEFFFFF), Color(0xFF9DEAFF), Color(0xFFFFF4CF)] :
      const [Color(0xFF77E5FF), Color(0xFFFF7ADA), Color(0xFFFFE887), Color(0xFFB8A0FF)];
    if (name == 'Pink Sparkles') {
      return const Color(0xFFFF8CC9).withValues(alpha: alpha.clamp(0.0, 1.0).toDouble());
    }
    if (name == 'Color Hearts' || name == 'Rainbow Hea...' || name == 'Color Riot') {
      return HSVColor.fromAHSV(alpha.clamp(0.0, 1.0).toDouble(),
          ((index * 37) % 360).toDouble(), .72, 1).toColor();
    }
    return colors[index % colors.length].withValues(alpha: alpha.clamp(0.0, 1.0).toDouble());
  }

  static void _star(Canvas c, Offset p, double radius, Paint paint,
      {int tips = 5, double inside = .46}) {
    final path = Path();
    for (var j = 0; j < tips * 2; j++) {
      final a = j * math.pi / tips - math.pi / 2;
      final r = j.isEven ? radius : radius * inside;
      final x = p.dx + r * math.cos(a), y = p.dy + r * math.sin(a);
      if (j == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
    }
    path.close();
    c.drawPath(path, paint);
  }

  static void _heart(Canvas c, Offset p, double r, Paint paint) {
    final path = Path()..moveTo(p.dx, p.dy + r * .80)
      ..cubicTo(p.dx - r * 1.7, p.dy - r * .14,
        p.dx - r * .86, p.dy - r * 1.24, p.dx, p.dy - r * .48)
      ..cubicTo(p.dx + r * .86, p.dy - r * 1.24,
        p.dx + r * 1.7, p.dy - r * .14, p.dx, p.dy + r * .80)
      ..close();
    c.drawPath(path, paint);
  }

  static void _flower(Canvas c, Offset p, double r, Paint paint, int petals) {
    for (var j = 0; j < petals; j++) {
      final a = 2 * math.pi * j / petals;
      c.save();
      c.translate(p.dx, p.dy);
      c.rotate(a);
      c.drawOval(Rect.fromCenter(center: Offset(0, -r * .65),
          width: r * .83, height: r * 1.16), paint);
      c.restore();
    }
    c.drawCircle(p, r * .22, Paint()..color = const Color(0xFFFFD85E));
  }

  static void _butterfly(Canvas c, Offset p, double r, Paint paint, double beat) {
    c.save();
    c.translate(p.dx, p.dy);
    final spread = .35 + .65 * beat.abs();
    for (final side in [-1.0, 1.0]) {
      final wing = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(side * r * 1.30 * spread, -r * 1.52,
            side * r * 1.35 * spread, -r * .22)
        ..quadraticBezierTo(side * r * 1.35 * spread, r * 1.16,
            0, r * .23)
        ..close();
      c.drawPath(wing, paint);
      c.drawLine(Offset(0, -r * .28), Offset(side * r * .28, -r * .91),
          Paint()..color = const Color(0xDDFFFFFF)..strokeWidth = math.max(.6, r * .06));
    }
    c.drawOval(Rect.fromCenter(center: Offset.zero, width: r * .15, height: r),
        Paint()..color = const Color(0xFF493360));
    c.restore();
  }

  static void _snowflake(Canvas c, Offset p, double r, Paint paint) {
    final stroke = Paint()..color = paint.color..strokeWidth = math.max(1, r * .10)
      ..strokeCap = StrokeCap.round;
    for (var j = 0; j < 3; j++) {
      final a = j * math.pi / 3;
      final d = Offset(math.cos(a), math.sin(a)) * r;
      c.drawLine(p - d, p + d, stroke);
    }
  }

  static void _glow(Canvas c, Offset p, double r, Color color) {
    final radial = ui.Gradient.radial(p, r * 2.1, [color, color.withValues(alpha: 0)]);
    c.drawCircle(p, r * 2.1, Paint()..shader = radial);
  }

  static void _fireworks(Canvas canvas, Size size, String name, double t, int seed) {
    final unit = math.min(size.width, size.height);
    final bursts = name.contains(' III') ? 4 : name.contains(' I') ? 2 : 3;
    for (var j = 0; j < bursts; j++) {
      final epoch = ((t + j * .72) / 1.8).floor();
      final age = ((t + j * .72) / 1.8) - epoch;
      if (age > .83) continue;
      final bx = size.width * (.16 + .68 * _rand(seed + epoch * 17 + j * 31));
      final by = size.height * (.18 + .47 * _rand(seed + epoch * 19 + j * 47));
      final radius = unit * (.035 + age * .32);
      final alpha = math.pow(1 - age, 1.4).toDouble() * .9;
      for (var k = 0; k < 22; k++) {
        final a = 2 * math.pi * k / 22 + _rand(k + seed) * .2;
        final length = radius * (.72 + _rand(k * 7 + seed) * .47);
        final p1 = Offset(bx + math.cos(a) * length * .75,
            by + math.sin(a) * length * .75 + age * age * unit * .13);
        final p2 = Offset(bx + math.cos(a) * length,
            by + math.sin(a) * length + age * age * unit * .13);
        final color = _color(name, j + k ~/ 7, alpha);
        canvas.drawLine(p1, p2, Paint()..color = color
            ..strokeWidth = math.max(1.1, unit * .003)
            ..strokeCap = StrokeCap.round);
        if (k.isEven) _glow(canvas, p2, unit * .007, color);
      }
    }
  }

  static String _kind(String name) {
    if (name == 'Spiderweb') return 'web';
    if (name == 'Christmas D...') return 'doodle';
    if (name == 'Shining Moon' || name == 'Moonlight Ex...') return 'moon';
    if (name == 'Flickering Lig...') return 'flicker';
    if (name == 'Starburst' || name == 'Snowburst' || name == 'Glitter Bomb') return 'burst';
    if (name == 'Heart Rays' || name == 'Love Zoom' ||
        name == 'Heart Project...') return 'heroHeart';
    if (name == 'Iridescent' || name == 'Refraction') return 'prism';
    if (name.contains('Butterfly') || name == 'Butterflies') return 'butterfly';
    if (name == 'Flowers' || name.contains('petals') || name == 'Spring Bloss...') return 'petal';
    if (name == 'Watercolor') return 'watercolor';
    if (name.contains('Firework') || name == 'July 4th Fire...') return 'fireworks';
    if (name == 'Cyberpunk Li...' || name == 'Fluorescence') return 'neon';
    if (name == 'Floating Can...') return 'candle';
    if (name == 'Magic Transf...' || name == 'Utopia') return 'magic';
    if (name == 'Snow Bokeh' || name == 'Winter Lights') return 'bokeh';
    if (name.contains('Snow') || name == 'Winter Aesth...') return 'snow';
    if (name.contains('Confetti') || name.contains('Sequin') || name == 'Color Riot' ||
        name == 'Pizzazz 2' || name.contains('Sparkly Conf') ||
        name == 'Falling Gold ...' || name == 'Streamers') return 'confetti';
    if (name == 'Meteor Show...' || name == 'Shooting Sta...') return 'meteor';
    if (name.contains('Heart') || name.contains('Love') || name == 'In Love' ||
        name == 'Rainbow Hea...' || name == 'Romantic He...') return 'hearts';
    if (name == 'Firefly' || name == 'Glowworm') return 'firefly';
    if (name == 'Whimsical' || name == 'Circling Spar...') return 'ribbon';
    if (name.contains('Christmas Or...')) return 'ornament';
    return 'star';
  }

  static void _doodle(Canvas c, Size size, double t, int occurrence) {
    final color = occurrence == 1 ? const Color(0xFFCC3329) :
        const Color(0xFF19C6BE);
    final stroke = Paint()..color = color..strokeWidth = math.max(1.5, size.width * .005)
        ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    final unit = math.min(size.width, size.height);
    for (var i = 0; i < 22; i++) {
      final side = i.isEven ? 0.08 : 0.92;
      final p = Offset(size.width * (side + .012 * math.sin(t * 1.3 + i)),
          size.height * (.035 + i * .043));
      c.save(); c.translate(p.dx, p.dy); c.rotate(.2 * math.sin(t + i));
      if (i % 3 == 0) {
        _star(c, Offset.zero, unit * .045, stroke, tips: 6);
      } else if (i % 3 == 1) {
        c.drawRect(Rect.fromCenter(center: Offset.zero,
            width: unit * .07, height: unit * .07), stroke);
        c.drawLine(Offset(-unit * .04, 0), Offset(unit * .04, 0), stroke);
      } else {
        _flower(c, Offset.zero, unit * .032, stroke, 5);
      }
      c.restore();
    }
    for (var i = 0; i < 8; i++) {
      _star(c, Offset(size.width * (.14 + i * .1), size.height * .025),
        unit * .020, stroke, tips: 6);
    }
  }

  static void _heroHeart(Canvas c, Size size, String name, double t) {
    final r = math.min(size.width, size.height) * .30;
    final pulse = name == 'Love Zoom' ? .4 + (t * .9) % 1.7 :
        name == 'Heart Rays' ? .78 + .14 * math.sin(t * 6).abs() :
        .9 + .06 * math.sin(t * 2);
    final centre = Offset(size.width * .5, size.height * .43);
    final heart = Paint()..color = const Color(0x99FF66B7);
    _glow(c, centre, r * 1.15, const Color(0x77FF60B9));
    _heart(c, centre, r * pulse, heart);
    if (name == 'Heart Rays') {
      for (var i = 0; i < 16; i++) {
        final a = i * math.pi / 8;
        final from = centre + Offset(math.cos(a), math.sin(a)) * r;
        final to = centre + Offset(math.cos(a), math.sin(a)) * r * (1.25 + .12 * math.sin(t * 3 + i));
        c.drawLine(from, to, Paint()..color = const Color(0xBFFFF3CD)
            ..strokeWidth = math.max(1, r * .025));
      }
    }
  }

  static void _moon(Canvas c, Size size, double t) {
    final r = math.min(size.width, size.height) * .18;
    final p = Offset(size.width * (.76 + .08 * math.sin(t * .15)), size.height * .2);
    _glow(c, p, r, const Color(0x99B1DFFF));
    c.drawCircle(p, r * .64, Paint()..color = const Color(0xC8FFFBE7));
    c.drawCircle(p + Offset(-r * .3, -r * .2), r * .56,
        Paint()..color = const Color(0x774564A2)..blendMode = BlendMode.srcOver);
  }

  static void _burst(Canvas c, Size size, String name, double t) {
    final r = math.min(size.width, size.height) * (.08 + .19 * ((t * .5) % 1));
    final centre = Offset(size.width * (.55 + .12 * math.sin(t * .8)), size.height * .38);
    for (var i = 0; i < 55; i++) {
      final a = i * math.pi * 2 / 55;
      final p = centre + Offset(math.cos(a), math.sin(a)) * r;
      final paint = Paint()..color = name == 'Snowburst'
          ? const Color(0xC0FFFFFF) : _color(name, i, .77);
      if (name == 'Snowburst') _snowflake(c, p, r * .09, paint);
      else _star(c, p, r * .10, paint, tips: 4);
    }
  }

  /// Called for both a live on-screen canvas and a PNG export canvas.
  static void draw(Canvas canvas, Size size, List<TiniAppliedEffect> effects, double seconds) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final fx in effects) {
      if (!fx.active(seconds)) continue;
      final desc = fx.descriptor;
      if (desc == null || desc.category != category || !supported.contains(desc.name)) continue;
      _drawEffect(canvas, size, desc.name, seconds - fx.startSeconds, desc.occurrence);
    }
    canvas.restore();
  }

  static void _drawEffect(Canvas c, Size size, String name, double t, int occurrence) {
    final seed = _seed(name);
    final kind = _kind(name);
    final unit = math.min(size.width, size.height);
    if (kind == 'doodle') { _doodle(c, size, t, occurrence); return; }
    if (kind == 'heroHeart') { _heroHeart(c, size, name, t); return; }
    if (kind == 'moon') { _moon(c, size, t); return; }
    if (kind == 'burst') { _burst(c, size, name, t); return; }
    if (kind == 'flicker') {
      final alpha = .09 + .18 * math.sin(t * 28).abs();
      c.drawRect(Offset.zero & size,
          Paint()..color = Colors.white.withValues(alpha: alpha));
      return;
    }
    if (kind == 'fireworks') {
      _fireworks(c, size, name, t, seed);
      return;
    }
    if (kind == 'web') {
      final paint = Paint()..color = const Color(0xBBDDDDEB)..style = PaintingStyle.stroke
          ..strokeWidth = math.max(.7, unit * .002);
      for (var corner = 0; corner < 2; corner++) {
        final cx = corner == 0 ? 0.0 : size.width;
        for (var k = 0; k < 8; k++) {
          final angle = (corner == 0 ? .02 : math.pi - .02) +
              (corner == 0 ? 1 : -1) * k * math.pi / 15;
          c.drawLine(Offset(cx, 0), Offset(cx + unit * .7 * math.cos(angle),
              unit * .7 * math.sin(angle)), paint);
        }
        for (var ring = 1; ring <= 5; ring++) {
          final path = Path();
          for (var k = 0; k < 8; k++) {
            final angle = (corner == 0 ? .02 : math.pi - .02) +
                (corner == 0 ? 1 : -1) * k * math.pi / 15;
            final r = unit * ring * .115;
            final x = cx + r * math.cos(angle), y = r * math.sin(angle);
            if (k == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
          }
          c.drawPath(path, paint);
        }
      }
      return;
    }
    if (kind == 'prism') {
      for (var i = 0; i < 8; i++) {
        final x = (i * size.width / 7 + 18 * math.sin(t * 1.5 + i)).clamp(0.0, size.width).toDouble();
        c.drawRect(Rect.fromLTWH(x, 0, unit * .036, size.height),
          Paint()..color = HSVColor.fromAHSV(.09, (i * 48 + t * 25) % 360, .75, 1).toColor()
            ..blendMode = BlendMode.screen);
      }
      return;
    }
    if (kind == 'neon') {
      for (var i = 0; i < 9; i++) {
        final a = math.sin(t * 1.6 + i * .9);
        final x = (i * .16 + a * .08) * size.width;
        final p = Paint()..color = _color(name, i, .38 + .20 * math.sin(t * 3 + i).abs())
            ..strokeWidth = unit * (.006 + (i % 3) * .003);
        c.drawLine(Offset(x, 0), Offset(x - unit * .15, size.height), p);
        _glow(c, Offset(x, size.height * .48), unit * .018, p.color);
      }
      return;
    }
    if (kind == 'watercolor' || kind == 'magic') {
      final amount = kind == 'watercolor' ? 9 : 18;
      for (var i = 0; i < amount; i++) {
        final a = _rand(seed + i * 41) * 2 * math.pi;
        final phase = t * (.17 + i % 4 * .09);
        final p = Offset(size.width * (.5 + .42 * math.cos(a + phase)),
            size.height * (.5 + .42 * math.sin(a + phase)));
        final r = unit * (kind == 'watercolor' ? .17 : .065);
        _glow(c, p, r, _color(name, i, kind == 'watercolor' ? .24 : .65));
        if (kind == 'magic') _star(c, p, r * .25,
            Paint()..color = _color(name, i, .9), tips: 4);
      }
      return;
    }
    final intensity = name.contains('Storm') ? 105 : name.contains('Powder') ? 135 :
        name.contains('Rain') || name.contains('Shower') ? 80 :
        name.contains('Glitter') ? 100 : 50;
    for (var i = 0; i < intensity; i++) {
      final x0 = _rand(seed + i * 31 + 1);
      final y0 = _rand(seed + i * 43 + 2);
      final sizeVar = _rand(seed + i * 53 + 3);
      final speed = .05 + .095 * _rand(seed + i * 29 + 4);
      final drift = math.sin(t * (.4 + sizeVar) + i * .8) * .024;
      double x = (x0 + drift) * size.width;
      double y = (y0 + t * speed) % 1.18 * size.height - size.height * .09;
      if (kind == 'hearts' && name == 'Hearts trail') {
        x = size.width * (.46 + .25 * math.sin(t * 1.5 + i * .18));
        y = (1.02 - ((t * .36 + i * .075) % 1.14)) * size.height;
      } else if (kind == 'hearts' || kind == 'firefly' || kind == 'bokeh') {
        y = (y0 - t * speed + 3) % 1.18 * size.height - size.height * .09;
      }
      final p = Offset(x, y);
      final radius = unit * (.005 + sizeVar * .023) *
          (name == 'Super Love B...' ? 1.75 : name == 'Mini stars 3' ? .5 : 1.0);
      final flicker = .55 + .45 * math.sin(t * (2 + sizeVar * 5) + i).abs();
      final color = _color(name, i, .48 + flicker * .43);
      final paint = Paint()..color = color;
      switch (kind) {
        case 'hearts':
          if (name == 'Heartbeat' || name == 'Beating Heart') {
            final pulse = 1 + .34 * math.pow(math.sin(t * (name == 'Heartbeat' ? 7.0 : 4.0)), 4).toDouble();
            if (i > 12) continue;
            _heart(c, p, radius * pulse * 2, paint);
          } else {
            if (name.contains('Burning')) _glow(c, p, radius * 2, const Color(0xAAFF531D));
            _heart(c, p, radius * (name == 'Heart' ? 1.6 : 1), paint);
          }
          break;
        case 'snow':
          if (i.isEven) _snowflake(c, p, radius, paint);
          else c.drawCircle(p, radius * .46, paint);
          break;
        case 'petal':
          if (name == 'Flowers' || name == 'Spring Bloss...') {
            _flower(c, p, radius * 1.45, paint, 5);
          } else {
            c.save(); c.translate(p.dx, p.dy); c.rotate(t + i);
            c.drawOval(Rect.fromCenter(center: Offset.zero,
                width: radius * 1.8, height: radius * 2.8), paint);
            c.restore();
          }
          break;
        case 'butterfly':
          _butterfly(c, p, radius * 1.7, paint, math.sin(t * 11 + i));
          break;
        case 'confetti':
          c.save(); c.translate(p.dx, p.dy); c.rotate(t * 1.8 + i);
          c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero,
              width: radius * 1.6, height: radius * .7), const Radius.circular(1)), paint);
          c.restore();
          break;
        case 'bokeh':
          _glow(c, p, radius * 1.5, color);
          c.drawCircle(p, radius, Paint()..color = color.withValues(alpha: .19));
          break;
        case 'firefly':
          _glow(c, p, radius * 1.5, color);
          c.drawCircle(p, radius * .23, Paint()..color = Colors.white);
          break;
        case 'ornament':
          _glow(c, p, radius, color);
          c.drawCircle(p, radius, paint);
          c.drawLine(p + Offset(0, -radius), p + Offset(0, -radius * 1.6),
              Paint()..color = Colors.white70..strokeWidth = 1);
          break;
        case 'candle':
          if (i > 24) continue;
          c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: p + Offset(0, radius),
              width: radius * .5, height: radius * 2), Radius.circular(radius * .1)),
              Paint()..color = const Color(0xDDFFF1C3));
          _glow(c, p - Offset(0, radius * .5), radius * 1.6, const Color(0xBBFFB827));
          break;
        case 'meteor':
          final tail = Offset(radius * (6 + sizeVar * 11), -radius * (6 + sizeVar * 11));
          c.drawLine(p - tail, p, Paint()..color = color..strokeWidth = radius * .2);
          _glow(c, p, radius * .9, color);
          break;
        case 'ribbon':
          final path = Path()..moveTo(p.dx, p.dy);
          for (var k = 1; k <= 12; k++) {
            path.lineTo(p.dx + math.sin(t * 3 + k * .65 + i) * radius * 2,
                p.dy + k * radius * .65);
          }
          c.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke
              ..strokeWidth = math.max(.7, radius * .2));
          break;
        default:
          if (name == 'Gold Powder') {
            c.drawCircle(p, math.max(.7, radius * .30), paint);
          } else if (name == 'Shards of Lig...' || name == 'Color Diamo...') {
            _star(c, p, radius * 1.5, paint, tips: name == 'Color Diamo...' ? 4 : 3);
          } else {
            if (name.contains('Radiating') || name == 'Gleam' || name == 'Sparkle') _glow(c, p, radius * 1.35, color);
            _star(c, p, radius, paint, tips: name.contains('Xmas') ? 6 : 4,
              inside: name.contains('Twinkle') ? .24 : .45);
          }
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) => draw(canvas, size, effects, seconds);

  @override
  bool shouldRepaint(covariant TiniVibeEffectsPainter old) =>
      old.seconds != seconds || !identical(old.effects, effects);
}
