import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Third Amazing reference batch (40053.mp4). The ten treatments are deliberately
/// independent. The camera/subject/background replacement in Quick Speed is
/// approximated until a person-mask is available to the general effects editor.
class TiniAmazingTenPreview {
  static const category = 'مذهلة';
  static const supported = <String>{
    'Quick Speed', 'Energy', 'Split Apart', 'Question Ma...', 'سنة جديدة',
    "Something's ...", 'Scanning lig...', 'Shockwave', 'Moon Off', 'Illusion',
  };

  static double thumbnailSeconds(String name) => switch (name) {
    'Quick Speed' => .64,
    'Energy' => .70,
    'Split Apart' => 1.14,
    'Question Ma...' => .82,
    'سنة جديدة' => .81,
    "Something's ..." => 1.32,
    'Scanning lig...' => 1.06,
    'Shockwave' => .30,
    'Moon Off' => .92,
    'Illusion' => 1.18,
    _ => .75,
  };

  static Widget apply({required String name, required Widget child,
    required double elapsed, required double start, required double end}) {
    if (!supported.contains(name)) return child;
    final duration = math.max(.10, end - start);
    final time = math.max(0.0, elapsed - start);
    final progress = (time / duration).clamp(0.0, 1.0).toDouble();
    Widget video = child;
    switch (name) {
      case 'Quick Speed':
        final scene = ((time * 3.6).floor()) % 3;
        final tint = <Color>[
          const Color(0x28133168), const Color(0x10A5DFFF),
          const Color(0x36201015),
        ][scene];
        video = Transform.scale(scale: 1.04 + .022 * math.sin(time * 11),
          child: ColorFiltered(colorFilter: ColorFilter.mode(tint,
            BlendMode.srcOver), child: child));
        break;
      case "Something's ...":
        final zoom = 1 + .83 * _smooth((progress - .08) / .65);
        video = Transform.scale(scale: zoom,
          alignment: const Alignment(-.88, -.50), child: child);
        break;
      case 'Scanning lig...':
        video = ColorFiltered(colorFilter: const ColorFilter.matrix([
          .21,0,0,0,0, 0,.22,0,0,0, 0,0,.27,0,2, 0,0,0,1,0,
        ]), child: child);
        break;
      case 'Moon Off':
        final dim = 1 - .78 * _smooth(progress);
        video = ColorFiltered(colorFilter: ColorFilter.matrix([
          dim,0,0,0,0, 0,dim,0,0,0, 0,0,dim,0,0, 0,0,0,1,0,
        ]), child: child);
        break;
      case 'Illusion':
        final shift = (1 + .9 * _smooth(progress)).toDouble();
        final cold = ColorFiltered(colorFilter: const ColorFilter.matrix([
          .75,.06,.09,0,35, .03,.73,.13,0,36,
          .08,.05,.79,0,38, 0,0,0,1,0,
        ]), child: child);
        final cyan = ColorFiltered(colorFilter: const ColorFilter.mode(
          Color(0x4461DDFF), BlendMode.screen), child: child);
        video = Stack(fit: StackFit.passthrough, children: [
          cold,
          Opacity(opacity: .27 * _smooth(progress), child:
            Transform.translate(offset: Offset(3.5 * shift, .7 * shift),
              child: cyan)),
        ]);
        break;
      default:
        break;
    }
    return ClipRect(child: Stack(fit: StackFit.passthrough, children: [
      video,
      Positioned.fill(child: IgnorePointer(child: CustomPaint(
        painter: _AmazingTenPainter(name: name, time: time,
          progress: progress),
      ))),
    ]));
  }

  static double _smooth(double x) {
    final p = x.clamp(0.0, 1.0).toDouble();
    return p * p * (3 - 2 * p);
  }
}

class _AmazingTenPainter extends CustomPainter {
  final String name;
  final double time;
  final double progress;
  const _AmazingTenPainter({required this.name, required this.time,
    required this.progress});

  double get p => progress;
  static const _gold = Color(0xFFF9DF87);

