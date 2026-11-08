import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Live screen decorations. Frames are painted over the actual playing video;
/// inset photo treatments retain a separate video viewport (not a flat image).
class TiniScreenEffectsPreview {
  static const category = 'شاشة';
  static const supported = <String>{
    'Seagull Digit...', 'Balloon Frame', 'Yellow And B...', 'Cute Polaroid',
    'Graphic 2', 'MV Cover', 'DV', 'Spring Border', 'DV II', 'Camera Grid',
    'Viewfinder II', 'Graphic III', 'Cinema', 'Camcorder II', 'Color Phosp...',
  };

  static double thumbnailSeconds(String name) => switch (name) {
    'Spring Border' => 1.28,
    'Color Phosp...' => .42,
    'Balloon Frame' => .94,
    _ => .78,
  };

  static Widget apply({required String name, required Widget child,
      required double elapsed, required double start, required double end}) {
    if (!supported.contains(name)) return child;
    final t = math.max(0.0, elapsed - start);
    return LayoutBuilder(builder: (context, limits) {
      // No intermediate render targets or global mutable state are needed.
      final w = limits.maxWidth;
      final h = limits.maxHeight;
      if (!w.isFinite || !h.isFinite || w <= 0 || h <= 0) return child;
      Widget source = child;
      if (name == 'Seagull Digit...' || name == 'DV') {
        source = ColorFiltered(colorFilter: const ColorFilter.matrix([
          1.04,0,0,0,-8, 0,1.04,0,0,-8, 0,0,1.04,0,-8,
          0,0,0,1,0,
        ]), child: source);
      } else if (name == 'Viewfinder II') {
        source = ColorFiltered(colorFilter: const ColorFilter.mode(
          Color(0x27000000), BlendMode.darken), child: source);
      }
      if (name == 'Cute Polaroid') {
        return ClipRect(child: Stack(fit: StackFit.expand, children: [
          const ColoredBox(color: Color(0xFFF3BBC5)),
          CustomPaint(painter: _ScreenPainter(name, t, background: true)),
          Positioned(left: w*.16, top: h*.30, width: w*.68, height: h*.39,
            child: DecoratedBox(decoration: const BoxDecoration(
              color: Colors.white, boxShadow: [BoxShadow(
                color: Color(0x4C6F2634), blurRadius: 8, offset: Offset(1,4))]),
              child: Padding(padding: EdgeInsets.fromLTRB(w*.022,w*.022,
                    w*.022,h*.060),
                child: ClipRect(child: FittedBox(fit: BoxFit.cover,
                  child: SizedBox(width: w, height: h, child: source)))))),
          Positioned.fill(child: IgnorePointer(child: CustomPaint(
            painter: _ScreenPainter(name, t)))),
        ]));
      }
      if (name == 'MV Cover') {
        return ClipRect(child: Stack(fit: StackFit.expand, children: [
          ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: 12,
            sigmaY: 12), child: Opacity(opacity: .64, child: source)),
          Positioned(left: w*.105, top: h*.095, width: w*.79, height: h*.83,
            child: DecoratedBox(decoration: BoxDecoration(
              border: Border.all(color: const Color(0xBBFFFFFF),
                width: math.max(1.0,w*.007))),
              child: ClipRect(child: FittedBox(fit: BoxFit.cover,
                child: SizedBox(width: w, height: h, child: source))))),
          Positioned.fill(child: IgnorePointer(child: CustomPaint(
            painter: _ScreenPainter(name, t)))),
        ]));
      }
      return ClipRect(child: Stack(fit: StackFit.expand, children: [
        source,
        Positioned.fill(child: IgnorePointer(child: CustomPaint(
          painter: _ScreenPainter(name, t)))),
      ]));
    });
  }
}

