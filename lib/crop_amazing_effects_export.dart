import 'dart:math' as math;

/// Dedicated FFmpeg graphs for the first eight 'Amazing' reference items.
/// The input/output timestamps and frame size are preserved. The editor's
/// existing interval blend applies each result only within its selected span.
class TiniAmazingEffectsExport {
  static const category = 'مذهلة';
  static const supported = <String>{
    'H2L Text', '2026 Loading', 'Disco Count', 'Love Window',
    'Negative Gra...', 'Fire-Hot', 'Lyric Cut', 'Octopus End',
  };

  // Same normalized finger path and timing as the Flutter preview.
  static const _loveStrokes = <List<(double, double)>>[
    [
      (0.345, 0.267),
      (0.323, 0.249),
      (0.294, 0.249),
      (0.264, 0.272),
      (0.246, 0.311),
      (0.226, 0.362),
      (0.201, 0.429),
      (0.217, 0.444),
      (0.254, 0.448),
      (0.298, 0.436),
      (0.347, 0.410),
      (0.367, 0.394),
    ],
    [
      (0.397, 0.388),
      (0.419, 0.366),
      (0.456, 0.365),
      (0.484, 0.388),
      (0.482, 0.410),
      (0.462, 0.430),
      (0.434, 0.433),
      (0.412, 0.416),
      (0.413, 0.394),
      (0.442, 0.371),
      (0.483, 0.383),
    ],
    [
      (0.490, 0.374),
      (0.507, 0.402),
      (0.528, 0.433),
      (0.552, 0.406),
      (0.581, 0.361),
    ],
    [
      (0.601, 0.403),
      (0.633, 0.385),
      (0.676, 0.364),
      (0.698, 0.373),
      (0.683, 0.394),
      (0.640, 0.408),
      (0.652, 0.426),
      (0.694, 0.429),
      (0.730, 0.414),
      (0.758, 0.392),
    ],
    [
      (0.205, 0.467),
      (0.262, 0.464),
      (0.332, 0.465),
      (0.409, 0.467),
      (0.489, 0.471),
      (0.568, 0.469),
      (0.649, 0.464),
      (0.729, 0.459),
      (0.801, 0.454),
    ],
  ];

  static const _loveStages = <double>[0.0, .23, .42, .57, .82, 1.0];

  // A small dynamic greyscale reveal mask traces the real strokes over time.
  // This avoids an instantly visible, static drawtext('Love') in the export.
  // Sample at constant screen-space spacing so tall and wide clips behave alike.
  static List<String> _loveMaskExpressions({required double startSeconds,
      required double duration, required int width, required int height}) {
    final marks = <String>[];
    final ratio = height / width;
    for (var stroke=0; stroke<_loveStrokes.length; stroke++) {
      final points = _loveStrokes[stroke];
      final from = _loveStages[stroke];
      final span = _loveStages[stroke+1] - from;
      final lengths = <double>[];
      var total = 0.0;
      for (var i=0; i<points.length-1; i++) {
        final dx = points[i+1].$1 - points[i].$1;
        final dy = (points[i+1].$2 - points[i].$2) * ratio;
        final length = math.sqrt(dx*dx + dy*dy);
        lengths.add(length);
        total += length;
      }
      var drawn = 0.0;
      for (var i=0; i<lengths.length; i++) {
        final x1=points[i].$1, y1=points[i].$2;
        final x2=points[i+1].$1, y2=points[i+1].$2;
        final steps = math.max(1, (lengths[i] / .033).ceil());
        for (var k=(i==0 ? 0 : 1); k<=steps; k++) {
          final fraction=k/steps;
          final x=x1+(x2-x1)*fraction, y=y1+(y2-y1)*fraction;
          final progress = from + span*(drawn+lengths[i]*fraction)/total;
          final at = startSeconds + duration * math.min(progress,.999);
          // Brush is ~3.7% of the image width in both implementations.
          marks.add('gte(T,${_f(at)})*lt(hypot(X/W-${_f(x)},'
            '(Y/H-${_f(y)})*H/W),.019)');
        }
        drawn += lengths[i];
      }
    }
    // FFmpeg's expression evaluator has a bounded AST depth. Partition the
    // stamped mask into small independent passes to avoid parser overflow.
    const perPass = 42;
    return [for (var i=0; i<marks.length; i+=perPass)
      '255*min(1,${marks.skip(i).take(perPass).join('+')})'];
  }

