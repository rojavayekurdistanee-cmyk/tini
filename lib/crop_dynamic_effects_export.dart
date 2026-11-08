/// Reference-led FFmpeg recipes for the Dynamic tab.
/// The input clip is never overwritten. TiniEffectsRender composites each
/// result only within its recorded interval, retaining other effect categories.
class TiniDynamicEffectsExport {
  static const category = 'ديناميكية';

  // The final reference row repeats Shake; one catalogue entry is intentional.
  static const supported = <String>{
    'Disco', 'Club Mood', 'Club lights', 'Orange Nega...',
    'Shake + Scre...', 'Shaky Camer...', 'Shake 1', 'Shake 2', 'Shake',
    'Trembling', 'Colorful', 'RGB Border', 'Neon', 'Chromatic', 'Delay',
    'Stuck Frame', 'Flash II', 'Flash I', 'Black Flash II', 'Black Flash',
    'White Flash', 'Flicker', 'Chromo-zoom', 'Astral', 'Unreal II', 'ظل',
    'Bounce Cam...', 'Play Pendulu...', 'Throb', 'Beat', 'Pulse', 'Strobe',
    'Sway', 'Soul', 'Flash',
  };

  // zoompan generates frames at 30 fps. The parent graph must normalize the
  // source clock before branching, including for mixed temporal effects.
  static const frameRateDependent = <String>{
    'Chromo-zoom', 'Bounce Cam...', 'Throb', 'Pulse', 'Club lights',
    'Club Mood',
    'Stuck Frame', 'Delay', 'Astral', 'ظل', 'Soul',
  };

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
      throw UnsupportedError('Unsupported Dynamic effect: $name');
    }
    final s = startSeconds.toStringAsFixed(5);
    final phase = '(t-$s)';
    final framePhase = '(on/30-$s)';
    final n = 'td${index}_';
    final graph = <String>[];
    void process(String filters) =>
        graph.add('[$input]$filters,format=yuv420p[$output]');

    void mixed(String branch, String blend) {
      graph.add('[$input]split=2[${n}base][${n}work]');
      graph.add('[${n}work]$branch,format=yuv420p[${n}changed]');
      graph.add('[${n}base][${n}changed]'
          "blend=all_expr='$blend',format=yuv420p[$output]");
    }

    String zoom(double base, double amplitude, String motion,
        {String y = 'ih/2-ih/zoom/2'}) =>
      "zoompan=z='${base.toStringAsFixed(3)}+${amplitude.toStringAsFixed(3)}*($motion)':"
      "x='iw/2-iw/zoom/2':y='$y':d=1:s=${width}x$height:fps=30";

    // Crop coordinates use normalized room to avoid black sidebars. Motion is
    // phase-locked to the selected interval rather than the global video time.
    String shake({required double crop, required String x, required String y}) =>
      "crop=w=iw*${crop.toStringAsFixed(3)}:h=ih*${crop.toStringAsFixed(3)}:"
      "x='(iw-out_w)*($x)':y='(ih-out_h)*($y)',scale=$width:$height";

    // An evolving, bounded pulse prevents every flash variant from having the
    // same sine-wave rhythm. FFmpeg's eq evaluates brightness per video frame.
    String light(String expr) => "eq=brightness='$expr':eval=frame";

    switch (name) {
      case 'Disco':
        process("colorize=hue=295:saturation=0.70:mix=0.55,"
            "eq=contrast=1.13:brightness='0.02+0.08*sin($phase*7.2)':eval=frame");
        break;
      case 'Club Mood':
        mixed('tmix=frames=4:weights=1 2 2 3,'
            'colorize=hue=245:saturation=0.40:mix=0.70,gblur=sigma=2.5',
            'min(255,A*0.38+B*0.71)');
        break;
      case 'Club lights':
        // Moving tapered spotlights, rather than the former purple colour wash.
        // geq works in the YCbCr planes and follows decoded frame index N.
        process("eq=contrast=1.07:saturation=1.12,"
            "geq=lum='min(255,lum(X,Y)+"
            "117*exp(-pow((X/W-(0.18+0.33*sin(N*0.055)+Y/H*0.23)),2)/0.009)+"
            "95*exp(-pow((X/W-(0.82-0.32*sin(N*0.044+1.4)-Y/H*0.26)),2)/0.013))':"
            "cb='cb(X,Y)':cr='cr(X,Y)'");
        break;
      case 'Orange Nega...':
        process('negate,colorize=hue=15:saturation=0.72:mix=0.50,'
            'eq=contrast=1.35:saturation=1.50');
        break;
      case 'Shake + Scre...':
        process('${shake(crop: .77, x: '0.5+0.43*sin($phase*35)*sin($phase*9)', y: '0.5+0.38*cos($phase*27)')},'
            "rgbashift=rh=5:bh=-5,gblur=sigma=3.0,"
            "eq=contrast=1.18:brightness='0.16*pow(max(0,sin($phase*7.5)),8)':eval=frame");
        break;
      case 'Shaky Camer...':
        process('${shake(crop: .79, x: '0.5+0.44*sin($phase*13.1)+0.05*sin($phase*43)', y: '0.5+0.40*cos($phase*16.2)')},'
            'gblur=sigma=2.1');
        break;
      case 'Shake 1':
        process('${shake(crop: .80, x: '0.5+0.46*sin($phase*19)*sin($phase*6)', y: '0.5+0.16*sin($phase*11)')},'
            'gblur=sigma=1.3');
        break;
      case 'Shake 2':
        process('${shake(crop: .75, x: '0.5+0.20*sin($phase*9)', y: '0.5+0.47*sin($phase*15.5)')},'
            'eq=contrast=1.06');
        break;
      case 'Shake':
        process(shake(crop: .82,
            x: '0.5+0.42*sin($phase*26)*pow(max(0,sin($phase*4.3)),4)',
            y: '0.5+0.34*cos($phase*22)*pow(max(0,sin($phase*4.3)),4)'));
        break;
      case 'Trembling':
        process('${shake(crop: .975, x: '0.5+0.47*sin($phase*80)', y: '0.5+0.47*cos($phase*74)')},'
            'unsharp=5:5:0.7:5:5:0');
        break;
      case 'Colorful':
        process("colorbalance=rs=0.57:gs=0.26:bs=-0.53,"
            "hue=h='16*sin($phase*1.7)':s=1.68,"
            'eq=contrast=1.27:gamma_r=1.13:gamma_b=0.88');
        break;
      case 'RGB Border':
        process('drawbox=x=0:y=0:w=iw:h=ih:c=0x2459ff@0.7:t=17,'
            'drawbox=x=7:y=7:w=iw-14:h=ih-14:c=0x915dff@0.8:t=6,'
            'drawbox=x=13:y=13:w=iw-26:h=ih-26:c=0x6ae0ff@0.95:t=3');
        break;
      case 'Neon':
        process('eq=contrast=1.04:saturation=1.14,'
            'drawbox=x=0:y=0:w=iw:h=ih:c=0xfd294d@0.38:t=30,'
            'drawbox=x=7:y=7:w=iw-14:h=ih-14:c=0xff536c@0.92:t=7,'
            'drawbox=x=16:y=16:w=iw-32:h=ih-32:c=0xffbfd4@0.77:t=2');
        break;
      case 'Chromatic':
        process('rgbashift=rh=13:rv=-3:gh=-1:bh=-13:bv=4,'
            'eq=saturation=1.19:contrast=1.09');
        break;
      case 'Delay':
        process('tmix=frames=7:weights=1 1 1 2 2 3 4');
        break;
      case 'Stuck Frame':
        process('fps=4:round=near,fps=30:round=near');
        break;
      case 'Flash II':
        process(light('0.50*gt(sin($phase*11.8),0.52)+0.14*gt(sin($phase*23.6),0.82)'));
        break;
      case 'Flash I':
        process(light('0.52*pow(max(0,sin($phase*5.0)),18)'));
        break;
      case 'Black Flash II':
        process(light('-0.72*gt(sin($phase*18.5),0.18)'));
        break;
      case 'Black Flash':
        process(light('-0.82*gt(sin($phase*5.1),0.35)'));
        break;
      case 'White Flash':
        process(light('0.88*pow(max(0,sin($phase*4.7)),12)'));
        break;
      case 'Flicker':
        process(light('0.13*sin($phase*61)+0.10*sin($phase*93.7)+0.06*sin($phase*18.3)'));
        break;
      case 'Chromo-zoom':
        process('${zoom(1.025, .49, 'pow(max(0,sin($framePhase*4.6)),2)')},'
            'rgbashift=rh=14:bh=-16,gblur=sigma=0.9');
        break;
      case 'Astral':
        mixed('tmix=frames=5:weights=1 1 2 3 5,'
            'colorbalance=rs=-0.13:bs=0.43,gblur=sigma=2.8',
            'min(255,A*0.65+B*0.55)');
        break;
      case 'Unreal II':
        mixed('gblur=sigma=11,eq=brightness=0.19:saturation=0.58',
            'min(255,A*0.66+B*0.53)');
        break;
      case 'ظل':
        mixed('tmix=frames=6:weights=1 1 1 2 2 3,'
            'colorbalance=rs=-0.07:bs=0.18,eq=brightness=-0.29:saturation=0.55',
            'min(255,A*0.76+B*0.39)');
        break;
      case 'Bounce Cam...':
        process('${zoom(1.015, .58, 'pow(abs(sin($framePhase*5.2)),6)', y: 'ih/2-ih/zoom/2+(ih-ih/zoom)*0.12*sin($framePhase*5.2)')},'
            'eq=contrast=1.08');
        break;
      case 'Play Pendulu...':
        process("rotate=a='0.21*sin($phase*3.35)':ow=iw:oh=ih:c=black");
        break;
      case 'Throb':
        process('${zoom(1.00, .15, 'pow(max(0,sin($framePhase*12.4)),6)')},'
            "eq=saturation=1.38:brightness='0.04*pow(max(0,sin($phase*12.4)),6)':eval=frame");
        break;
      case 'Beat':
        process("eq=contrast='1.0+0.20*pow(max(0,sin($phase*8.0)),10)':"
            "brightness='0.09*pow(max(0,sin($phase*8.0)),10)':eval=frame");
        break;
      case 'Pulse':
        process('${zoom(1.035, .46, 'pow(max(0,sin($framePhase*3.9)),2)')},'
            'gblur=sigma=1.9');
        break;
      case 'Strobe':
        process(light('0.68*gt(sin($phase*27),0.25)-0.46*lte(sin($phase*27),0.25)'));
        break;
      case 'Sway':
        process("rotate=a='0.072*sin($phase*3.8)':ow=iw:oh=ih:c=black");
        break;
      case 'Soul':
        mixed('tmix=frames=8:weights=1 1 1 1 2 2 3 5,'
            'gblur=sigma=2.8,eq=brightness=0.09:saturation=0.70',
            'min(255,A*0.74+B*0.34)');
        break;
      case 'Flash':
        process(light('0.64*pow(max(0,sin($phase*7.3)),28)'));
        break;
    }
    return graph;
  }
}
