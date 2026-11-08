import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// The eight reference animations from 39976.mp4. Each has its own geometry,
/// timeline and paint path. This is a foreground compositor, never a substitute
/// for the source-video frame or the editor's other effect categories.
class TiniAmazingEffectsPreview {
  static const category = 'مذهلة';
  static const supported = <String>{
    'H2L Text', '2026 Loading', 'Disco Count', 'Love Window',
    'Negative Gra...', 'Fire-Hot', 'Lyric Cut', 'Octopus End',
  };

  static double thumbnailSeconds(String name) => switch (name) {
    'H2L Text' => .72,
    '2026 Loading' => 1.12,
    'Disco Count' => .24,
    'Love Window' => 1.92,
    'Negative Gra...' => .66,
    'Fire-Hot' => .92,
    'Lyric Cut' => .81,
    'Octopus End' => .54,
    _ => .70,
  };

  static Widget apply({required String name, required Widget child,
      required double elapsed, required double start, required double end}) {
    if (!supported.contains(name)) return child;
    final time = math.max(0.0, elapsed - start);
    final duration = math.max(.10, end - start);
    if (name == 'Octopus End') {
      // Fit at least one complete close/hold/reopen motion into the default
      // two-second effect span; longer spans repeat at the natural pace.
      final motionTime = time * (_octopusCycle /
          math.min(_octopusCycle, duration));
      // Keep the moving source visible through a real clip path. Painting a
      // transparent hole above a video texture is unreliable on Android.
      return ClipRect(child: Stack(fit: StackFit.passthrough, children: [
        Positioned.fill(child: IgnorePointer(child: CustomPaint(
          painter: _OctopusBackdropPainter(time: motionTime),
        ))),
        ClipPath(clipper: _OctopusWindowClipper(time: motionTime), child: child),
        Positioned.fill(child: IgnorePointer(child: CustomPaint(
          painter: _OctopusRimPainter(time: motionTime),
        ))),
      ]));
    }
    Widget image = child;
    if (name == 'Negative Gra...') {
      final invert = ColorFiltered(colorFilter: const ColorFilter.matrix([
        -1, 0, 0, 0, 255, 0, -1, 0, 0, 255,
        0, 0, -1, 0, 255, 0, 0, 0, 1, 0,
      ]), child: child);
      // Original and negative fragments alternate sharply, not a colour wash.
      image = Stack(fit: StackFit.passthrough, children: [
        invert,
        ClipPath(clipper: _GlitchClip(time), child: child),
      ]);
    } else if (name == 'Lyric Cut') {
      image = ColorFiltered(colorFilter: const ColorFilter.matrix([
        .25, 0, 0, 0, 0, 0, .25, 0, 0, 0,
        0, 0, .37, 0, 0, 0, 0, 0, 1, 0,
      ]), child: child);
    }
    return ClipRect(child: Stack(fit: StackFit.passthrough, children: [
      image,
      Positioned.fill(child: IgnorePointer(child: CustomPaint(
        painter: _AmazingPainter(name: name, time: time, duration: duration),
      ))),
    ]));
  }
}

// The opening is an animated physical aperture, not a stationary circle.
// One 3.36-second cycle: the tentacle closes, holds, withdraws and repeats.
// All geometry uses physical pixels (width as the unit) so portraits retain
// a nearly circular window instead of stretching to an oval.
const double _octopusCycle = 3.36;
const double _octopusClosedRadius = .365;

double _octopusMotion(double seconds) {
  final t = seconds % _octopusCycle;
  if (t < .88) {
    return .5 - .5 * math.cos(math.pi * t / .88);
  }
  if (t < 2.55) return 1.0;
  if (t < 3.16) {
    return .5 + .5 * math.cos(math.pi * (t - 2.55) / .61);
  }
  return 0.0;
}

double _octopusRadius(Size size, double time) {
  final openRadius = math.sqrt(.505 * .505 +
      math.pow(.52 * size.height / size.width, 2)) + .19;
  return _octopusClosedRadius +
      (openRadius - _octopusClosedRadius) * (1 - _octopusMotion(time));
}

