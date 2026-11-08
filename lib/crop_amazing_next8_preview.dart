import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Flutter preview for the second eight Amazing effects (40016.mp4).
/// Keeps the source-video widget live; temporal phases are local to the
/// selected effect interval. All drawing is clipped to the video viewport.
class TiniAmazingNextEightPreview {
  static const category = 'مذهلة';
  static const supported = <String>{
    'Negative Wa...', 'American Co...', 'Reverse',
    'Negative Spli...', 'Comic Book ...', 'Surveillance ...',
    'Light Leaks', 'Color Negati...', 'خلل',
  };

  static double thumbnailSeconds(String name) => switch (name) {
    'Negative Wa...' => .75,
    'American Co...' => .92,
    'Reverse' => .75,
    'Negative Spli...' => .67,
    'Comic Book ...' => .85,
    'Surveillance ...' => .68,
    'Light Leaks' => .72,
    'خلل' => .53,
    'Color Negati...' => .85,
    _ => .75,
  };

  static const _inverse = <double>[
    -1, 0, 0, 0, 255, 0, -1, 0, 0, 255,
    0, 0, -1, 0, 255, 0, 0, 0, 1, 0,
  ];

  static Widget apply({required String name, required Widget child,
      required double elapsed, required double start, required double end}) {
    if (!supported.contains(name)) return child;
    final time = math.max(0.0, elapsed - start);
    final duration = math.max(.10, end - start);
    if (name == 'خلل') {
      // Distinct digital tearing: displaced portions of the actual live video,
      // not a static colour overlay. Keep the centre frame underneath.
      final tick = (time * 19).floor();
      final jitter = (math.sin(tick * 13.31) * 18).roundToDouble();
      return ClipRect(child: Stack(fit: StackFit.passthrough, children: [
        child,
        ClipPath(clipper: _AmazingGlitchBands(time: time, alternate: false),
          child: Transform.translate(offset: Offset(13 + jitter, 0),
            child: ColorFiltered(colorFilter: const ColorFilter.matrix([
              1.22, 0, 0, 0, 45, 0, .62, 0, 0, -17,
              0, 0, .66, 0, -13, 0, 0, 0, 1, 0,
            ]), child: child))),
        ClipPath(clipper: _AmazingGlitchBands(time: time, alternate: true),
          child: Transform.translate(offset: Offset(-19 + jitter * .65, 0),
            child: ColorFiltered(colorFilter: const ColorFilter.matrix([
              .50, 0, 0, 0, -5, 0, 1.18, 0, 0, 22,
              0, 0, 1.20, 0, 40, 0, 0, 0, 1, 0,
            ]), child: child))),
        Positioned.fill(child: IgnorePointer(child: CustomPaint(
          painter: _AmazingGlitchPainter(time: time)))),
      ]));
    }
    if (name == 'Negative Wa...') {
      final crimson = ColorFiltered(
        colorFilter: const ColorFilter.mode(
          Color(0xBBE32A60), BlendMode.color), child: child);
      final negative = ColorFiltered(
        colorFilter: const ColorFilter.matrix(_inverse), child: child);
      return ClipRect(child: Stack(fit: StackFit.passthrough, children: [
        crimson,
        ClipPath(clipper: _AmazingNextClipper(name: name, time: time),
            child: negative),
        Positioned.fill(child: IgnorePointer(child: CustomPaint(
          painter: _AmazingNextPainter(name: name, time: time,
              duration: duration)))),
      ]));
    }
    if (name == 'Negative Spli...') {
      final negative = ColorFiltered(
          colorFilter: const ColorFilter.matrix(_inverse), child: child);
      final monochrome = ColorFiltered(colorFilter: const ColorFilter.matrix([
        .25,.50,.10,0,2, .20,.55,.10,0,18, .08,.28,.07,0,3,
        0,0,0,1,0,
      ]), child: child);
      return ClipRect(child: Stack(fit: StackFit.passthrough, children: [
        child,
        ClipPath(clipper: _AmazingNextClipper(name: name,
          time: time, part: 0), child: negative),
        ClipPath(clipper: _AmazingNextClipper(name: name,
          time: time, part: 1), child: monochrome),
        Positioned.fill(child: IgnorePointer(child: CustomPaint(
          painter: _AmazingNextPainter(name: name, time: time,
              duration: duration)))),
      ]));
    }
    if (name == 'Reverse') {
      return ClipRect(child: Stack(fit: StackFit.passthrough, children: [
        ColorFiltered(colorFilter: const ColorFilter.matrix([
          .055,.10,.025,0,179, .055,.10,.025,0,179,
          .055,.10,.025,0,179, 0,0,0,1,0,
        ]), child: child),
      ]));
    }
    Widget picture = child;
    if (name == 'Surveillance ...') {
      picture = ColorFiltered(colorFilter: const ColorFilter.matrix([
        .68,.06,.07,0,2, .08,.74,.06,0,5, .10,.09,.88,0,17,
        0,0,0,1,0,
      ]), child: child);
    } else if (name == 'American Co...') {
      picture = ColorFiltered(colorFilter: const ColorFilter.matrix([
        1.25,0,0,0,-18, 0,1.18,0,0,-10, 0,0,1.12,0,-5,
        0,0,0,1,0,
      ]), child: child);
    } else if (name == 'Comic Book ...') {
      picture = ColorFiltered(colorFilter: const ColorFilter.matrix([
        1.52,-.13,-.12,0,-15, -.10,1.50,-.12,0,-12,
        -.12,-.12,1.55,0,-11, 0,0,0,1,0,
      ]), child: child);
    } else if (name == 'Color Negati...') {
      final phase = (time / duration) % 1.0;
      if (phase < .87) {
        final palette = ((phase * 5.0).floor()) % 4;
        final matrices = <List<double>>[
          [-1,0,0,0,255, 0,-.75,.20,0,212, 0,.10,-1.4,0,220, 0,0,0,1,0],
          [0,-1,.2,0,251, -.9,.1,.12,0,210, .15,-1.0,.10,0,220, 0,0,0,1,0],
          [-.35,-.7,.2,0,230, .3,-1.1,.2,0,220, -.7,.08,.2,0,205, 0,0,0,1,0],
          [.1,-.95,.02,0,240, -.8,.2,.10,0,188, -.10,-.72,.10,0,235, 0,0,0,1,0],
        ];
        picture = ColorFiltered(
          colorFilter: ColorFilter.matrix(matrices[palette]), child: child);
      }
    }
    return ClipRect(child: Stack(fit: StackFit.passthrough, children: [
      picture,
      Positioned.fill(child: IgnorePointer(child: CustomPaint(
        painter: _AmazingNextPainter(name: name, time: time,
          duration: duration)))),
    ]));
  }
}