  void _text(Canvas canvas, String value, double x, double y,
      double height, Color color, {bool outline = false,
      bool handwriting = false}) {
    final style = TextStyle(fontSize: height, color: color,
      fontWeight: outline ? FontWeight.w900 : FontWeight.w400,
      fontStyle: handwriting ? FontStyle.italic : FontStyle.normal,
      fontFamily: handwriting ? 'cursive' : null,
      shadows: outline ? const [Shadow(color: Colors.black,
        offset: Offset(1.7, 2), blurRadius: 1.5)] : null);
    final painter = TextPainter(text: TextSpan(text: value, style: style),
      textDirection: TextDirection.ltr, maxLines: 1)..layout();
    painter.paint(canvas, Offset(x, y));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width, h = size.height, short = math.min(w, h);
    switch (name) {
      case 'Quick Speed':
        // Fast streaks converge on a road vanishing point. A real scene change
        // behind a person needs person segmentation, not a full-frame filter.
        final centre = Offset(w * .48, h * .43);
        for (var i = 0; i < 48; i++) {
          final a = i * 2 * math.pi / 48;
          final r = .34 + .17 * math.sin(i * 31.3);
          final edge = Offset(centre.dx + math.cos(a) * w * (1.4 + r),
            centre.dy + math.sin(a) * h * (1.1 + r));
          final from = Offset(centre.dx + (edge.dx - centre.dx) * .38,
            centre.dy + (edge.dy - centre.dy) * .38);
          final alpha = (.11 + .15 * math.sin(time * 10 + i)).clamp(0.0, .35).toDouble();
          canvas.drawLine(from, edge, Paint()
            ..color = Colors.white.withValues(alpha: alpha)
            ..strokeWidth = 1 + (i % 4) * .5);
        }
        break;
      case 'Energy':
        // Actual tapered manga-speed rays that originate at the borders and
        // stop around the subject. The previous endpoints were offscreen.
        final centre = Offset(w * .51, h * .46);
        for (var i = 0; i < 86; i++) {
          final a = i * math.pi * 2 / 86 +
              .018 * math.sin(i * 2.91 + time * 4.2);
          final dx = math.cos(a), dy = math.sin(a);
          final toX = dx > 0 ? (w - centre.dx) / dx :
              dx < 0 ? -centre.dx / dx : double.infinity;
          final toY = dy > 0 ? (h - centre.dy) / dy :
              dy < 0 ? -centre.dy / dy : double.infinity;
          final limit = math.min(toX, toY);
          final wav = .5 + .5 * math.sin(i * 21.87 + time * 7.3);
          final point = limit * (.24 + .39 * wav);
          final tip = centre + Offset(dx * point, dy * point);
          final edge = centre + Offset(dx * (limit + 3), dy * (limit + 3));
          final broad = short * ((i % 7 == 0 ? .048 : .013) + .013 * wav);
          final perp = Offset(-dy * broad, dx * broad);
          final ink = Path()..moveTo(tip.dx, tip.dy)
            ..lineTo(edge.dx + perp.dx, edge.dy + perp.dy)
            ..lineTo(edge.dx - perp.dx, edge.dy - perp.dy)..close();
          canvas.drawPath(ink, Paint()..color = const Color(0xF3000000));
        }
        break;
      case 'Split Apart':
        final amount = TiniAmazingTenPreview._smooth(p / .20);
        final crack = Path()
          ..moveTo(w * .53 - amount*w*.20, -4)
          ..lineTo(w*.33 - amount*w*.17, h*.32)
          ..lineTo(w*.61 - amount*w*.12, h*.49)
          ..lineTo(w*.40 - amount*w*.12, h*.73)
          ..lineTo(w*.53 - amount*w*.10, h+4)
          ..lineTo(w*.53 + amount*w*.10, h+4)
          ..lineTo(w*.58 + amount*w*.12, h*.73)
          ..lineTo(w*.86 + amount*w*.10, h*.51)
          ..lineTo(w*.58 + amount*w*.08, h*.32)
          ..lineTo(w*.79 + amount*w*.10, -4)
          ..close();
        canvas.drawPath(crack, Paint()..color = Colors.black);
        break;
      case 'Question Ma...':
        final appear = TiniAmazingTenPreview._smooth(p / .20) *
          (1 - TiniAmazingTenPreview._smooth((p-.77)/.18));
        for (var row = 0; row < 5; row++) {
          for (var col = 0; col < 4; col++) {
            final id = row*4+col;
            if (id / 23 > appear) continue;
            _text(canvas, '?', w * (-.02 + .275*col),
              h * (.03 + row*.207), short * .190,
              const Color(0xFFFFE447), outline: true);
          }
        }
        break;
      case 'سنة جديدة':
        final reveal = TiniAmazingTenPreview._smooth(p/.17) *
          (1 - TiniAmazingTenPreview._smooth((p-.43)/.16));
        if (reveal <= .01) break;
        canvas.saveLayer(Offset.zero & size, Paint()..color = Colors.white
          .withValues(alpha: reveal));
        const phrases = [
          'Wish you all the best.', 'Nice to meet you', 'New Year, New Me',
          'today is good.', 'Good luck to you', 'the best',
          'Best wishes forever', 'you always', 'new year',
          'Happy holidays!', 'love and joy',
        ];
        final scroll = TiniAmazingTenPreview._smooth(p/.50);
        for (var i = 0; i < phrases.length; i++) {
          _text(canvas, phrases[i],
            w * (-.14 + .06 * math.sin(i*7.4) - .09*scroll),
            h * (-.075 + .095*i + .025*scroll),
            short * (.095 + .018*(i%3)), _gold, handwriting: true);
        }
        canvas.restore();
        break;
      case 'Scanning lig...':
        // A bright, hard diagonal core surrounded by an independently moving
        // blue fall-off. Both move across the underlying darkened picture.
        final displacement = -.18 + 1.35 * p;
        final path = Path()
          ..moveTo(w*(displacement-.45*.0), -h*.2)
          ..lineTo(w*(displacement-.45*1.2), h*1.2);
        canvas.drawPath(path, Paint()..style = PaintingStyle.stroke
          ..strokeWidth = short * .46
          ..shader = ui.Gradient.linear(Offset(w*(displacement), 0),
            Offset(w*(displacement-.45), h), [
              const Color(0x00C8E7FF), const Color(0xB08FD0FF),
              const Color(0x00C8E7FF)]));
        canvas.drawPath(path, Paint()..style = PaintingStyle.stroke
          ..strokeWidth = short * .046..strokeCap = StrokeCap.round
          ..color = const Color(0xF5F1F8FF)
          ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, 2));
        break;
      case 'Shockwave':
        final intensity = math.pow(1-p, 1.35).toDouble();
        canvas.drawRect(Offset.zero & size,
          Paint()..color = const Color(0xFFF75943)
            .withValues(alpha: .48*intensity));
        final centre = Offset(w*.37,h*.49);
        for (var ring = 0; ring < 3; ring++) {
          final radius = short*(.23 + .65*TiniAmazingTenPreview._smooth(p) + ring*.22);
          final stroke = Path();
          for (var i=0; i<=100; i++) {
            final a=i*math.pi*2/100;
            final wobble = 1 + .15*math.sin(a*9 + ring*7 + time*5)
              + .06*math.sin(a*23-time*9);
            final x=centre.dx+math.cos(a)*radius*wobble;
            final y=centre.dy+math.sin(a)*radius*wobble;
            if(i==0){stroke.moveTo(x,y);}else{stroke.lineTo(x,y);}
          }
          canvas.drawPath(stroke, Paint()..style=PaintingStyle.stroke
            ..strokeWidth=short*(.026-ring*.004)
            ..color=const Color(0xFFFF835C).withValues(alpha: .74*intensity)
            ..maskFilter=ui.MaskFilter.blur(ui.BlurStyle.normal,short*.028));
          canvas.drawPath(stroke, Paint()..style=PaintingStyle.stroke
            ..strokeWidth=1.3..color=Colors.white.withValues(alpha:.9*intensity));
        }
        break;
      case 'Moon Off':
        final fade = (1 - TiniAmazingTenPreview._smooth((p-.62)/.21));
        if (fade < .01) break;
        final c = Offset(w*.27,h*.53);
        final rect = Rect.fromCenter(center:c,width:short*.21,height:short*.21);
        final golden = Paint()..color=_gold.withValues(alpha:fade)
          ..strokeWidth = math.max(1,short*.005)..style=PaintingStyle.stroke;
        canvas.drawRect(rect,golden);
        final lineX = rect.left-short*.068;
        canvas.drawLine(Offset(lineX,rect.top-short*.11),
          Offset(lineX,rect.bottom+short*.10),golden);
        final moon = p > .36;
        final sphere = c;
        canvas.drawCircle(sphere,short*.059,Paint()..color=(moon ?
          const Color(0xFFECE7C6) : const Color(0xFFFFBA27))
          .withValues(alpha:fade));
        for(var i=0;i<8;i++){
          final a=i*math.pi*.25;
          final off=Offset(math.cos(a),math.sin(a));
          if(!moon){
            canvas.drawLine(sphere+off*short*.065,
              sphere+off*short*.082,golden);
          } else {
            canvas.drawCircle(sphere+off*short*.032,short*.008,
              Paint()..color=const Color(0x665B5661).withValues(alpha:fade));
          }
        }
        final sun = Offset(lineX,moon?rect.bottom+short*.12:rect.top-short*.12);
        canvas.drawCircle(sun,short*.016,Paint()..color=_gold.withValues(alpha:fade));
        for(var i=0;i<8;i++){
          final a=i*math.pi/4, dir=Offset(math.cos(a),math.sin(a));
          canvas.drawLine(sun+dir*short*.021,sun+dir*short*.032,golden);
        }
        break;
      default: break;
    }
  }

  @override
  bool shouldRepaint(covariant _AmazingTenPainter old) =>
    name != old.name || time != old.time || progress != old.progress;
}