Offset _octopusCentre(Size size) =>
    Offset(size.width * .505, size.height * .48);

double _octopusWobble(double a, double time) =>
    1 + .027 * math.sin(4 * a + time * 1.25) +
        .014 * math.sin(7 * a - time * .9);

Path _octopusOpening(Size size, double time) {
  final path = Path();
  if (size.isEmpty) return path;
  final centre = _octopusCentre(size);
  final radius = _octopusRadius(size, time) * size.width;
  const samples = 128;
  for (var i = 0; i <= samples; i++) {
    final a = i * 2 * math.pi / samples;
    final r = radius * _octopusWobble(a, time);
    final p = centre + Offset(math.cos(a) * r, math.sin(a) * r);
    if (i == 0) { path.moveTo(p.dx, p.dy); }
    else { path.lineTo(p.dx, p.dy); }
  }
  return path..close();
}

class _OctopusWindowClipper extends CustomClipper<Path> {
  final double time;
  const _OctopusWindowClipper({required this.time});
  @override
  Path getClip(Size size) => _octopusOpening(size, time);
  @override
  bool shouldReclip(covariant _OctopusWindowClipper oldClipper) =>
      time != oldClipper.time;
}

// Individually modelled suction cups. They move with the same deforming arm
// geometry as the aperture, not as a static bitmap above the video.
void _octopusSucker(Canvas canvas, Offset c, double r, double time,
    {bool highlighted = false}) {
  if (r <= 0) return;
  if (highlighted) {
    canvas.drawCircle(c + Offset(r * .10, r * .16), r * 1.16,
        Paint()..color = const Color(0x7A12052F)
          ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, r * .20));
  }
  canvas.drawCircle(c, r * 1.09, Paint()..color = const Color(0xFF381253));
  canvas.drawCircle(c, r * .97, Paint()..color = const Color(0xFF8542A7));
  canvas.drawCircle(c, r * .84, Paint()
    ..shader = ui.Gradient.radial(c - Offset(r * .12, r * .17), r * 1.12,
      [const Color(0xFFFFCA83), const Color(0xFFF48660),
       const Color(0xFFBE4779), const Color(0xFF54216F)],
      [0,.40,.77,1]));
  canvas.drawCircle(c, r * .50, Paint()..color = const Color(0xFFED906E));
  canvas.drawCircle(c + Offset(r*.045,r*.045), r * .37,
      Paint()..color = const Color(0xFF321247));
  if (highlighted) {
    canvas.drawArc(Rect.fromCircle(center: c, radius: r*.80),
        math.pi*.92, math.pi*.8, false, Paint()
          ..color=const Color(0xB8FFDAA3)..style=PaintingStyle.stroke
          ..strokeWidth=r*.10..strokeCap=StrokeCap.round);
  }
}

// Rings are attached to the tentacle. At closure, several rings enter the
// picture; as the tentacle withdraws, the whole arrangement leaves the frame.
Offset _octopusCupPosition(Size size, double time, int ring, int index,
    int count) {
  final angle = 2 * math.pi * index / count +
      (ring.isOdd ? .14 : 0) + .033 * math.sin(time * 1.8 + ring);
  final radius = (_octopusRadius(size, time) + .055 + ring * .26) *
      size.width * _octopusWobble(angle, time);
  return _octopusCentre(size) +
      Offset(math.cos(angle) * radius, math.sin(angle) * radius);
}