class _AmazingNextClipper extends CustomClipper<Path> {
  final String name;
  final double time;
  final int part;
  const _AmazingNextClipper({required this.name, required this.time,
    this.part=0});
  @override
  Path getClip(Size size) {
    final w=size.width, h=size.height;
    final path=Path();
    if (name == 'Negative Wa...') {
      for (final rect in <Rect>[
        Rect.fromCenter(center:Offset(w*(.30+.16*math.sin(4*time)),
          h*(.27+.08*math.cos(3*time))), width:w*.19,height:h*.18),
        Rect.fromCenter(center:Offset(w*(.66-.20*math.sin(3*time+.5)),
          h*(.58+.15*math.sin(2*time))), width:w*.15,height:h*.13),
        Rect.fromCenter(center:Offset(w*(.41+.12*math.cos(5*time)),
          h*(.79-.11*math.sin(4*time))), width:w*.09,height:h*.09),
      ]) { path.addRect(rect); }
    } else if (name == 'Negative Spli...') {
      final x=(.47+.24*math.sin(4*time)).clamp(.10,.90)*w;
      final y=(.39+.23*math.cos(3.3*time)).clamp(.08,.92)*h;
      path.addRect(part == 0 ? Rect.fromLTWH(0,0,x,y) :
          Rect.fromLTWH(x,y,w-x,h-y));
    }
    return path;
  }
  @override
  bool shouldReclip(covariant _AmazingNextClipper oldClipper) =>
      oldClipper.time != time || oldClipper.name != name || oldClipper.part != part;
}

class _AmazingNextPainter extends CustomPainter {
  final String name;
  final double time;
  final double duration;
  const _AmazingNextPainter({required this.name, required this.time,
    required this.duration});

