import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Lighting tab: each reference effect gets a distinct, time-based light field.
/// This paints over the *actual player frame*; it does not alter video decoding,
/// selection, the undo stack, or effects belonging to other categories.
class TiniLightingEffectsPreview {
  static const category = 'إضاءة';

  /// A useful keyframe for unselected grid tiles (not always a fade-in frame).
  static double thumbnailSeconds(String name) => switch (name) {
    'Diamond Sof...' => .42,
    'Leak II' || 'Leak 1' || 'Leak' => .60,
    'Halo Light II' => .52,
    'Rainbow Sha...' || 'Prism I' => .65,
    'Lights' => .80,
    'Water Reflec...' => .73,
    _ => .48,
  };

  static Widget apply({required String name, required Widget child,
      required double elapsed, required double start, required double end}) {
    final t = (elapsed - start).clamp(0.0, (end-start).clamp(0.0, 999999.0)).toDouble();
    Widget video = child;
    double saturation = 1.0;
    double brightness = 0.0;
    double contrast = 1.0;
    double blur = 0.0;
    switch (name) {
      case 'Frost Soft Le...': saturation=.78; brightness=.035; contrast=.93; blur=.55; break;
      case 'Diamond Sof...': saturation=1.08; brightness=.035; contrast=1.05; break;
      case 'Soft Light': saturation=1.04; brightness=.065; contrast=.87; break;
      case 'Over Exposu...': brightness=.22; contrast=.83; break;
      case 'Dream Glow': saturation=1.09; brightness=.055; contrast=.92; break;
      case 'Red Glow': saturation=1.11; brightness=-.06; contrast=1.13; break;
      case 'Glow': brightness=.08; contrast=.94; break;
      case 'Leak II': saturation=1.09; contrast=1.03; break;
      case 'Leak 1': brightness=.055; contrast=.92; break;
      case 'Leak': saturation=1.10; contrast=1.08; break;
      case 'Vaporwave': saturation=1.18; contrast=1.08; break;
      case 'Neon': saturation=1.29; contrast=1.22; brightness=-.055; break;
      case 'Halo Light II': saturation=1.06; brightness=.012; break;
      case 'Rainbow Sha...': contrast=1.05; brightness=.008; break;
      case 'Water Reflec...': saturation=1.08; contrast=1.07; break;
      case 'Angel': brightness=.13; contrast=.80; break;
      case 'Tyndall Light': saturation=.98; contrast=.96; brightness=.035; break;
      case 'Backlight': contrast=.90; brightness=.025; break;
      case 'Prism I': saturation=.77; contrast=1.18; brightness=-.22; break;
      case 'Lights': saturation=1.10; brightness=.025; break;
      default: return video;
    }
    final k = 1.0-saturation;
    final a = contrast;
    final offset = 255.0*(brightness+(1.0-contrast)*.5);
    video = ColorFiltered(colorFilter: ColorFilter.matrix([
      a*(saturation+.2126*k), a*.7152*k, a*.0722*k, 0, offset,
      a*.2126*k, a*(saturation+.7152*k), a*.0722*k, 0, offset,
      a*.2126*k, a*.7152*k, a*(saturation+.0722*k), 0, offset,
      0, 0, 0, 1, 0,
    ]), child: video);
    if (blur>0) {
      video = ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: blur,
          sigmaY: blur), child: video);
    }
    return ClipRect(child: Stack(fit: StackFit.passthrough, children: [
      video,
      Positioned.fill(child: IgnorePointer(child: CustomPaint(
        painter: _LightingPainter(name: name, time: t),
      ))),
    ]));
  }
}