class _OctopusBackdropPainter extends CustomPainter {
  final double time;
  const _OctopusBackdropPainter({required this.time});
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w=size.width, h=size.height;
    canvas.drawRect(Offset.zero & size, Paint()
      ..shader = ui.Gradient.radial(Offset(w*.42,h*.40),h*.73,
        [const Color(0xFF793694),const Color(0xFF5A247C),
         const Color(0xFF43176F),const Color(0xFF240C40)],
        [0,.39,.77,1]));
    // Contoured folds travel together with the aperture.
    final centre=_octopusCentre(size);
    final baseRadius=_octopusRadius(size,time)*w;
    for (var band=0;band<4;band++) {
      final outline=Path();
      for (var i=0;i<=108;i++) {
        final angle=2*math.pi*i/108;
        final r=baseRadius+w*(.035+band*.17);
        final p=centre + Offset(math.cos(angle),math.sin(angle))*
            (r*_octopusWobble(angle,time));
        if (i==0) { outline.moveTo(p.dx,p.dy); }
        else { outline.lineTo(p.dx,p.dy); }
      }
      outline.close();
      canvas.drawPath(outline,Paint()
        ..color=(band.isEven ? const Color(0x3E29104D)
            : const Color(0x317B42A6))
        ..style=PaintingStyle.stroke..strokeWidth=w*.085);
    }
    // Concentric, alternating rows of cups. Culling offscreen rows saves
    // raster time during the wide-open part of the animation.
    for (var ring=1;ring<=4;ring++) {
      final count=8+ring*4;
      final radius=w*(.041+.002*(ring%3));
      for (var j=0;j<count;j++) {
        final c=_octopusCupPosition(size,time,ring,j,count);
        if (c.dx < -radius*1.2 || c.dx > w+radius*1.2 ||
            c.dy < -radius*1.2 || c.dy > h+radius*1.2) continue;
        _octopusSucker(canvas,c,radius,time);
      }
    }
  }
  @override
  bool shouldRepaint(covariant _OctopusBackdropPainter oldDelegate) =>
      oldDelegate.time != time;
}

class _OctopusRimPainter extends CustomPainter {
  final double time;
  const _OctopusRimPainter({required this.time});
  @override
  void paint(Canvas canvas,Size size) {
    if (size.isEmpty) return;
    final w=size.width, h=size.height;
    final opening=_octopusOpening(size,time);
    canvas.drawPath(opening,Paint()..color=const Color(0xFF391357)
      ..style=PaintingStyle.stroke..strokeWidth=w*.095
      ..strokeJoin=StrokeJoin.round);
    canvas.drawPath(opening,Paint()..color=const Color(0xFF8C48AA)
      ..style=PaintingStyle.stroke..strokeWidth=w*.029);
    const count=18;
    for (var j=0;j<count;j++) {
      final c=_octopusCupPosition(size,time,0,j,count);
      final radius=w*(.034+.004*(j%3));
      if (c.dx < -radius*1.2 || c.dx > w+radius*1.2 ||
          c.dy < -radius*1.2 || c.dy > h+radius*1.2) continue;
      _octopusSucker(canvas,c,radius,time,highlighted:true);
    }
  }
  @override
  bool shouldRepaint(covariant _OctopusRimPainter oldDelegate) =>
      oldDelegate.time != time;
}

class _GlitchClip extends CustomClipper<Path> {
  final double time;
  const _GlitchClip(this.time);
  @override
  Path getClip(Size size) {
    final path = Path();
    final tick = (time * 11).floor();
    for (var i = 0; i < 15; i++) {
      final y = ((i * 97 + tick * 31) % 103) / 103 * size.height;
      final thickness = (.008 + (i % 4) * .006) * size.height;
      final x = ((i * 23 + tick * 7) % 50) / 100 * size.width;
      path.addRect(Rect.fromLTWH(x, y, size.width * .8, thickness));
    }
    return path;
  }
  @override
  bool shouldReclip(covariant _GlitchClip oldClipper) => oldClipper.time != time;
}

class _AmazingPainter extends CustomPainter {
  final String name;
  final double time;
  final double duration;
  const _AmazingPainter({required this.name, required this.time,
      required this.duration});

  double get phase => (time / duration).clamp(0.0, 1.0).toDouble();
  static double _wave(double x) => math.sin(x);