  void _label(Canvas canvas, String word, Offset at, double size, Color tint,
      {FontWeight weight = FontWeight.w600}) {
    final text=TextPainter(text:TextSpan(text:word,
        style:TextStyle(fontSize:size,color:tint,fontWeight:weight,
          fontFamily:'monospace')),
      textDirection:TextDirection.ltr)..layout();
    text.paint(canvas,at);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w=size.width, h=size.height;
    final unit=math.min(w,h);
    if (w <= 0 || h <= 0) return;
    switch (name) {
      case 'Negative Wa...': {
        final points=<Offset>[
          Offset(w*(.30+.16*math.sin(4*time)),h*(.27+.08*math.cos(3*time))),
          Offset(w*(.66-.20*math.sin(3*time+.5)),h*(.58+.15*math.sin(2*time))),
          Offset(w*(.41+.12*math.cos(5*time)),h*(.79-.11*math.sin(4*time))),
        ];
        for(final centre in points) {
          canvas.drawRect(Rect.fromCenter(center:centre,width:unit*.17,
            height:unit*.13),Paint()..color=const Color(0x55FFFFFF)
            ..style=PaintingStyle.stroke..strokeWidth=unit*.004);
        }
        break;
      }
      case 'American Co...': {
        // Off-axis comic-book borders, muted paper side panels and halftone.
        final left=Path()..moveTo(0,0)..lineTo(w*.11,h*.02)
          ..lineTo(w*.07,h*.96)..lineTo(0,h)..close();
        final right=Path()..moveTo(w,0)..lineTo(w*.91,h*.02)
          ..lineTo(w*.93,h*.96)..lineTo(w,h)..close();
        canvas.drawPath(left,Paint()..color=const Color(0xD7E2B58C));
        canvas.drawPath(right,Paint()..color=const Color(0xE087A2BA));
        final dot=Paint()..color=const Color(0x4C2A2223);
        for(var row=0;row<70;row++) {
          final y=(row+.5)*h/70;
          for(var col=0;col<3;col++) {
            final x=(col+.5)*w*.026;
            canvas.drawCircle(Offset(x,y),unit*.0022,dot);
            canvas.drawCircle(Offset(w-x,y),unit*.0022,dot);
          }
        }
        canvas.drawPath(Path()..moveTo(w*.11,h*.015)
          ..lineTo(w*.91,h*.015)..lineTo(w*.93,h*.96)
          ..lineTo(w*.07,h*.96)..close(),
          Paint()..color=const Color(0xFF282127)..style=PaintingStyle.stroke
            ..strokeWidth=unit*.016..strokeJoin=StrokeJoin.bevel);
        canvas.drawLine(Offset(w*.005,h*.13),Offset(w*.105,h*.05),
          Paint()..color=Colors.white..strokeWidth=unit*.011);
        canvas.drawLine(Offset(w*.90,h*.13),Offset(w*.995,h*.04),
          Paint()..color=const Color(0xFF2A1F26)..strokeWidth=unit*.014);
        break;
      }
      case 'Negative Spli...': {
        final x=w*(.47+.24*math.sin(4*time));
        final y=h*(.39+.23*math.cos(3.3*time));
        canvas.drawLine(Offset(x,0),Offset(x,h),
          Paint()..color=const Color(0x33000000)..strokeWidth=unit*.004);
        canvas.drawLine(Offset(0,y),Offset(w,y),
          Paint()..color=const Color(0x33000000)..strokeWidth=unit*.004);
        break;
      }
      case 'Comic Book ...': {
        // Screen-space print texture is intentional. Per-subject black ink
        // edges are generated in FFmpeg export; Flutter has no CPU access
        // to an underlying video Texture without a separate shader/ML pass.
        final dot=Paint()..color=const Color(0x240E0B10);
        final stride=math.max(6.0,unit*.026);
        for(double y=stride/2; y<h; y+=stride) {
          for(double x=stride/2; x<w; x+=stride) {
            canvas.drawCircle(Offset(x,y),stride*.105,dot);
          }
        }
        break;
      }
      case 'Surveillance ...': {
        canvas.drawRect(Offset.zero & size,Paint()..color=const Color(0x28524F98));
        final line=Paint()..color=const Color(0x20E4E7FF)..strokeWidth=1;
        for(double y=(time*22)%7; y<h; y+=7) {
          canvas.drawLine(Offset(0,y),Offset(w,y),line);
        }
        final margin=unit*.04;
        canvas.drawRect(Rect.fromLTWH(margin,margin,w-2*margin,h-2*margin),
          Paint()..color=const Color(0xB0131431)
            ..style=PaintingStyle.stroke..strokeWidth=unit*.008);
        final font=math.max(10.0,unit*.039);
        _label(canvas,'CAM 01',Offset(margin+8,margin+8),font,Colors.white70);
        _label(canvas,'REC',Offset(w-margin-font*3.1,margin+8),font,Colors.white);
        canvas.drawCircle(Offset(w-margin-font*3.6,margin+font*1.12),
          font*.19,Paint()..color=const Color(0xFFFF4040));
        final total=time.floor(), hh=total~/3600,
          mm=(total%3600)~/60, ss=total%60;
        final stamp='${hh.toString().padLeft(2,'0')}:'
          '${mm.toString().padLeft(2,'0')}:'
          '${ss.toString().padLeft(2,'0')}';
        _label(canvas,stamp,Offset(margin+8,h-margin-font-8),font,
          const Color(0xFFE2E8FF));
        break;
      }
      case 'Light Leaks': {
        // Three differently moving optical light leaks, a sweeping streak,
        // and a distinct high-energy flare. The source video stays visible.
        final phase = time * 2.4;
        final pulse = .80 + .20 * math.sin(time * 5.7);
        final hotX = w * (.12 + .34 * math.sin(time * 1.45));
        final hotY = h * (.34 + .25 * math.cos(time * 1.80));
        canvas.drawRect(Offset.zero & size, Paint()
          ..blendMode = BlendMode.screen
          ..shader = ui.Gradient.radial(Offset(hotX, hotY), w * .94,
            [const Color(0xF9FFCE69).withValues(alpha: .95 * pulse),
             const Color(0xD7FF663B), const Color(0x88E42A62),
             Colors.transparent], [0, .22, .50, 1]));
        canvas.drawRect(Offset.zero & size, Paint()
          ..blendMode = BlendMode.screen
          ..shader = ui.Gradient.radial(
            Offset(w * (.91 - .34 * math.sin(time * 1.7 + .6)),
              h * (.76 - .16 * math.cos(time * 1.5))), w * .77,
            [const Color(0xD1B8F9FF), const Color(0xB738A8FF),
              const Color(0x6B7045FF), Colors.transparent],
            [0, .24, .57, 1]));
        // A luminous film-burn stripe traverses the full frame diagonally.
        final sweep = w * (-.43 + ((time * .62) % 1.8));
        final slash = Path()
          ..moveTo(sweep - w * .32, -h * .2)
          ..lineTo(sweep + w * .15, -h * .2)
          ..lineTo(sweep - w * .22, h * 1.2)
          ..lineTo(sweep - w * .69, h * 1.2)
          ..close();
        canvas.drawPath(slash, Paint()..blendMode = BlendMode.screen
          ..shader = ui.Gradient.linear(
            Offset(sweep - w * .68, h * .50),
            Offset(sweep + w * .14, h * .50),
            [Colors.transparent, const Color(0xAFFF622D),
              const Color(0xDFFFF1AD), const Color(0xB7FF8A4A),
              Colors.transparent], [0, .27, .49, .70, 1]));
        break;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AmazingNextPainter oldDelegate) =>
    oldDelegate.name != name || oldDelegate.time != time ||
    oldDelegate.duration != duration;
}


/// Several time-varying horizontal tears in the current video texture.
class _AmazingGlitchBands extends CustomClipper<Path> {
  final double time;
  final bool alternate;
  const _AmazingGlitchBands({required this.time, required this.alternate});
  @override
  Path getClip(Size size) {
    final path = Path();
    final tick = (time * 13).floor();
    for (var i = 0; i < 6; i++) {
      final group = i.isOdd == alternate;
      if (!group) continue;
      final y = (.07 + .15 * i + .065 * math.sin(tick * 1.27 + i * 3.7))
          .clamp(0.0, .97) * size.height;
      final thick = size.height * (.028 + .037 *
          (.5 + .5 * math.sin(tick * 4.1 + i * 2.3)));
      final x = size.width * (.04 * math.sin(tick * 2.1 + i));
      path.addRect(Rect.fromLTWH(x, y, size.width * .98, thick));
    }
    return path;
  }
  @override
  bool shouldReclip(covariant _AmazingGlitchBands oldClipper) =>
      oldClipper.time != time || oldClipper.alternate != alternate;
}

class _AmazingGlitchPainter extends CustomPainter {
  final double time;
  const _AmazingGlitchPainter({required this.time});
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width, h = size.height;
    final tick = (time * 23).floor();
    final unit = math.min(w, h);
    for (var i = 0; i < 18; i++) {
      final seed = math.sin(i * 17.13 + tick * 4.79);
      final y = h * ((i * .071 + seed * .037) % 1);
      final x = w * ((i * .179 + seed * .28).abs() % .82);
      final len = w * (.07 + .19 * (.5 + .5 *
          math.sin(i * 2.8 + tick * 3.11)));
      canvas.drawRect(Rect.fromLTWH(x, y, len,
          math.max(1.0, unit * (i % 5 == 0 ? .015 : .004))),
        Paint()..color = i.isOdd ? const Color(0xD3FFFFFF)
            : const Color(0xBB08030E));
    }
    final shift = .38 + .34 * math.sin(tick * 1.31);
    canvas.drawRect(Rect.fromLTWH(0, h * shift, w, h * .009),
      Paint()..color = const Color(0xCC38EDFC));
  }
  @override
  bool shouldRepaint(covariant _AmazingGlitchPainter oldDelegate) =>
      oldDelegate.time != time;
}
