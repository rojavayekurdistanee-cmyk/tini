import 'dart:math' as math;

/// Dedicated FFmpeg treatment for the ten 40053.mp4 Amazing references.
/// Clip-local timing is derived from the existing effect interval. No change
/// to previously recorded Amazing, Vibe, Lighting or Dynamic effect recipes.
class TiniAmazingTenExport {
  static const category = 'مذهلة';
  static const supported = <String>{
    'Quick Speed', 'Energy', 'Split Apart', 'Question Ma...', 'سنة جديدة',
    "Something's ...", 'Scanning lig...', 'Shockwave', 'Moon Off', 'Illusion',
  };
  static const frameRateDependent = <String>{"Something's ...", 'Quick Speed'};
  static String _f(num n) => n.toStringAsFixed(5);

  static List<String> filterGraph({
    required String input, required String output, required String name,
    required double startSeconds, required double endSeconds,
    required int width, required int height, required int index,
  }) {
    if (!supported.contains(name)) {
      throw UnsupportedError('Unknown Amazing third-batch effect: $name');
    }
    final prefix = 'at${index}_';
    String tag(String suffix) => '$prefix$suffix';
    final s = _f(startSeconds);
    final d = _f(math.max(.1, endSeconds - startSeconds));
    final e = _f(endSeconds);
    final t = '(T-$s)';
    final phase = 'min(1,max(0,$t/$d))';
    final graph = <String>[];

    // An inexpensive low-resolution geometry mask, scaled back to output
    // dimensions, keeps geometrical effects feasible on mobile hardware.
    void mask({required String expr, required String foreground,
      String suffix = 'mask', String? base}) {
      final sw = (width / 4).round().clamp(96, 224);
      final sh = (height * sw / width).round().clamp(96, 400);
      graph.add('[$input]split=2[${tag('base')}][${tag('seed')}]');
      graph.add('[${tag('seed')}]scale=$sw:$sh,format=gray,'
        "geq=lum='$expr',scale=$width:$height:flags=bilinear,"
        'format=gray[${tag(suffix)}]');
      if (base == null) {
        graph.add('[${tag('base')}]split=2[${tag('under')}][${tag('solid')}]');
        graph.add('[${tag('solid')}]drawbox=x=0:y=0:w=iw:h=ih:'
          'color=$foreground:t=fill[${tag('ink')}]');
        graph.add('[${tag('under')}][${tag('ink')}][${tag(suffix)}]'
          'maskedmerge,format=yuv420p[$output]');
      } else {
        graph.add('[${tag('base')}]split=2[${tag('under')}][${tag('upper')}]');
        graph.add('[${tag('under')}]$base[${tag('dark')}]');
        graph.add('[${tag('upper')}]$foreground[${tag('bright')}]');
        graph.add('[${tag('dark')}][${tag('bright')}][${tag(suffix)}]'
          'maskedmerge,format=yuv420p[$output]');
      }
    }

    switch (name) {
      case 'Quick Speed': {
        // Fast alternating exposure + speed zoom. This cannot genuinely
        // replace the scene behind a human without a subject mask and street
        // background assets, which the generic effect renderer does not have.
        graph.add('[$input]zoompan='
          "z='1.04+0.06*abs(sin(on*.36))':"
          "x='(iw-iw/zoom)*(.5+.08*sin(on*.43))':"
          "y='(ih-ih/zoom)*(.50+.10*sin(on*.25))':"
          'd=1:s=${width}x$height:fps=30,'
          'eq=contrast=1.14:saturation=1.30,'
          "hue=h='12+30*sin(7.5*(t-$s))':s=1.12,"
          'unsharp=3:3:0.40,format=yuv420p[$output]');
        break;
      }
      case 'Energy': {
        // High-contrast radiating ink wedges with a clear central opening.
        // Match the Flutter tapered rays rather than keeping them offscreen.
        final dx='(X/W-.51)', dy='(Y/H-.46)';
        final radius='sqrt(pow($dx,2)+pow($dy,2))';
        final angle='atan2($dy,$dx)';
        final wobble='(.20+.10*sin(21*$angle+7*$t))';
        final strong='lt(abs(sin(43*$angle+.10*sin(4*$t))),'
            '(.15+.45*$radius))';
        final fine='lt(abs(sin(86*$angle+.22*cos(3*$t))),'
            '(.075+.18*$radius))';
        mask(expr:'if(gt($radius,$wobble),'
          'if(gt($strong+$fine,.5),255,0),0)',
          foreground:'black');
        break;
      }
      case 'Split Apart': {
        // Sharp zig-zag lightning gap: narrow at first, then thick black.
        final section = 'if(lt(Y/H,.32),.53-.49*(Y/H),'
          'if(lt(Y/H,.49),.37+1.38*(Y/H-.32),'
          'if(lt(Y/H,.73),.61-.83*(Y/H-.49),'
          '.41+.41*(Y/H-.73))))';
        final thick = '(.012+.175*min(1,max(0,$t/($d*.20))))';
        mask(expr:'if(lt(abs(X/W-($section)),$thick),255,0)',
          foreground:'black');
        break;
      }
      case 'Question Ma...': {
        // A full grid of yellow ? with black outlines and a shared fade out.
        final ops = <String>[];
        final alpha = 'min(1,max(0,(t-$s)/($d*.18)))'
          '*min(1,max(0,($e-t)/($d*.17)))';
        final size = math.max(19,(width*.21).round());
        for (var row=0; row<5; row++) {
          for (var col=0; col<4; col++) {
            final x = (width*(-.02+.275*col)).round();
            final y = (height*(.03+.207*row)).round();
            final stagger = _f(startSeconds + .16*(row*4+col)/20 *
              (endSeconds-startSeconds));
            ops.add('drawtext=text=\\?:x=$x:y=$y:fontsize=$size:'
              'fontcolor=0xFFE447:bordercolor=0x221700:borderw=2:'
              "alpha='$alpha':enable='between(t,$stagger,$e)'");
          }
        }
        graph.add('[$input]${ops.join(',')},format=yuv420p[$output]');
        break;
      }
      case 'سنة جديدة': {
        const lines = [
          'Wish you all the best', 'Nice to meet you', 'New Year New Me',
          'today is good', 'Good luck to you', 'the best',
          'Best wishes forever', 'you always', 'new year',
          'Happy holidays', 'love and joy',
        ];
        final alpha='min(1,max(0,(t-$s)/($d*.17)))'
          '*min(1,max(0,($s+$d*.58-t)/($d*.15)))';
        final fontsize = math.max(16,(width*.104).round());
        final ops=<String>[];
        for(var i=0;i<lines.length;i++) {
          final x=(width*(-.13+.04*math.sin(i*7.4))).round();
          final y=(height*(-.07+.094*i)).round();
          ops.add('drawtext=font=serif:text=${lines[i]}:x=$x:y=$y:'
            'fontsize=$fontsize:fontcolor=0xF9DF87:'
            "alpha='$alpha':enable='between(t,$s,$e)'");
        }
        graph.add('[$input]${ops.join(',')},format=yuv420p[$output]');
        break;
      }
      case "Something's ...": {
        // zoompan is evaluated against a normalized 30-fps timeline in the
        // parent render graph to avoid changing stream duration or timestamps.
        final local = '(on/30-$s)';
        final amount = 'min(1,max(0,($local-$d*.08)/($d*.65)))';
        graph.add('[$input]zoompan='
          "z='1+.83*($amount*$amount*(3-2*$amount))':"
          "x='(iw-iw/zoom)*.06':"
          "y='(ih-ih/zoom)*.20':d=1:s=${width}x$height:fps=30,"
          'format=yuv420p[$output]');
        break;
      }
      case 'Scanning lig...': {
        // Diagonal glow: x + .45*y = moving position. A Gaussian shoulder
        // preserves gradual illumination while the central band stays sharp.
        final scan = '(-.18+1.35*$phase)';
        final offset = '(X/W+.45*Y/H-$scan)';
        final narrow='exp(-pow($offset/.032,2))';
        final halo='exp(-pow($offset/.16,2))';
        mask(expr:'clip(255*(.03+.79*$halo+.18*$narrow),0,255)',
          foreground:"lutrgb=r='val*.74':g='min(255,val*1.00+15)':"
            "b='min(255,val*1.35+35)',eq=brightness=.17",
          base:'eq=brightness=-.31:contrast=.92');
        break;
      }
      case 'Shockwave': {
        final cx='(X/W-.36)', cy='((Y/H-.49)*1.20)';
        final angle='atan2($cy,$cx)';
        final r='sqrt(pow($cx,2)+pow($cy,2))';
        final ring='exp(-pow(($r-(.20+.55*$phase)'
          '*(1+.10*sin(9*$angle+6*$t)))/.033,2))';
        mask(expr:'clip(255*(.50*exp(-2.2*$phase)'
          '+.67*$ring*exp(-1.5*$phase)),0,255)',
          foreground:"lutrgb=r='min(255,val*1.25+60)':"
            "g='val*.68':b='val*.60',eq=brightness=.04",base:'null');
        break;
      }
      case 'Moon Off': {
        // Procedural sun/moon discs; unlike Unicode emoji these render with
        // the same geometry regardless of installed fonts on Android.
        final cX=(width*.27).round(), cY=(height*.52).round();
        final box=(width*.21).round();
        final sw = (width/4).round().clamp(96,224);
        final sh = (height*sw/width).round().clamp(96,400);
        final r = '(sqrt(pow((X/W-.27),2)+pow((Y/H-.52)*$height/$width,2)))';
        final fade='min(1,max(0,($s+$d*.84-T)/($d*.17)))';
        final sun = 'if(lt(T,$s+$d*.36),'
          'if(lt($r,.059),255*$fade,0),0)';
        final moon = 'if(gt(T,$s+$d*.36),'
          'if(lt($r,.059),255*$fade,0),0)';
        final visible='between(t,$s,${_f(startSeconds+(endSeconds-startSeconds)*.84)})';
        graph.add('[$input]split=3[${tag('base')}][${tag('sunSeed')}][${tag('moonSeed')}]');
        graph.add('[${tag('base')}]'
          "eq=brightness='-.36*min(1,max(0,(t-$s)/$d))':eval=frame,"
          'drawbox=x=${cX-box~/2}:y=${cY-box~/2}:w=$box:h=$box:'
          "c=0xF3CA77@.85:t=1:enable='$visible',"
          'drawbox=x=${cX-box~/2-18}:y=${cY-box~/2-22}:'
          "w=2:h=${box+44}:c=0xF3CA77@.85:t=fill:enable='$visible'"
          '[${tag('dim')}]');
        graph.add('[${tag('sunSeed')}]scale=$sw:$sh,format=gray,'
          "geq=lum='$sun',scale=$width:$height:flags=bicubic,"
          'format=gray[${tag('sunMask')}]');
        graph.add('[${tag('moonSeed')}]scale=$sw:$sh,format=gray,'
          "geq=lum='$moon',scale=$width:$height:flags=bicubic,"
          'format=gray[${tag('moonMask')}]');
        graph.add('[${tag('dim')}]split=3[${tag('plain')}][${tag('sunPaint')}][${tag('moonPaint')}]');
        graph.add('[${tag('sunPaint')}]drawbox=x=0:y=0:w=iw:h=ih:'
          'color=0xFFD044:t=fill[${tag('sunColour')}]');
        graph.add('[${tag('plain')}][${tag('sunColour')}][${tag('sunMask')}]'
          'maskedmerge[${tag('sunDone')}]');
        graph.add('[${tag('moonPaint')}]drawbox=x=0:y=0:w=iw:h=ih:'
          'color=0xF4EBCB:t=fill[${tag('moonColour')}]');
        graph.add('[${tag('sunDone')}][${tag('moonColour')}][${tag('moonMask')}]'
          'maskedmerge,format=yuv420p[$output]');
        break;
      }
      case 'Illusion': {
        graph.add('[$input]eq=brightness=.08:contrast=.75:saturation=.59,'
          'colorbalance=rs=.04:gs=.09:bs=.20,'
          'rgbashift=rh=5:bh=-6:rv=1:bv=-1,'
          'format=yuv420p[$output]');
        break;
      }
    }
    return graph;
  }
}
