import 'dart:math' as math;

/// Video-effect graphs for the "أساسية" tab. No network, assets or native
/// plugin is needed. Each recipe preserves frame size and leaves audio alone.
/// All temporal expressions use the clip's OUTPUT timeline (post speed edit).
class TiniBasicEffectsExport {
  static const category = 'أساسية';

  static const supported = <String>{
    'Chrome Blur', 'Screenshot ...', 'Chromatic A...', 'Noise',
    'Halo Blur', 'Hazy', 'Rotary Focus', 'Vertical Blur',
    'Zoom Lens', 'Blurry Focus', 'Blur Close', 'Rebound Swi...',
    'Vignette', 'Blur', 'Fisheye III', 'Diamond Zoo...',
    'Motion Blur', 'Magnifying ...', 'Mini Zoom', 'Slanted Blur',
    'TV Jitter', 'Window', 'Zoom', 'Background ...', 'HDR', 'Zoom Sketch',
  };

  // zoompan emits one 30-fps frame per source frame. Both sides of the
  // time-limited blend must use the same frame rate and timestamps.
  static const frameRateDependent = <String>{
    'Zoom Lens', 'Rebound Swi...', 'Mini Zoom', 'Zoom', 'Zoom Sketch',
  };

  static String _number(double n) => n.toStringAsFixed(5);

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
      throw UnsupportedError('Unsupported Basic effect: $name');
    }
    final duration = math.max(0.1, endSeconds - startSeconds);
    final s = _number(startSeconds);
    final d = _number(duration);
    // q is evaluated by per-frame filters; p is evaluated by blend (T).
    final q = 'min(max((t-$s)/$d,0),1)';
    final p = 'min(max((T-$s)/$d,0),1)';
    final n = 'tb${index}_';
    final graph = <String>[];

    void process(String filters) => graph.add('[$input]$filters,format=yuv420p[$output]');

    // Blend two identical-clock streams using time and/or pixel coordinates.
    void spatial(String filters, String expression) {
      graph.add('[$input]split=2[${n}original][${n}processing]');
      graph.add('[${n}processing]$filters,format=yuv420p[${n}processed]');
      graph.add('[${n}original][${n}processed]'
          "blend=all_expr='$expression'[$output]");
    }

    String zoom({required double from, required double amount, double waves = 0}) {
      final frameProgress = 'min(max((on/30-$s)/$d,0),1)';
      final z = waves == 0
          ? '${_number(from)}+${_number(amount)}*$frameProgress'
          : '${_number(from)}+${_number(amount)}*sin(3.14159265*$frameProgress)'
              '+${_number(waves)}*sin(12.56637061*$frameProgress)';
      return "zoompan=z='$z':x='iw/2-iw/zoom/2':"
          "y='ih/2-ih/zoom/2':d=1:s=${width}x$height:fps=30";
    }

    switch (name) {
      case 'Chrome Blur':
        process('gblur=sigma=2.2,rgbashift=rh=4:bh=-5,eq=saturation=1.18');
        break;
      case 'Screenshot ...':
        // Photo-capture flash followed by a bright, framed frozen-looking view.
        final inset = math.max(5, (width * .06).round());
        process("eq=brightness='0.24*exp(-16*abs(t-$s-$d*0.35))':eval=frame,"
            'drawbox=x=$inset:y=$inset:w=iw-2*$inset:h=ih-2*$inset:'
            'c=white@0.72:t=3');
        break;
      case 'Chromatic A...':
        process('rgbashift=rh=9:rv=-3:bh=-10:bv=4,eq=contrast=1.15:saturation=1.45');
        break;
      case 'Noise':
        process('noise=alls=42:allf=t+u');
        break;
      case 'Halo Blur':
        spatial('gblur=sigma=9,eq=brightness=0.09', 'min(255,A*0.75+B*0.35)');
        break;
      case 'Hazy':
        process('gblur=sigma=2.8,eq=contrast=0.68:saturation=0.78:brightness=0.10');
        break;
      case 'Rotary Focus':
        process("rotate=a='0.13*sin(6.283185*$q)':ow=iw:oh=ih:c=black,"
            'gblur=sigma=1.3');
        break;
      case 'Vertical Blur':
        process('avgblur=sizeX=1:sizeY=17');
        break;
      case 'Zoom Lens':
        process('${zoom(from: 1.02, amount: 0.49)},vignette=angle=PI/2.3');
        break;
      case 'Blurry Focus':
        spatial('gblur=sigma=12',
            'if(lt(pow((X/W-0.5)/0.38,2)+pow((Y/H-0.5)/0.39,2),1),A,B)');
        break;
      case 'Blur Close':
        spatial('gblur=sigma=16', 'A*(1-$p)+B*$p');
        break;
      case 'Rebound Swi...':
        process(zoom(from: 1.08, amount: 0.33, waves: 0.08));
        break;
      case 'Vignette':
        process('vignette=angle=PI/3.5');
        break;
      case 'Blur':
        process('gblur=sigma=11');
        break;
      case 'Fisheye III':
        process('lenscorrection=cx=0.5:cy=0.5:k1=-0.48:k2=0.14');
        break;
      case 'Diamond Zoo...':
        spatial('crop=iw*0.61:ih*0.61,scale=$width:$height',
            'if(lt(abs(X/W-0.5)+abs(Y/H-0.5),0.18+0.42*$p),B,A)');
        break;
      case 'Motion Blur':
        process('tmix=frames=4:weights=1 2 3 4');
        break;
      case 'Magnifying ...':
        spatial('crop=iw*0.54:ih*0.54,scale=$width:$height',
            'if(lt(pow(X/W-0.5,2)+pow(Y/H-0.5,2),0.09),B,A)');
        break;
      case 'Mini Zoom':
        process(zoom(from: 1.02, amount: 0.15));
        break;
      case 'Slanted Blur':
        process("gblur=sigma=5,rotate=a='0.035*sin(6.283185*$q)':"
            'ow=iw:oh=ih:c=black');
        break;
      case 'TV Jitter':
        process('noise=alls=23:allf=t,rgbashift=rh=6:bh=-5,'
            "crop=w=iw*0.96:h=ih*0.96:x='(iw-out_w)*(0.5+0.44*sin(n*1.73))':"
            "y='(ih-out_h)*(0.5+0.44*cos(n*1.19))',scale=$width:$height");
        break;
      case 'Window':
        final innerW = math.max(2, ((width * .81).round() ~/ 2) * 2);
        final innerH = math.max(2, ((height * .81).round() ~/ 2) * 2);
        process('scale=$innerW:$innerH,pad=$width:$height:(ow-iw)/2:(oh-ih)/2:black,'
            'drawbox=x=0:y=0:w=iw:h=ih:c=white@0.17:t=3');
        break;
      case 'Zoom':
        process(zoom(from: 1.02, amount: 0.76));
        break;
      case 'Background ...':
        // The source video forms the subject plane over a softened backdrop;
        // unlike segmentation this deliberately keeps a rectangular foreground.
        final innerW = math.max(2, ((width * .75).round() ~/ 2) * 2);
        final innerH = math.max(2, ((height * .75).round() ~/ 2) * 2);
        graph.add('[$input]split=2[${n}bg][${n}fg]');
        graph.add('[${n}bg]gblur=sigma=17,eq=brightness=-0.09[${n}blur]');
        graph.add('[${n}fg]scale=$innerW:$innerH[${n}center]');
        graph.add('[${n}blur][${n}center]overlay=(W-w)/2:(H-h)/2,'
            'format=yuv420p[$output]');
        break;
      case 'HDR':
        process('eq=contrast=1.31:saturation=1.23:gamma=1.07,'
            'unsharp=5:5:0.67:5:5:0');
        break;
      case 'Zoom Sketch':
        graph.add('[$input]split=2[${n}base][${n}edge]');
        graph.add('[${n}edge]edgedetect=low=0.06:high=0.23,'
            'negate,eq=contrast=1.28[${n}sketch]');
        graph.add('[${n}base][${n}sketch]blend=all_opacity=0.68[${n}composite]');
        graph.add('[${n}composite]${zoom(from: 1.02, amount: 0.37)},'
            'format=yuv420p[$output]');
        break;
    }
    return graph;
  }
}