class _ScreenPainter extends CustomPainter {
  final String name;
  final double t;
  final bool background;
  const _ScreenPainter(this.name, this.t, {this.background = false});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final thin = math.max(1.0, math.min(w,h)*.006);
    Offset p(double x, double y) => Offset(x*w,y*h);
    Rect r(double x,double y,double rw,double rh) =>
        Rect.fromLTWH(x*w,y*h,rw*w,rh*h);
    void line(double ax,double ay,double bx,double by, Color c,
        [double mult = 1]) => canvas.drawLine(p(ax,ay),p(bx,by),Paint()
          ..color=c..strokeWidth=thin*mult..strokeCap=StrokeCap.round);
    void rect(double x,double y,double rw,double rh,Color color,
        {double radius = 0, bool outline = false, double thick = 1}) {
      final paint=Paint()..color=color..style=(outline ? PaintingStyle.stroke : PaintingStyle.fill)
        ..strokeWidth=thin*thick;
      canvas.drawRRect(RRect.fromRectAndRadius(r(x,y,rw,rh),
        Radius.circular(w*radius)),paint);
    }
    void text(String value,double x,double y,Color c, {double scale=.048,
        FontWeight weight=FontWeight.w600, bool shadow = false}) {
      final painter=TextPainter(text:TextSpan(text:value,
        style:TextStyle(color:c,fontSize:math.max(8.0,w*scale),
          fontWeight:weight,letterSpacing:.5,
          shadows:shadow ? const [Shadow(color: Colors.black54,
              offset: Offset(1,1),blurRadius:2)] : null)),
        textDirection:TextDirection.ltr,maxLines:1);
      painter.layout(maxWidth:w*.96);painter.paint(canvas,p(x,y));
    }
    void corner(double x,double y,double sx,double sy,Color c,
        [double length=.095]) {
      line(x,y,x+sx*length,y,c,1.35);
      line(x,y,x,y+sy*length,c,1.35);
    }
    void corners(Color color,{double inset=.045,double length=.105}) {
      corner(inset,inset,1,1,color,length);
      corner(1-inset,inset,-1,1,color,length);
      corner(inset,1-inset,1,-1,color,length);
      corner(1-inset,1-inset,-1,-1,color,length);
    }
    void star(double x,double y,double rad,Color color) {
      final path=Path();
      for(var i=0;i<8;i++) {
        final a=i*math.pi/4;
        final d=(i.isEven?rad:rad*.26);
        final pt=p(x+math.cos(a)*d,y+math.sin(a)*d*w/h);
        if(i==0) path.moveTo(pt.dx,pt.dy); else path.lineTo(pt.dx,pt.dy);
      }
      path.close(); canvas.drawPath(path,Paint()..color=color);
    }
    void flower(double x,double y,double scale,Color color) {
      for(var j=0;j<5;j++) {
        final a=j*math.pi*2/5+t*.11;
        canvas.drawOval(Rect.fromCenter(center:p(x+math.cos(a)*scale*.48,
          y+math.sin(a)*scale*.48*w/h),width:w*scale*.65,
          height:w*scale*.6),Paint()..color=color);
      }
      canvas.drawCircle(p(x,y),w*scale*.19,
          Paint()..color=const Color(0xFFFFB52F));
    }
    void heart(double x,double y,double scale,Color color) {
      final s=w*scale;
      final center=p(x,y);
      final path=Path()..moveTo(center.dx,center.dy+s*.80)
        ..cubicTo(center.dx-s*.2,center.dy+s*.54,
            center.dx-s*.76,center.dy+s*.18,center.dx-s*.60,center.dy-s*.15)
        ..cubicTo(center.dx-s*.45,center.dy-s*.48,
            center.dx-s*.07,center.dy-s*.35,center.dx,center.dy-s*.08)
        ..cubicTo(center.dx+s*.12,center.dy-s*.42,
            center.dx+s*.55,center.dy-s*.45,center.dx+s*.62,center.dy-s*.13)
        ..cubicTo(center.dx+s*.75,center.dy+s*.23,
            center.dx+s*.21,center.dy+s*.60,center.dx,center.dy+s*.80);
      canvas.drawPath(path,Paint()..color=color);
    }
    if (background) {
      if (name == 'Cute Polaroid') {
        for(var row=0;row<13;row++) {
          for(var col=0;col<8;col++) {
            final ox=(row.isEven ? .017 : 0.0);
            heart(.035+col*.133+ox,.023+row*.079,.014,
              const Color(0xFFD65E7E).withValues(alpha: .75));
          }
        }
      }
      return;
    }
    switch(name) {
      case 'Seagull Digit...':
        corners(const Color(0xCFF4F7FA),inset:.085,length:.12);
        text('RAW',.83,.05,Colors.white,scale:.037,shadow:true);
        text('01   02    03',.075,.94,Colors.white70,scale:.031);
        text('▮▯▮  ISO   800',.47,.952,Colors.white70,scale:.029);
        break;
      case 'Balloon Frame':
        final colors=[const Color(0xFFF6497D),const Color(0xFFFFCC40),
          const Color(0xFF55B4EC),const Color(0xFFB06FE7),
          const Color(0xFF47CEC6),const Color(0xFFF89D4C)];
        for(var i=0;i<19;i++) {
          final top=i<10;
          final k=top?i:i-10;
          final x=top?-.07+(k%5)*.102: .75+(k%5)*.085;
          final y=top?-.043+(k~/5)*.115:.69+(k~/5)*.16;
          final displacement=.009*math.sin(t*2.5+i*1.9);
          final rx=w*(.062+(i%3)*.008);
          final ry=h*.052;
          final centre=p(x+displacement,y);
          canvas.drawOval(Rect.fromCenter(center:centre,width:rx*2,height:ry*2),
              Paint()..color=colors[i%colors.length]);
          canvas.drawOval(Rect.fromCenter(center:centre+Offset(-rx*.25,-ry*.32),
            width:rx*.45,height:ry*.45),Paint()..color=Colors.white.withValues(alpha:.24));
          line(x+displacement,y+.052,x+displacement+.013,y+.096,
              const Color(0xAAEEEEEE),.45);
        }
        for(var i=0;i<7;i++) star(.06+i*.141,.035+(i%3)*.045,
          .012,const Color(0xEAFFFFFF));
        break;
      case 'Yellow And B...':
        rect(0,0,1,.022,const Color(0xFFD4F9FF));
        rect(0,.976,1,.024,const Color(0xFFFFEBA1));
        rect(0,0,.026,1,const Color(0xFFFFF0AD));
        rect(.974,0,.026,1,const Color(0xFFB6F6FC));
        for(final pos in [(x:.095,y:.045),(x:.90,y:.048),
            (x:.91,y:.91),(x:.06,y:.84)]) {
          star(pos.x,pos.y,.028,Colors.black87);
        }
        line(.04,.955,.96,.955,const Color(0xB5FFF0B3),1.5);
        break;
      case 'Cute Polaroid':
        text('I love you ♡',.30,.645,const Color(0xFFD24B73),scale:.063,
            weight:FontWeight.w500);
        break;
      case 'Graphic 2':
        rect(0,0,1,.015,const Color(0xE6F6FBFF));
        rect(0,.965,1,.035,const Color(0xFFFFF0BA));
        rect(0,0,.023,1,const Color(0xCCF8FDFB));
        rect(.977,0,.023,1,const Color(0xCCF8FDFB));
        for (var i=0;i<8;i++) star(.06+i*.13,.035+(i%3)*.012,
          i.isEven ? .013 : .008,Colors.black87);
        text('▶▶   NOW PLAYING  /  PHOTO STORY',.08,.972,
          const Color(0xFF656C68),scale:.022);
        break;
      case 'MV Cover':
        rect(.10,.09,.80,.83,Colors.white70,outline:true,thick:2);
        text('♡ 3762',.76,.05,Colors.white,scale:.038,shadow:true);
        break;
      case 'DV':
        corners(Colors.white,inset:.045,length:.10);
        text('REC',.07,.04,Colors.white,scale:.043,shadow:true);
        text('HDV  ▣',.77,.045,Colors.white,scale:.043,shadow:true);
        text('00:00:02',.07,.098,Colors.white,scale:.035,shadow:true);
        rect(.78,.945,.16,.006,Colors.white70);
        break;
      case 'Spring Border':
        rect(0,.96,1,.04,const Color(0x7C58C34C));
        for (var i=0;i<22;i++) {
          final xx=(i*.173+.015)%1;
          final yy=.85+((i*7)%11)/100+.008*math.sin(t*2+i);
          line(xx,.985,xx,yy,const Color(0xFF3CB56B),.6);
          flower(xx,yy,.023+(i%3)*.006,
            i%3==0?const Color(0xFFFBADCE):
              i%3==1?const Color(0xFFFFE06E):const Color(0xFFFFFFFF));
        }
        for(var i=0;i<7;i++) star(.09+i*.13,.14+(i%3)*.24+
          .02*math.sin(t*1.8+i),.013,const Color(0xFFFFE888));
        break;
      case 'DV II':
        text('CAM',.022,.04,const Color(0xFF8AFF70),scale:.047);
        text('SP   ▶',.73,.04,Colors.white,scale:.041,shadow:true);
        text('00:06:20',.70,.092,Colors.white,scale:.037,shadow:true);
        text('FEB. 02. 1997',.02,.935,Colors.white,scale:.034,shadow:true);
        text('PM 08:26',.72,.935,Colors.white,scale:.035,shadow:true);
        break;
      case 'Camera Grid':
        for(final x in [.333,.666]) line(x,0,x,1,Colors.white38,.6);
        for(final y in [.333,.666]) line(0,y,1,y,Colors.white38,.6);
        line(.482,.50,.518,.50,Colors.white70,.85);
        line(.5,.482,.5,.518,Colors.white70,.85);
        break;
      case 'Viewfinder II':
        corners(Colors.white70,inset:.048,length:.10);
        for (var i=0;i<13;i++) {
          line(.34+i*.027,.947+(i%3)*.003,.34+i*.027,.958,
              Colors.white54,.45);
        }
        break;
      case 'Graphic III':
        rect(.015,.014,.97,.972,Colors.white70,outline:true,thick:1);
        text('GRAPHIC',.05,.042,Colors.white70,scale:.033);
        text('●',.87,.04,const Color(0xFFE86D76),scale:.035);
        line(.07,.93,.93,.93,Colors.white54,.8);
        break;
      case 'Cinema':
        rect(0,0,1,.098,Colors.black);
        rect(0,.898,1,.102,Colors.black);
        line(.07,.100,.93,.100,Colors.white24,.55);
        line(.07,.897,.93,.897,Colors.white24,.55);
        break;
      case 'Camcorder II':
        text('●',.025,.05,const Color(0xFFEB3D3D),scale:.044);
        text('REC',.075,.058,Colors.white,scale:.041,shadow:true);
        text('16:9  HD',.73,.058,Colors.white,scale:.033,shadow:true);
        text('ISO',.04,.922,Colors.white,scale:.033,shadow:true);
        text('100  1/250',.04,.956,Colors.white,scale:.025,shadow:true);
        line(.24,.951,.71,.951,Colors.white70);
        for(var i=0;i<10;i++) line(.24+i*.051,.943,.24+i*.051,.955,
            Colors.white70,.5);
        break;
      case 'Color Phosp...':
        final glow=.46+.20*math.sin(t*6.4);
        rect(.008,.006,.984,.008,const Color(0xFFFF8C9B).withValues(alpha:glow));
        rect(.008,.982,.984,.010,const Color(0xFF8B9BFF).withValues(alpha:glow));
        rect(.006,.006,.010,.986,const Color(0xFFFC668D).withValues(alpha:glow));
        rect(.983,.006,.010,.986,const Color(0xFF84BBFF).withValues(alpha:glow));
        line(.02,.03,.96,.03,const Color(0xD5FF8389),2.2);
        line(.035,.965,.97,.965,const Color(0xD58D9FFF),2.1);
        break;
    }
  }

  @override
  bool shouldRepaint(_ScreenPainter old) => name!=old.name ||
      background!=old.background || t!=old.t;
}