  void _text(Canvas canvas, String text, Offset at, double size, Color color,
      {FontWeight weight = FontWeight.w900, double? width, bool italic = false,
      double spacing = -.5, Paint? foreground}) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: TextStyle(
        fontSize: size, fontWeight: weight,
        letterSpacing: spacing, fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        color: foreground == null ? color : null,
        foreground: foreground,
        height: 1.0,
      )), textDirection: TextDirection.ltr, maxLines: 1,
    )..layout(maxWidth: width ?? double.infinity);
    painter.paint(canvas, at);
    painter.dispose();
  }

  // The writing is five separate finger gestures: L, o, v, e, underline.
  // Time shares are mirrored by TiniAmazingEffectsExport so both stages agree.
  static const _loveStrokes = <List<Offset>>[
    [
      Offset(0.345, 0.267),
      Offset(0.323, 0.249),
      Offset(0.294, 0.249),
      Offset(0.264, 0.272),
      Offset(0.246, 0.311),
      Offset(0.226, 0.362),
      Offset(0.201, 0.429),
      Offset(0.217, 0.444),
      Offset(0.254, 0.448),
      Offset(0.298, 0.436),
      Offset(0.347, 0.410),
      Offset(0.367, 0.394),
    ],
    [
      Offset(0.397, 0.388),
      Offset(0.419, 0.366),
      Offset(0.456, 0.365),
      Offset(0.484, 0.388),
      Offset(0.482, 0.410),
      Offset(0.462, 0.430),
      Offset(0.434, 0.433),
      Offset(0.412, 0.416),
      Offset(0.413, 0.394),
      Offset(0.442, 0.371),
      Offset(0.483, 0.383),
    ],
    [
      Offset(0.490, 0.374),
      Offset(0.507, 0.402),
      Offset(0.528, 0.433),
      Offset(0.552, 0.406),
      Offset(0.581, 0.361),
    ],
    [
      Offset(0.601, 0.403),
      Offset(0.633, 0.385),
      Offset(0.676, 0.364),
      Offset(0.698, 0.373),
      Offset(0.683, 0.394),
      Offset(0.640, 0.408),
      Offset(0.652, 0.426),
      Offset(0.694, 0.429),
      Offset(0.730, 0.414),
      Offset(0.758, 0.392),
    ],
    [
      Offset(0.205, 0.467),
      Offset(0.262, 0.464),
      Offset(0.332, 0.465),
      Offset(0.409, 0.467),
      Offset(0.489, 0.471),
      Offset(0.568, 0.469),
      Offset(0.649, 0.464),
      Offset(0.729, 0.459),
      Offset(0.801, 0.454),
    ],
  ];

  static const _loveStages = <double>[0.0, .23, .42, .57, .82, 1.0];

  void _drawLoveWriting(Canvas canvas, Size size) {
    final pen = Paint()
      ..isAntiAlias = true
      ..blendMode = BlendMode.clear
      ..strokeWidth = size.width * .037
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (var gesture = 0; gesture < _loveStrokes.length; gesture++) {
      final start = _loveStages[gesture];
      final finish = _loveStages[gesture + 1];
      final portion = ((phase - start) / (finish - start))
          .clamp(0.0, 1.0).toDouble();
      if (portion <= 0) continue;
      final points = _loveStrokes[gesture];
      final path = Path()..moveTo(points.first.dx * size.width,
          points.first.dy * size.height);
      for (final pt in points.skip(1)) {
        path.lineTo(pt.dx * size.width, pt.dy * size.height);
      }
      for (final metric in path.computeMetrics()) {
        canvas.drawPath(metric.extractPath(0, metric.length * portion), pen);
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width, h = size.height;
    final minSide = math.min(w, h);
    Offset p(double x, double y) => Offset(w * x, h * y);
    final t = time;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    switch (name) {
      case 'H2L Text': {
        final beat = (t % 2.9);
        final font = w * .118;
        if (beat < 1.55) {
          _text(canvas, "DON'T", p(.12, .155), font, Colors.white);
          if (beat > .36) _text(canvas, 'GET ME', p(.045, .225), font, Colors.white);
          if (beat > .80) _text(canvas, 'GOING', p(.075, .295), font, Colors.white);
        } else {
          _text(canvas, 'I STILL', p(.145, .16), font, Colors.white);
        }
        break;
      }
      case '2026 Loading': {
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(w*.07, h*.085, w*.86, h*.032),
          Radius.circular(minSide*.026));
        canvas.drawRRect(rect, Paint()..color = const Color(0xE9000000));
        final barRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(w*.175, h*.090, w*.65, h*.022),
          Radius.circular(minSide*.02));
        canvas.drawRRect(barRect, Paint()..color = Colors.white);
        canvas.drawRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(w*.181, h*.094, w*.638, h*.014),
          Radius.circular(minSide*.02)), Paint()..color = Colors.black);
        final progress = (.03 + .94 * (t / math.max(1.1, duration)).clamp(0.0, 1.0))
            .clamp(0.0, 1.0).toDouble();
        canvas.drawRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(w*.183, h*.096, w*.634*progress, h*.010),
          Radius.circular(minSide*.02)), Paint()..color = Colors.white);
        _text(canvas, '2025', p(.082, .092), w*.035, Colors.white,
          weight: FontWeight.w600, spacing: -.3);
        _text(canvas, '2026', p(.838, .092), w*.035, Colors.white,
          weight: FontWeight.w600, spacing: -.3);
        _text(canvas, 'Loading...', p(.405, .123), w*.031,
          const Color(0xFF191919), weight: FontWeight.w600, spacing: 0);
        break;
      }
      case 'Disco Count': {
        // Six equally spaced numbers, in exact descending order: 10..5.
        // Use effect-local phase, not wall-clock seconds (export is identical).
        final n = 10 - math.min(5, (phase * 6).floor());
        final value = '$n';
        final font = w * .29;
        // Several offset metal/charcoal layers give the reference's raised
        // silver numeral without loading a 3D renderer into the video editor.
        _text(canvas, value, p(n == 10 ? .27 : .38, .095) + Offset(w*.017,h*.010),
          font, const Color(0xFF343434));
        final metal = Paint()..shader = ui.Gradient.linear(
          p(.2,.12), p(.8,.26),
          [const Color(0xFF4A515A), const Color(0xFFF6FAFF),
            const Color(0xFF7D868B), const Color(0xFFFFFFFF),
            const Color(0xFF555D68)], [0,.21,.47,.68,1]);
        _text(canvas, value, p(n == 10 ? .27 : .38, .095),
          font, Colors.white, foreground: metal);
        final glint = (.4 + .6*_wave(t * 13)).clamp(0.0, 1.0);
        canvas.drawCircle(p(.71,.105), minSide*.012*glint,
          Paint()..color = Colors.white.withValues(alpha: .88*glint)
            ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal,minSide*.022));
        break;
      }
      case 'Love Window': {
        // Frosted glass is drawn separately over the untouched moving video.
        // The finger clears each letter *as it is traced*, then underlines LOVE.
        canvas.saveLayer(Offset.zero & size, Paint());
        canvas.drawRect(Offset.zero & size,
          Paint()..color = const Color(0xDCE3E4E1));
        for (var i=0; i<80; i++) {
          final x = ((i*37+13)%101)/101.0;
          final y = ((i*43+7)%103)/103.0;
          final r = minSide * (.0018 + (i%5)*.0014);
          final offset = p(x, (y + t*.007*(1+i%3))%1.0);
          canvas.drawOval(Rect.fromCenter(center: offset, width: r*1.3,
            height: r*2.8), Paint()..color = const Color(0x665C6672));
          canvas.drawCircle(offset-Offset(r*.32,r*.45),r*.45,
            Paint()..color=const Color(0x88FFFFFF));
        }
        _drawLoveWriting(canvas, size);
        canvas.restore();
        break;
      }
      case 'Negative Gra...': {
        final tick=(t*12).floor();
        for(var i=0;i<17;i++) {
          final y=((i*47+tick*19)%113)/113.0;
          final x=((i*31+tick*13)%97)/97.0;
          final thick=(.003+(i%4)*.009)*h;
          final paint=Paint()..color = [const Color(0xA900E9F7),
            const Color(0xB919173D),const Color(0x88FC5FA8),
            const Color(0xC7F9EACD)][i%4];
          canvas.drawRect(Rect.fromLTWH(w*(x-.2),h*y,w*(.25+(i%5)*.12),thick),paint);
        }
        final scratch=Paint()..color=const Color(0x997EF1FF)
          ..strokeWidth=minSide*.003..style=PaintingStyle.stroke;
        for(var i=0;i<12;i++) {
          final path=Path()..moveTo(w*((i*37%99)/100),h*((i*19%90)/100));
          for(var j=0;j<4;j++) {
            path.relativeLineTo(w*(.04*_wave(i*3+j*2+t*9)),
              h*(.035*_wave(j*4+t*13+i)));
          }
          canvas.drawPath(path,scratch);
        }
        break;
      }
      case 'Fire-Hot': {
        canvas.saveLayer(Offset.zero & size, Paint());
        canvas.drawRect(Offset.zero & size,
          Paint()..color=const Color(0xFFF5F2E9));
        final centers=<Offset>[p(.48,.38),p(.34,.69),p(.66,.50)];
        for(var i=0;i<centers.length;i++) {
          final radius=w*(.04 + (.06+.21*phase)*(i==0 ? 1.1 : .7));
          final path=Path();
          for(var j=0;j<=70;j++) {
            final a=2*math.pi*j/70;
            final noise=1+.15*_wave(a*11+i*5+t*1.5)+.08*_wave(a*19+i*2);
            final point=centers[i]+Offset(radius*noise*math.cos(a),
              radius*noise*math.sin(a)*1.8);
            if(j==0) {path.moveTo(point.dx,point.dy);} else {path.lineTo(point.dx,point.dy);}
          }
          path.close();
          canvas.drawPath(path,Paint()..color=const Color(0xFF57463C)
            ..style=PaintingStyle.stroke..strokeWidth=minSide*.035);
          canvas.drawPath(path,Paint()..color=const Color(0xFFE97E22)
            ..style=PaintingStyle.stroke..strokeWidth=minSide*.016);
          canvas.drawPath(path,Paint()..color=const Color(0xFFFFD18B)
            ..style=PaintingStyle.stroke..strokeWidth=minSide*.008);
          canvas.drawPath(path,Paint()..blendMode=BlendMode.clear);
        }
        for(var i=0;i<32;i++) {
          final px=(i*37%99)/100.0, py=(i*41%93)/100.0;
          canvas.drawCircle(p(px,py),minSide*(.002+(i%4)*.002),
            Paint()..color=const Color(0x443D2A19));
        }
        canvas.restore();
        break;
      }
      case 'Lyric Cut': {
        const lyric=['LIFE', 'IS', 'GREAT', 'JUST', 'GOTTA'];
        final index=((t*2.2).floor())%lyric.length;
        final current=lyric[index];
        final font=w*(current.length>4 ? .15 : .20);
        final tint=[const Color(0xFFFFFFFF),const Color(0xFFFFD945),
          const Color(0xFF56FAD8),const Color(0xFFFFFFFF),
          const Color(0xFFFF79ED)][index];
        canvas.drawRect(Offset.zero & size, Paint()..color=const Color(0x880A051C));
        canvas.drawOval(Rect.fromCenter(center:p(.5,.55),width:w*.84,height:h*.23),
          Paint()..color=tint.withValues(alpha:.25)
            ..maskFilter=ui.MaskFilter.blur(ui.BlurStyle.normal,minSide*.18));
        _text(canvas,current,p(.5,.54)-Offset(font*current.length*.30,0),
          font,tint,spacing:-font*.045);
        final scanY=h*(.53+.015*_wave(t*9));
        canvas.drawLine(Offset(w*.16,scanY),Offset(w*.84,scanY),
          Paint()..color=const Color(0xAAF7F4FD)..strokeWidth=minSide*.004
            ..blendMode=BlendMode.screen);
        break;
      }
      case 'Octopus End': {
        // Drawn as dedicated clipped-video composition in apply().
        break;
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AmazingPainter oldDelegate) =>
    oldDelegate.name != name || oldDelegate.time != time ||
    oldDelegate.duration != duration;
}
