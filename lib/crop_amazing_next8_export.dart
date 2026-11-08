import 'dart:math' as math;

/// Video-space treatments for the second eight Amazing reference effects.
/// All timelines use the existing effect interval and the incoming frame clock.
/// This module does not alter the preceding eight Amazing effects.
class TiniAmazingNextEightExport {
  static const category = 'مذهلة';
  static const supported = <String>{
    'Negative Wa...', 'American Co...', 'Reverse',
    'Negative Spli...', 'Comic Book ...', 'Surveillance ...',
    'Light Leaks', 'Color Negati...', 'خلل',
  };

  static String _num(num number) => number.toStringAsFixed(5);

  static List<String> filterGraph({
    required String input,
    required String output,
    required String name,
    required double startSeconds,
    required double endSeconds,
    required int width,
    required int height,
    required int index,
  }) {
    if (!supported.contains(name)) {
      throw UnsupportedError('Unknown Amazing effect: $name');
    }
    final n = 'an${index}_';
    final s = _num(startSeconds);
    final duration = _num(math.max(.1, endSeconds - startSeconds));
    final t = '(T-$s)';
    final result = <String>[];
    String part(String suffix) => '$n$suffix';
    void single(List<String> operations) => result.add(
        '[$input]${operations.join(',')},format=yuv420p[$output]');
    switch (name) {
      case 'Negative Wa...': {
        // Three separate moving negative cut-outs above a crimson image.
        final a=part('a'), b=part('b'), c=part('c');
        result.add('[$input]split=3[$a][$b][$c]');
        result.add('[$a]colorize=hue=350:saturation=0.67:'
            'lightness=0.46:mix=0.70,eq=contrast=1.14:saturation=1.12,'
            'format=yuv420p[${part('red')}]');
        result.add('[$b]negate,eq=contrast=1.38:saturation=1.16,'
            'format=yuv420p[${part('negative')}]');
        final sw=math.min(180,math.max(80,width ~/ 5));
        final sh=math.max(60,(sw*height/width).round());
        final moving = <String>[
          'lt(abs(X/W-(.30+.16*sin(4*$t))),.095)*lt(abs(Y/H-(.27+.08*cos(3*$t))),.09)',
          'lt(abs(X/W-(.66-.20*sin(3*$t+.5))),.075)*lt(abs(Y/H-(.58+.15*sin(2*$t))),.065)',
          'lt(abs(X/W-(.41+.12*cos(5*$t))),.045)*lt(abs(Y/H-(.79-.11*sin(4*$t))),.045)',
        ].join('+');
        result.add('[$c]scale=$sw:$sh,format=gray,'
            "geq=lum='if(gt($moving,.5),255,0)',"
            'scale=$width:$height:flags=neighbor,format=gray[${part('mask')}]');
        result.add('[${part('red')}][${part('negative')}][${part('mask')}]'
            'maskedmerge,format=yuv420p[$output]');
        break;
      }
      case 'American Co...': {
        final edge=math.max(2,(width*.012).round());
        final margin=math.max(8,(width*.065).round());
        final thick=math.max(3,(width*.018).round());
        single([
          'eq=contrast=1.19:saturation=1.32',
          'unsharp=3:3:0.55',
          'drawbox=x=0:y=0:w=$margin:h=ih:color=0xD6AF89@0.86:t=fill',
          'drawbox=x=iw-$margin:y=0:w=$margin:h=ih:color=0x91ADC1@0.83:t=fill',
          'drawbox=x=$margin:y=$margin:w=iw-2*$margin:'
              'h=ih-2*$margin:color=black@0.91:t=$thick',
          'drawbox=x=$edge:y=$edge:w=iw-2*$edge:h=ih-2*$edge:'
              'color=white@0.65:t=$edge',
        ]);
        break;
      }
      case 'Reverse': {
        // The recorded reference is a near-opaque pale wash, NOT hflip.
        single(['hue=s=0.07','eq=contrast=0.18:brightness=0.31',
          'gblur=sigma=1.2']);
        break;
      }
      case 'Negative Spli...': {
        final source=part('source'), negative=part('negative'), mono=part('mono');
        result.add('[$input]split=3[$source][$negative][$mono]');
        result.add('[$negative]negate,hue=h=22:s=1.7,'
            'eq=contrast=1.25,format=yuv420p[${part('neg')}]');
        result.add('[$mono]hue=s=0,eq=contrast=1.24,'
            'colorbalance=gs=0.22:gm=0.18:bs=-0.09,'
            'format=yuv420p[${part('gray')}]');
        final split='(.47+.24*sin(4.0*$t))';
        final band='(.39+.23*cos(3.3*$t))';
        result.add('[$source][${part('neg')}]blend=all_expr='
            "if(lt(X/W,$split)*lt(Y/H,$band),B,A)'[${part('mix')}]" );
        result.add('[${part('mix')}][${part('gray')}]blend=all_expr='
            "if(gt(X/W,$split)*gt(Y/H,$band),B,A)',"
            'format=yuv420p[$output]');
        break;
      }
      case 'Comic Book ...': {
        // Edge extraction is applied to the *moving source* rather than
        // drawing unrelated fixed contours over faces.
        final original=part('base'), edges=part('edge');
        result.add('[$input]split=2[$original][$edges]');
        result.add('[$original]eq=contrast=1.43:saturation=1.72,'
            'unsharp=5:5:0.95,format=yuv420p[${part('inkbase')}]');
        result.add('[$edges]format=gray,'
            'edgedetect=mode=wires:low=0.06:high=0.15,'
            'negate,format=yuv420p[${part('inklines')}]');
        result.add('[${part('inkbase')}][${part('inklines')}]'
            "blend=c0_expr='A*(.35+.65*B/255)':"
            "c1_expr='A':c2_expr='A',"
            'format=yuv420p[$output]');
        break;
      }
      case 'Surveillance ...': {
        final margin=math.max(4,(width*.040).round());
        final border=math.max(2,(width*.009).round());
        final font=math.max(11,(width*.038).round());
        single([
          'hue=h=258:s=0.61',
          'eq=contrast=0.90:brightness=-0.025',
          'drawgrid=w=iw:h=7:t=1:color=white@0.10',
          'drawbox=x=$margin:y=$margin:w=iw-2*$margin:'
              'h=ih-2*$margin:color=black@0.82:t=$border',
          "drawtext=text='CAM 01':x=$margin+8:y=$margin+8:"
              'fontsize=$font:fontcolor=white@0.83',
          "drawtext=text='REC':x=w-$margin-3*${font}:y=$margin+8:"
              'fontsize=$font:fontcolor=white@0.89',
          "drawtext=text='%{pts\\:hms}':x=$margin+8:"
              'y=h-$margin-${font+8}:fontsize=$font:fontcolor=white@0.83',
        ]);
        break;
      }
      case 'Light Leaks': {
        // Optical flares in *RGB* space: independent warm blooms, a cool
        // bloom and a moving hot streak. YUV-channel blending tinted the
        // source and made the leaks imperceptible on some devices.
        final sw=math.min(224, math.max(96, width ~/ 4));
        final sh=math.max(96, (sw * height / width).round());
        final hot='exp(-pow((X/W-(.12+.34*sin(1.45*$t)))/.31,2)'
          '-pow((Y/H-(.34+.25*cos(1.8*$t)))/.38,2))';
        final cool='exp(-pow((X/W-(.91-.34*sin(1.7*$t+.6)))/.29,2)'
          '-pow((Y/H-(.76-.16*cos(1.5*$t)))/.43,2))';
        final stripe='exp(-pow((X/W+.24*Y/H-(-.43+mod($t*.62,1.8)))/.10,2))';
        result.add('[$input]split=2[${part('base')}][${part('seed')}]');
        result.add('[${part('base')}]format=gbrp[${part('rgb')}]');
        result.add('[${part('seed')}]scale=$sw:$sh,format=gbrp,'
          "geq=r='clip(255*(.98*$hot+.33*$cool+.92*$stripe),0,255)':"
          "g='clip(255*(.58*$hot+.69*$cool+.58*$stripe),0,255)':"
          "b='clip(255*(.21*$hot+1.00*$cool+.34*$stripe),0,255)',"
          'scale=$width:$height:flags=bicubic,format=gbrp[${part('lights')}]');
        result.add('[${part('rgb')}][${part('lights')}]'
          'blend=all_mode=screen:all_opacity=0.92,'
          'format=yuv420p[$output]');
        break;
      }
      case 'خلل': {
        // Distorted live frame slices plus intermittent RGB channel separation.
        final sw=math.min(224,math.max(96,width ~/ 4));
        final sh=math.max(96,(sw * height / width).round());
        final rows = <String>[
          'lt(abs(Y/H-(.12+.09*sin(6*$t))),.052)',
          'lt(abs(Y/H-(.35+.11*cos(8*$t))),.064)',
          'lt(abs(Y/H-(.59+.10*sin(5*$t+2))),.049)',
          'lt(abs(Y/H-(.82+.08*cos(7*$t+3))),.058)',
        ].join('+');
        result.add('[$input]split=3[${part('base')}][${part('shift')}][${part('maskseed')}]');
        result.add('[${part('shift')}]format=rgba,'
          'rgbashift=rh=17:bh=-16:rv=4:bv=-4,'
          'noise=alls=19:allf=t,eq=contrast=1.38:saturation=1.72,'
          'format=yuv420p[${part('torn')}]');
        result.add('[${part('maskseed')}]scale=$sw:$sh,format=gray,'
          "geq=lum='if(gt($rows,.5),255,0)',"
          'scale=$width:$height:flags=neighbor,format=gray[${part('mask')}]');
        result.add('[${part('base')}][${part('torn')}][${part('mask')}]'
          'maskedmerge,rgbashift=rh=4:bh=-5,'
          'format=yuv420p[$output]');
        break;
      }
      case 'Color Negati...': {
        // Periodically cycle posterised solarised hues; finish each interval
        // with a brief return to the natural frame, as seen in the reference.
        final original=part('original'), inverted=part('inverted');
        result.add('[$input]split=2[$original][$inverted]');
        result.add('[$inverted]negate,'
            "hue=h='100+145*sin(3.1*(t-$s))':s=2,"
            'eq=contrast=1.65:saturation=2.4,'
            'format=yuv420p[${part('palette')}]');
        result.add('[$original][${part('palette')}]blend=all_expr='
            "if(lt(mod(max(0,$t),$duration),$duration*.87),B,A)',"
            'format=yuv420p[$output]');
        break;
      }
    }
    return result;
  }
}
