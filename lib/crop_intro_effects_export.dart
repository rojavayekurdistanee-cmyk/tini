import 'dart:math' as math;

/// Native-independent FFmpeg graphs for the first Effects tab only.
/// Expressions are relative to the chosen effect span on the clip's output
/// timeline. Every chain preserves input frame dimensions and source audio.
class TiniIntroEffectsExport {
  static const category = 'مقدمة وخاتمة';
  static const supported = <String>{
    'Transform to Fall', 'Axis Rotation', 'Starry Zoom', 'Gradual Focusing',
    'Vertical Open', 'Horizontal Close', 'Low Exposure', 'Camera Focus 1',
    'Zoom In', 'Horizontal Open', 'The End', 'Switch Off', 'Switch On',
    'Shooting Frame', 'Countdown', 'Slip', 'Scroll', 'Rotate', 'Circle',
    'Vertical', 'Horizon',
  };

  static String _t(double number) => number.toStringAsFixed(5);

  static List<String> filterGraph({
    required String input,
    required String output,
    required String name,
    required String id,
    required double startSeconds,
    required double endSeconds,
    required int width,
    required int height,
    required int index,
  }) {
    if (!supported.contains(name)) {
      throw UnsupportedError('Missing intro effect: $name');
    }
    final duration = math.max(.1, endSeconds - startSeconds);
    final s = _t(startSeconds);
    final e = _t(endSeconds);
    final d = _t(duration);
    // T is the incoming frame timestamp in the blend filter; t is its
    // lowercase counterpart in filters such as rotate and drawtext.
    final p = 'min(max((T-$s)/$d,0),1)';
    final q = 'min(max((t-$s)/$d,0),1)';
    final n = 'ti${index}_';
    final graph = <String>[];

    void process(String chain) => graph.add('[$input]$chain[$output]');

    void twoWay(String chain, String mix) {
      graph.add('[$input]split=2[${n}source][${n}filter_input]');
      graph.add('[${n}filter_input]$chain[${n}filtered]');
      graph.add('[${n}source][${n}filtered]blend=all_expr=\'$mix\'[$output]');
    }

    void blackMask(String expression, {String? chromaExpression}) {
      graph.add('[$input]split=2[${n}original][${n}black_input]');
      graph.add('[${n}black_input]lut=y=16:u=128:v=128[${n}black]');
      if (chromaExpression == null) {
        graph.add('[${n}original][${n}black]blend=all_expr=\'$expression\'[$output]');
      } else {
        graph.add('[${n}original][${n}black]blend='
            'c0_expr=\'$expression\':c1_expr=\'$chromaExpression\':'
            'c2_expr=\'$chromaExpression\'[$output]');
      }
    }

    switch (name) {
      case 'Transform to Fall':
        process("rotate=a='0.32*$q':ow=iw:oh=ih:c=black,"
            "zoompan=z='1+0.26*min(max((on/30-$s)/$d,0),1)':"
            "x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':"
            'd=1:s=${width}x$height:fps=30,format=yuv420p');
        break;
      case 'Axis Rotation':
        // Three-dimensional-looking axis tilt with a restrained zoom.
        process("rotate=a='0.24*sin(3.141593*$q)':ow=iw:oh=ih:c=black,"
            "zoompan=z='1+0.18*sin(3.141593*min(max((on/30-$s)/$d,0),1))':"
            "x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':"
            'd=1:s=${width}x$height:fps=30,format=yuv420p');
        break;
      case 'Starry Zoom':
        final stars = [
          ('0.15*w+13*sin(7*t)', '0.16*h+9*cos(8*t)', '28'),
          ('0.75*w-12*sin(11*t)', '0.32*h', '35'),
          ('0.45*w+16*cos(9*t)', '0.67*h+11*sin(6*t)', '27'),
          ('0.8*w', '0.83*h+5*sin(13*t)', '19'),
        ];
        final overlay = stars.map((v) =>
            "drawtext=text='*':fontcolor=white@0.9:fontsize=${v.$3}:"
            "x='${v.$1}':y='${v.$2}':enable='between(t,$s,$e)'")
            .join(',');
        process("zoompan=z='1+0.30*min(max((on/30-$s)/$d,0),1)':"
            "x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':"
            'd=1:s=${width}x$height:fps=30,$overlay,format=yuv420p');
        break;
      case 'Gradual Focusing':
        twoWay('gblur=sigma=13,format=yuv420p', 'A*$p+B*(1-$p)');
        break;
      case 'Vertical Open':
        blackMask('if(lt(abs(X/W-0.5),0.5*$p),A,B)');
        break;
      case 'Horizontal Close':
        blackMask('if(lt(abs(Y/H-0.5),0.5*(1-$p)),A,B)');
        break;
      case 'Low Exposure':
        process("eq=brightness='-0.42*sin(3.141593*$q)':"
            'contrast=1.08:eval=frame');
        break;
      case 'Camera Focus 1':
        final side = math.max(2, (width * .004).round());
        final left = width ~/ 4;
        final top = height ~/ 4;
        final cornerW = width ~/ 9;
        final cornerH = height ~/ 13;
        final right = width - left - side;
        final bottom = height - top - side;
        final mark = <String>[
          'drawbox=x=$left:y=$top:w=$cornerW:h=$side:c=white@0.75:t=fill',
          'drawbox=x=$left:y=$top:w=$side:h=$cornerH:c=white@0.75:t=fill',
          'drawbox=x=${right - cornerW}:y=$top:w=$cornerW:h=$side:c=white@0.75:t=fill',
          'drawbox=x=$right:y=$top:w=$side:h=$cornerH:c=white@0.75:t=fill',
          'drawbox=x=$left:y=$bottom:w=$cornerW:h=$side:c=white@0.75:t=fill',
          'drawbox=x=$left:y=${bottom - cornerH}:w=$side:h=$cornerH:c=white@0.75:t=fill',
          'drawbox=x=${right - cornerW}:y=$bottom:w=$cornerW:h=$side:c=white@0.75:t=fill',
          'drawbox=x=$right:y=${bottom - cornerH}:w=$side:h=$cornerH:c=white@0.75:t=fill',
        ].join(',');
        process('$mark,format=yuv420p');
        break;
      case 'Zoom In':
        process("zoompan=z='1+0.58*min(max((on/30-$s)/$d,0),1)':"
            "x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':"
            'd=1:s=${width}x$height:fps=30,format=yuv420p');
        break;
      case 'Horizontal Open':
        final variantTwo = id.endsWith('#2');
        if (variantTwo) {
          // Alternate horizontal opening, with a narrower, delayed reveal.
          blackMask('if(lt(abs(Y/H-0.5),0.5*pow($p,1.9)),A,B)');
        } else {
          blackMask('if(lt(abs(Y/H-0.5),0.5*$p),A,B)');
        }
        break;
      case 'The End':
        // Shrinking iris with a narrow luminous rim, as in the reference.
        final radius = 'sqrt(pow(X/W-0.5,2)+pow(Y/H-0.5,2))';
        final edge = '0.72*(1-$p)';
        final y = 'if(lt($radius,$edge),A,'
            'if(lt(abs($radius-($edge)),0.025),142,B))';
        final uv = 'if(lt($radius,$edge),A,'
            'if(lt(abs($radius-($edge)),0.025),206,B))';
        blackMask(y, chromaExpression: uv);
        break;
      case 'Switch Off':
        final mask = 'if(gte($p,0.95),B,'
            'if(lt(abs(Y/H-0.5),0.5*pow(1-$p,3)),A,'
            'if(lt(abs(Y/H-0.5),0.008),235,B)))';
        blackMask(mask, chromaExpression: mask.replaceAll('235', '128'));
        break;
      case 'Switch On':
        final mask = 'if(lt(abs(Y/H-0.5),0.5*pow($p,0.7)),A,'
            'if(lt(abs(Y/H-0.5),0.008),235,B))';
        blackMask(mask, chromaExpression: mask.replaceAll('235', '128'));
        break;
      case 'Shooting Frame':
        final inset = math.max(6, width ~/ 13);
        final hInset = math.max(6, height ~/ 13);
        process('drawbox=x=$inset:y=$hInset:w=${width - 2 * inset}:'
            'h=${height - 2 * hInset}:c=white@0.75:t=2,'
            'drawbox=x=${width ~/ 2 - 12}:y=${height ~/ 2 - 1}:'
            'w=24:h=2:c=white@0.8:t=fill,'
            'drawbox=x=${width ~/ 2 - 1}:y=${height ~/ 2 - 12}:'
            'w=2:h=24:c=white@0.8:t=fill,format=yuv420p');
        break;
      case 'Countdown':
        // Explicit glyph intervals avoid reliance on metadata/animation assets.
        final third = duration / 3;
        final numberSize = math.max(48, (height * .22).round());
        process([for (var i = 0; i < 3; i++)
          "drawtext=text='${3 - i}':fontcolor=white:fontsize=$numberSize:"
          "x='(w-text_w)/2':y='(h-text_h)/2':"
          "enable='between(t,${_t(startSeconds + third * i)},"
          "${_t(startSeconds + third * (i + 1))})'"
        ].join(',') + ',format=yuv420p');
        break;
      case 'Slip':
        process("crop=w='iw*0.84':h='ih*0.92':"
            "x='(iw-out_w)*(0.5+0.45*sin(6.283185*(t-$s)/$d))':"
            "y='(ih-out_h)/2',scale=$width:$height,format=yuv420p");
        break;
      case 'Scroll':
        process('scroll=vertical=0.38:horizontal=0,format=yuv420p');
        break;
      case 'Rotate':
        process("rotate=a='6.283185*$q':ow=iw:oh=ih:c=black,"
            'format=yuv420p');
        break;
      case 'Circle':
        blackMask('if(lt(sqrt(pow(X/W-0.5,2)+pow(Y/H-0.5,2)),'
            '0.72*$p),A,B)');
        break;
      case 'Vertical':
        process('scroll=vertical=-0.44:horizontal=0,format=yuv420p');
        break;
      case 'Horizon':
        process('scroll=horizontal=-0.44:vertical=0,format=yuv420p');
        break;
    }
    return graph;
  }
}