class _LightingPainter extends CustomPainter {
  final String name;
  final double time;
  const _LightingPainter({required this.name, required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w=size.width, h=size.height;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    Offset p(double x,double y) => Offset(w*x,h*y);
    double f(double x)=>math.sin(x);
    void glow(double x,double y,double radius,Color color,{double strength=1}) {
      final center=p(x,y);
      final rect=Rect.fromCircle(center:center,radius:radius*math.max(w,h));
      final shader=ui.Gradient.radial(center,rect.width/2,[
        color.withValues(alpha: strength.clamp(0.0,1.0).toDouble()),
        color.withValues(alpha: (strength*.35).clamp(0.0,1.0).toDouble()),
        color.withValues(alpha: 0)], [0,.36,1]);
      canvas.drawOval(rect,Paint()..shader=shader..blendMode=BlendMode.screen);
    }
    void beam(Offset from,Offset to,double thickness,Color color,{double strength=.65}) {
      final shader=ui.Gradient.linear(from,to,[
        color.withValues(alpha: strength.clamp(0.0,1.0).toDouble()),
        color.withValues(alpha: (strength*.38).clamp(0.0,1.0).toDouble()),
        color.withValues(alpha: 0)], [0,.53,1]);
      canvas.drawLine(from,to,Paint()..shader=shader..strokeCap=StrokeCap.round
        ..strokeWidth=thickness*math.min(w,h)..blendMode=BlendMode.screen
        ..maskFilter=ui.MaskFilter.blur(ui.BlurStyle.normal,thickness*math.min(w,h)*.10));
    }
    void spark(double x,double y,double sizeRatio,Color color) {
      final center=p(x,y), r=math.min(w,h)*sizeRatio;
      final paint=Paint()..color=color.withValues(alpha:.78)
        ..strokeWidth=math.max(.7,r*.10)..strokeCap=StrokeCap.round
        ..blendMode=BlendMode.screen;
      canvas.drawLine(center+Offset(-r,0),center+Offset(r,0),paint);
      canvas.drawLine(center+Offset(0,-r),center+Offset(0,r),paint);
      glow(x,y,sizeRatio*.095,color,strength:.32);
    }

    switch(name) {
      case 'Frost Soft Le...':
        glow(.05,.35,.77,const Color(0xFF80B9FE),strength:.25);
        glow(.99,.75,.69,const Color(0xFFD9B8F9),strength:.29);
        glow(.48,.08,.40,const Color(0xFFE4F2FF),strength:.20);
        for(var i=0;i<8;i++) {
          spark(.12+(i*29%77)/100,.10+(i*17%61)/100,.012,
            const Color(0xFFDAEDFF));
        }
        break;
      case 'Diamond Sof...':
        glow(.72,.27,.45,const Color(0xFFFFF2FF),strength:.22);
        for(var i=0;i<13;i++) {
          final x=.07+((i*37)%89)/100.0, y=.10+((i*53)%81)/100.0;
          final blink=.45+.55*math.pow(math.max(0,f(time*3.4+i*2.1)),4);
          spark(x,y,(.025+.018*(i%3))*blink,const Color(0xFFE9F5FF));
        }
        break;
      case 'Soft Light':
        glow(.52,.43,.88,const Color(0xFFFFE6C9),strength:.16);
        break;
      case 'Over Exposu...':
        glow(.52,.32,1.02,Colors.white,strength:.53);
        glow(.45,.12,.65,const Color(0xFFFFF1D4),strength:.42);
        break;
      case 'Dream Glow':
        glow(.92,.21,.80,const Color(0xFFFFCC8A),strength:.35);
        glow(.08,.81,.70,const Color(0xFFFFB3E8),strength:.25);
        glow(.52,.36,.58,const Color(0xFFFFF7DB),strength:.19);
        break;
      case 'Red Glow':
        glow(.03,.68,.92,const Color(0xFFFF171B),strength:.78);
        glow(.91,.86,.51,const Color(0xFFFF4921),strength:.18);
        break;
      case 'Glow':
        glow(.52,.43,.98,Colors.white,strength:.34);
        glow(.57,.27,.48,const Color(0xFFFAF4D6),strength:.14);
        break;
      case 'Leak II':
        glow(1.07,.29,.93,const Color(0xFFFF3D0C),strength:.61);
        beam(p(1.02,-.11),p(.58,1.01),.24,const Color(0xFFFFD578),strength:.54);
        break;
      case 'Leak 1':
        glow(1.05,.18,.83,const Color(0xFFFFB26E),strength:.71);
        glow(-.07,1.06,.72,const Color(0xFFFFD19C),strength:.39);
        break;
      case 'Leak':
        glow(-.18,.83,.93,const Color(0xFFFF542A),strength:.68);
        beam(p(-.08,.22),p(.32,1.1),.17,const Color(0xFFFFAD39),strength:.40);
        break;
      case 'Vaporwave':
        glow(.78,.30,.96,const Color(0xFFE725CD),strength:.50);
        glow(-.07,.13,.83,const Color(0xFF45F6FF),strength:.32);
        glow(.53,1.09,.62,const Color(0xFF8668FF),strength:.22);
        break;
      case 'Neon':
        glow(.86,.76,.94,const Color(0xFFFF0A9C),strength:.73);
        glow(.02,.07,.96,const Color(0xFF29EFFF),strength:.54);
        break;
      case 'Halo Light II':
        final rect=Rect.fromCenter(center:p(.95,.51),width:w*1.13,height:h*.88);
        const rainbow=[Color(0xFFFF5B43),Color(0xFFFFD84A),Color(0xFF69E390),
          Color(0xFF55CEFF),Color(0xFF8B75FA),Color(0xFFD3AAFE)];
        for(var i=0;i<rainbow.length;i++) {
          final paint=Paint()..color=rainbow[i].withValues(alpha:.36)
            ..style=PaintingStyle.stroke..strokeWidth=math.max(3.0,w*.052)
            ..maskFilter=const ui.MaskFilter.blur(ui.BlurStyle.normal,5)
            ..blendMode=BlendMode.screen;
          canvas.drawArc(rect.inflate(i*w*.037),-.3,math.pi*1.23,false,paint);
        }
        glow(.96,.50,.76,const Color(0xFFD5EDFF),strength:.10);
        break;
      case 'Rainbow Sha...':
        final shift=.16*f(time*.65);
        const colors=[Color(0xFFFF6476),Color(0xFFFFD85E),
          Color(0xFF68DB9F),Color(0xFF66B9F8),Color(0xFFD38CFF)];
        for(var i=0;i<colors.length;i++) {
          final offset=(i-2)*.14+shift;
          beam(p(-.28+offset,-.10),p(.78+offset,1.08),.24,colors[i],strength:.29);
        }
        break;
      case 'Water Reflec...':
        for(var i=0;i<15;i++) {
          final y=.03+i*.028;
          final path=Path()..moveTo(w*(-.1),h*y);
          for(var j=0;j<=28;j++) {
            final x=j/28.0;
            path.lineTo(w*x,h*(y+.010*f(x*23+time*1.9+i*.71)));
          }
          canvas.drawPath(path,Paint()..color=const Color(0xFFA6E7FF).withValues(alpha: (i % 3 == 0 ? 0.20 : 0.08))
            ..style=PaintingStyle.stroke..strokeWidth=math.max(1.0,w*.004)
            ..blendMode=BlendMode.screen);
        }
        glow(.06,.23,.57,const Color(0xFF79D7FF),strength:.13);
        for(var i=0;i<7;i++) {
          spark(.14+(i*31%75)/100,.05+(i*23%38)/100,.009,
            const Color(0xFFC7E9FF));
        }
        break;
      case 'Angel':
        glow(.53,-.04,1.07,Colors.white,strength:.67);
        for(var i=0;i<6;i++) {
          beam(p(.50,-.15),p(-.24+i*.30,1.16),.20,
            const Color(0xFFFFF9E6),strength:.25);
        }
        break;
      case 'Tyndall Light':
        for(var i=0;i<5;i++) {
          beam(p(-.21+i*.13,-.13),p(.34+i*.19,1.08),.20,
              const Color(0xFFFFDD94),strength:.35);
        }
        glow(.02,-.05,.63,const Color(0xFFFFE3A8),strength:.26);
        break;
      case 'Backlight':
        glow(.52,.01,.94,const Color(0xFFE1F4FF),strength:.41);
        final paint=Paint()..color=const Color(0xFFD8EDFF).withValues(alpha:.16)
          ..style=PaintingStyle.stroke..strokeWidth=w*.060
          ..maskFilter=const ui.MaskFilter.blur(ui.BlurStyle.normal,11)
          ..blendMode=BlendMode.screen;
        canvas.drawOval(Rect.fromCenter(center:p(.52,.53),width:w*.90,height:h*.88),paint);
        break;
      case 'Prism I':
        final shift=.12*f(time*.45);
        beam(p(.84+shift,-.20),p(.01+shift,.92),.30,const Color(0xFF61DFF8),strength:.69);
        beam(p(.99+shift,-.20),p(.15+shift,.92),.29,const Color(0xFFABEF5C),strength:.66);
        beam(p(1.15+shift,-.16),p(.32+shift,.96),.26,const Color(0xFFFF5D7A),strength:.55);
        break;
      case 'Lights':
        const colors=[Color(0xFFFFB75B),Color(0xFF72DDFF),Color(0xFFFF628D),
          Color(0xFF74FFB9),Color(0xFFFFCD82),Color(0xFF8EACFF),
          Color(0xFFFF7F7A),Color(0xFFD4FF69),Color(0xFFF0C2FF)];
        for(var i=0;i<21;i++) {
          final a=i*2.39996;
          final x=.48+.53*f(a+time*(.35+i%4*.08));
          final y=.47+.60*math.cos(a*1.47+time*(.24+i%3*.06));
          final radius=.10+(i%4)*.025;
          glow(x,y,radius,colors[i%colors.length],strength:.24+.07*(i%3));
        }
        break;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LightingPainter oldDelegate) =>
      name != oldDelegate.name || time != oldDelegate.time;
}