  static String _f(double n) => n.toStringAsFixed(5);

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
      throw UnsupportedError('Amazing effect is not implemented: $name');
    }
    final s = _f(startSeconds);
    final d = _f(math.max(.10, endSeconds - startSeconds));
    final n = 'ta${index}_';
    final graph = <String>[];
    final q = '(t-$s)';
    final p = '(T-$s)';

    // 'drawtext' is used for actual animated lettering, not a substituted
    // generic blur. This filter is already required by the Intro/Outro tab.
    String words(String text, int size, String x, String y,
        {String color = 'white', String? enable, String extra = ''}) {
      return "drawtext=text='$text':fontsize=$size:fontcolor=$color:"
          "x='$x':y='$y'${enable == null ? '' : ":enable='$enable'"}$extra";
    }

    void process(List<String> filters) => graph.add(
      '[$input]${filters.join(',')},format=yuv420p[$output]');

    switch (name) {
      case 'H2L Text': {
        final font = math.max(20, (width * .120).round());
        final move = 'h*.155+8*sin(($q)*5)';
        final beats = <(String, double, double, String, String)>[
          ('DON’T',0,.98,'(w-text_w)/2', move),
          ('GET ME',.38,1.10,'(w-text_w)/2','h*.235'),
          ('GOING',.82,1.55,'(w-text_w)/2','h*.315'),
          ('I STILL',1.55,3.0,'(w-text_w)/2',move),
        ];
        process([for (final beat in beats)
          words(beat.$1, font, beat.$4, beat.$5,
            enable: 'between(mod($q,3),${beat.$2},${beat.$3})',
            extra: ':borderw=1:bordercolor=white@0.6')]);
        break;
      }
      case '2026 Loading': {
        final left = (width * .07).round();
        final top = (height * .085).round();
        final rectWidth = (width * .86).round();
        final rectHeight = math.max(12, (height * .032).round());
        // Custom blend evaluates progress once per frame. Unlike drawbox's
        // dimension options (which are init-only) this really fills over time.
        graph.add('[$input]drawbox=x=$left:y=$top:w=$rectWidth:'
          'h=$rectHeight:c=black@0.90:t=fill,'
          'drawbox=x=${(width*.177).round()}:y=${(height*.09).round()}:'
          'w=${(width*.645).round()}:h=${(height*.024).round()}:'
          'c=white:t=2,format=yuv420p[${n}base]');
        graph.add('[${n}base]split=2[${n}bar][${n}white_src]');
        graph.add('[${n}white_src]lut=y=235:u=128:v=128[${n}white]');
        final within = 'between(X/W,.183,(.183+.634*'
          'min(1,max(0,$p/$d))))*between(Y/H,.098,.107)';
        graph.add('[${n}bar][${n}white]blend='
          "c0_expr='if($within,B,A)':"
          "c1_expr='if($within,B,A)':"
          "c2_expr='if($within,B,A)'[${n}filled]");
        final tagFont = math.max(10,(width*.033).round());
        processText(label: '${n}filled', output: output, graph: graph,
          filters: [words('2025',tagFont,'w*.081','h*.092',extra:':borderw=0'),
            words('2026',tagFont,'w*.84','h*.092'),
            words('Loading...',tagFont,'(w-text_w)/2','h*.125',color:'black')]);
        break;
      }
      case 'Disco Count': {
        final font = math.max(36,(width*.31).round());
        final filters=<String>[];
        // Exactly six numbers: 10, 9, 8, 7, 6, 5.
        // Each receives one sixth of the selected effect interval.
        final duration=endSeconds-startSeconds;
        for (var i=0;i<6;i++) {
          final digit = '${10-i}';
          final begin=_f(startSeconds + duration*i/6);
          final finish=_f(startSeconds + duration*(i+1)/6);
          final enabled='gte(t,$begin)*lt(t,$finish)';
          filters.add(words(digit,font,'(w-text_w)/2+w*.017','h*.128+h*.009',
            color:'black@0.9',enable:enabled,
            extra: ':borderw=5:bordercolor=black@0.7'));
          filters.add(words(digit,font,'(w-text_w)/2','h*.128',
            color:'0xCCD6E2',enable:enabled,
            extra: ':borderw=3:bordercolor=0x596575:'
                'shadowcolor=white@0.85:shadowx=-2:shadowy=-2'));
          filters.add(words('✦', math.max(14,font~/6),
            'w*.70+7*sin(t*8)','h*.128',color:'white@0.85',enable:enabled));
        }
        process(filters);
        break;
      }
      case 'Love Window': {
        // Frost remains visible. As the finger traces L, o, v and e, the
        // original moving video is revealed through the newly cleared tracks.
        // Only after the word is complete is the underline progressively drawn.
        final sw=math.min(144,math.max(96,width~/4));
        final sh=math.max(96,(height/width*sw).round());
        final reveal=_loveMaskExpressions(startSeconds:startSeconds,
          duration:endSeconds-startSeconds,width:width,height:height);
        graph.add('[$input]split=3[${n}source][${n}fog][${n}mask_in]');
        graph.add('[${n}fog]gblur=sigma=16,'
          'eq=brightness=0.18:contrast=0.64:saturation=0.28,'
          'noise=alls=7:allf=t,format=yuv420p[${n}frosted]');
        final inputs = [for (var i=0; i<reveal.length; i++) '${n}part$i'];
        graph.add('[${n}mask_in]scale=$sw:$sh:flags=bilinear,format=gray,'
          'split=${reveal.length}${[for (final x in inputs) '[$x]'].join()}');
        for (var i=0; i<reveal.length; i++) {
          graph.add("[${inputs[i]}]geq=lum='${reveal[i]}'[${n}mark$i]");
        }
        var combined = '${n}mark0';
        for (var i=1; i<reveal.length; i++) {
          final merged = '${n}merged$i';
          graph.add('[$combined][${n}mark$i]blend=all_mode=lighten[$merged]');
          combined = merged;
        }
        graph.add('[$combined]gblur=sigma=0.7,'
          'scale=$width:$height:flags=bicubic,format=gray[${n}letter_mask]');
        graph.add('[${n}frosted][${n}source][${n}letter_mask]'
          'maskedmerge,format=yuv420p[$output]');
        break;
      }
      case 'Negative Gra...': {
        graph.add('[$input]split=2[${n}source][${n}negative_input]');
        graph.add('[${n}negative_input]negate,eq=contrast=1.52:'
          'saturation=1.42,rgbashift=rh=9:bh=-8,'
          'noise=alls=18:allf=t[${n}negative]');
        final noiseStripe = 'lt(mod(Y/H*28+sin($p*19)*3,4),2.8)*'
          'lt(mod(X/W*12+$p*13,5),4.2)';
        graph.add('[${n}negative][${n}source]blend='
          "all_expr='if($noiseStripe,A,B)'[${n}stripes]");
        processText(label:'${n}stripes', output:output, graph:graph, filters:[
          'rgbashift=rh=7:bh=-6',
          'eq=contrast=1.18:saturation=1.33',
        ]);
        break;
      }
      case 'Fire-Hot': {
        // Render the burn geometry at low resolution, then upscale its mask.
        // Full-resolution per-pixel trigonometry would be prohibitively slow
        // on typical Android devices, especially on long segments.
        final sw = math.min(192, math.max(96, width ~/ 4));
        final sh = math.max(120, (height / width * sw).round());
        graph.add('[$input]split=3[${n}source][${n}paper_in][${n}mask_in]');
        String dist(String cx, String cy, String ry, String seed) =>
          'sqrt(pow((X/W-$cx)*1.2,2)+pow((Y/H-$cy)*$ry,2))'
          '+.028*sin(X/W*47+Y/H*39+$p*2+$seed)';
        final burn = 'min(min(${dist('.48','.38','.85','1')},'
          '${dist('.35','.66','1.0','3')}),'
          '${dist('.67','.53','1.3','6')})';
        final progress = '(.035+.18*min(1,max(0,$p/$d)))';
        final ember = 'exp(-pow(($burn-$progress)/.022,2))';
        final soot = 'exp(-pow(($burn-$progress-.028)/.014,2))';
        graph.add('[${n}paper_in]scale=$sw:$sh,format=gbrp,'
          "geq=r='clip(247-31*$soot,0,255)':"
          "g='clip(243-122*$ember-52*$soot,0,255)':"
          "b='clip(234-193*$ember-46*$soot,0,255)',"
          'scale=$width:$height:flags=bicubic,format=yuv420p[${n}paper]');
        graph.add('[${n}mask_in]scale=$sw:$sh,format=gray,'
          "geq=lum='if(lt($burn,$progress),255,0)',"
          'scale=$width:$height:flags=bicubic,format=gray[${n}mask]');
        graph.add('[${n}paper][${n}source][${n}mask]'
          'maskedmerge,format=yuv420p[$output]');
        break;
      }
      case 'Lyric Cut': {
        final lineFont=math.max(25,(width*.20).round());
        final lines=<String>['LIFE','IS','GREAT','JUST','GOTTA'];
        final filters=<String>[
          'eq=brightness=-0.36:contrast=1.1:saturation=0.38',
        ];
        for(var i=0;i<lines.length;i++) {
          final begin=_f(startSeconds + i*.46);
          final finish=_f(math.min(endSeconds,startSeconds+(i+1)*.46));
          if(double.parse(begin)>=double.parse(finish)) break;
          filters.add(words(lines[i],lineFont,'(w-text_w)/2','h*.50',
            color: i == 1 ? '0xFFE057' : i == 2 ? '0x50FFD6' : 'white',
            enable:'between(mod($q,2.30),${_f(i*.46)},${_f((i+1)*.46)})',
            extra: ':borderw=1:bordercolor=white@0.2'));
        }
        process(filters);
        break;
      }
      case 'Octopus End': {
        // The reference repeats a complete tentacle motion: open -> close ->
        // hold -> reopen. Suckers and irregular opening share the same moving
        // radius in the preview and FFmpeg, rather than rendering a still ring.
        // Work at a reduced scale for predictable mobile CPU consumption.
        final sw = math.min(136, math.max(96, width ~/ 7));
        final sh = math.max(120, (height / width * sw).round());
        final aspect = height / width;
        final openRadius = math.sqrt(.505*.505 +
            math.pow(.52 * aspect, 2)) + .19;
        const closedRadius = .365;
        final selectedDuration = math.max(.10, endSeconds - startSeconds);
        final rate = 3.36 / math.min(3.36, selectedDuration);
        final localTime = '(max(0,T-$s)*${_f(rate)})';
        final period = 'mod($localTime,3.36)';
        // FFmpeg's expression registers are local to an evaluation. Sharing
        // these values inside a channel avoids re-evaluating large subtrees.
        final prefix = <String>[
          'st(0,$period)',
          'st(1,if(lt(ld(0),.88),.5-.5*cos(PI*ld(0)/.88),'
            'if(lt(ld(0),2.55),1,'
            'if(lt(ld(0),3.16),.5+.5*cos(PI*(ld(0)-2.55)/.61),0))))',
          'st(2,$closedRadius+(${_f(openRadius)}-$closedRadius)*(1-ld(1)))',
          'st(3,atan2((Y/H-.48)*H/W,X/W-.505))',
          'st(4,hypot(X/W-.505,(Y/H-.48)*H/W))',
          'st(5,1+.027*sin(4*ld(3)+$localTime*1.25)'
            '+.014*sin(7*ld(3)-$localTime*.9))',
          'st(6,max(0,floor((ld(4)-ld(2)-.055)/.26+.5)))',
          'st(7,2*PI/if(lt(ld(6),.5),18,8+4*ld(6)))',
          'st(8,floor((ld(3)-.14*mod(ld(6),2)'
            '-.033*sin($localTime*1.8+ld(6)))/ld(7)+.5)*ld(7)'
            '+.14*mod(ld(6),2)'
            '+.033*sin($localTime*1.8+ld(6)))',
          'st(9,hypot(ld(4)-(ld(2)+.055+.26*ld(6))'
            '*(1+.027*sin(4*ld(8)+$localTime*1.25)'
            '+.014*sin(7*ld(8)-$localTime*.9)),'
            '(ld(3)-ld(8))*(ld(2)+.055+.26*ld(6))))',
        ].join(';');
        String channel(int cavity, int inner, int coral, int lilac,
            int shadow, String background) =>
          '$prefix;'
          'if(gt(ld(6),4),$background,'
          'if(lt(ld(9),.017),$cavity,'
          'if(lt(ld(9),.027),$inner,'
          'if(lt(ld(9),.039),$coral,'
          'if(lt(ld(9),.048),$lilac,'
          'if(lt(ld(9),.059),$shadow,$background))))))';
        final glow = 'exp(-pow((X/W-.42)/.83,2)-pow((Y/H-.40)/.73,2))';
        final ripple = 'sin(Y/H*16+1.2*sin(X/W*10+$localTime*.35))';
        final red = channel(48,183,250,137,50,'49+56*$glow+8*$ripple');
        final green = channel(18,67,144,57,17,'12+28*$glow+4*$ripple');
        final blue = channel(79,113,136,174,87,'74+64*$glow+6*$ripple');
        // Only the mask and edge, not the source video, are changed to reveal
        // the underlying live video as the hole opens. Work in RGB to avoid
        // the violet/pink colour pollution observed with planar YUV blending.
        graph.add('[$input]split=4[${n}video][${n}body_in]'
          '[${n}mask_in][${n}rim_in]');
        graph.add('[${n}body_in]scale=$sw:$sh:flags=bilinear,format=gbrp,'
          "geq=r='clip($red,0,255)':g='clip($green,0,255)':"
          "b='clip($blue,0,255)',"
          'scale=$width:$height:flags=bicubic,format=gbrp[${n}body]');
        graph.add('[${n}video]format=gbrp[${n}rgb_video]');
        graph.add('[${n}body]split=2[${n}body_back][${n}body_front]');
        graph.add('[${n}mask_in]scale=$sw:$sh,format=gray,'
          "geq=lum='$prefix;if(lt(ld(4),ld(2)*ld(5)),255,0)',"
          'scale=$width:$height:flags=bicubic,format=gbrp[${n}window]');
        graph.add('[${n}rim_in]scale=$sw:$sh,format=gray,'
          "geq=lum='$prefix;if(lt(abs(ld(4)-ld(2)*ld(5)),.043)"
          "+lt(ld(6),.5)*lt(ld(9),.059),255,0)',"
          'scale=$width:$height:flags=bicubic,format=gbrp[${n}rim_mask]');
        graph.add('[${n}body_back][${n}rgb_video][${n}window]'
          'maskedmerge[${n}open_video]');
        graph.add('[${n}open_video][${n}body_front][${n}rim_mask]'
          'maskedmerge,format=yuv420p[$output]');
        break;
      }
    }
    return graph;
  }

  static void processText({required String label, required String output,
      required List<String> graph, required List<String> filters}) {
    graph.add('[$label]${filters.join(',')},format=yuv420p[$output]');
  }
}
