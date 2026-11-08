/// Dedicated non-destructive FFmpeg treatments for the Classic category.
/// Every recipe preserves frame geometry and works in the existing timed blend.
class TiniClassicEffectsExport {
  static const category = 'كلاسيكية';
  static const supported = <String>{
    'Slide Show', 'Black Noise', 'Vintage Film', 'Film Freeze', 'DV Tape',
    'Viewfinder', 'Memory Film', 'Retro Blue', 'To B&W', 'B&W Film',
    'Retro Burst', 'Black & White', 'FPS Lag', '1998', 'JVC', 'Retro DV 3',
    'Black Sprock...', 'Vintage Video', 'Saturated Fil...',
    'Out of Focus', 'Noise I', 'White Retro ...', '70s',
  };

  // These treatments use time-sampled frames and must have a stable clock.
  static const frameRateDependent = <String>{
    'Slide Show', 'Film Freeze', 'FPS Lag',
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
      throw UnsupportedError('Unsupported Classic effect: $name');
    }
    final t = '(t-${startSeconds.toStringAsFixed(5)})';
    final w = width;
    final h = height;
    final border = (w * .022).round().clamp(2, 32);
    final filmBar = (w * .105).round().clamp(12, 110);
    final slotW = (w * .042).round().clamp(5, 48);
    final slotH = (h * .073).round().clamp(7, 90);
    final slotX = ((filmBar - slotW) / 2).round();
    final innerX = w - filmBar + slotX;
    final slotSequence = <String>[];
    for (var i = 0; i < 9; i++) {
      final y = ((i + .23) * h / 9).round();
      slotSequence.add('drawbox=x=$slotX:y=$y:w=$slotW:h=$slotH:color=white@0.91:t=fill');
      slotSequence.add('drawbox=x=$innerX:y=$y:w=$slotW:h=$slotH:color=white@0.91:t=fill');
    }
    final corners = <String>[
      'drawbox=x=${(w*.07).round()}:y=${(h*.08).round()}:w=${(w*.20).round()}:h=2:color=white@0.87:t=fill',
      'drawbox=x=${(w*.07).round()}:y=${(h*.08).round()}:w=2:h=${(h*.115).round()}:color=white@0.87:t=fill',
      'drawbox=x=${(w*.73).round()}:y=${(h*.08).round()}:w=${(w*.20).round()}:h=2:color=white@0.87:t=fill',
      'drawbox=x=${(w*.93).round()}:y=${(h*.08).round()}:w=2:h=${(h*.115).round()}:color=white@0.87:t=fill',
      'drawbox=x=${(w*.07).round()}:y=${(h*.91).round()}:w=${(w*.20).round()}:h=2:color=white@0.87:t=fill',
      'drawbox=x=${(w*.07).round()}:y=${(h*.80).round()}:w=2:h=${(h*.11).round()}:color=white@0.87:t=fill',
      'drawbox=x=${(w*.73).round()}:y=${(h*.91).round()}:w=${(w*.20).round()}:h=2:color=white@0.87:t=fill',
      'drawbox=x=${(w*.93).round()}:y=${(h*.80).round()}:w=2:h=${(h*.11).round()}:color=white@0.87:t=fill',
    ];
    String filters;
    switch (name) {
      case 'Slide Show':
        // A photographic slideshow: 2 fps held shots with a white mat.
        filters = 'fps=2,fps=30,eq=contrast=1.12:saturation=1.15,'
            'drawbox=x=$border:y=$border:w=${w-2*border}:h=${h-2*border}:color=white@0.8:t=3';
        break;
      case 'Black Noise':
        filters = 'hue=s=0,eq=contrast=1.70:brightness=-0.17,'
            'noise=alls=76:allf=t+u,drawgrid=w=iw:h=5:t=1:color=black@0.28';
        break;
      case 'Vintage Film':
        filters = 'eq=contrast=0.84:saturation=0.48:gamma_r=1.18:gamma_b=0.80,'
            'colorbalance=rs=0.18:bs=-0.13,noise=alls=18:allf=t+u,'
            'vignette=angle=PI/3.3,drawgrid=w=iw:h=31:t=1:color=white@0.065';
        break;
      case 'Film Freeze':
        filters = 'fps=1,fps=30,eq=contrast=1.04:saturation=0.53,'
            'drawbox=x=$border:y=$border:w=${w-2*border}:h=${h-2*border}:color=white@0.55:t=2';
        break;
      case 'DV Tape':
        filters = 'eq=contrast=1.08:saturation=0.90,chromashift=cbh=5:crh=-5,'
            'noise=alls=24:allf=t+u,drawgrid=w=iw:h=4:t=1:color=black@0.24';
        break;
      case 'Viewfinder':
        filters = 'eq=saturation=0.57:contrast=1.16:gamma_g=1.10,'
            '${corners.join(',')},'
            'drawbox=x=${w~/2-1}:y=${h~/2-(h*.025).round()}:w=2:h=${(h*.05).round()}:color=white@0.67:t=fill,'
            'drawbox=x=${w~/2-(w*.025).round()}:y=${h~/2-1}:w=${(w*.05).round()}:h=2:color=white@0.67:t=fill';
        break;
      case 'Memory Film':
        filters = 'gblur=sigma=1.9,eq=contrast=0.78:saturation=0.55:brightness=0.055:gamma_r=1.20,'
            'noise=alls=9:allf=t,vignette=angle=PI/3.9';
        break;
      case 'Retro Blue':
        filters = 'colorbalance=bs=0.49:rs=-0.22:gs=0.08,'
            'eq=contrast=1.28:saturation=0.73:brightness=-0.03,'
            'vignette=angle=PI/2.5';
        break;
      case 'To B&W':
        filters = "hue=s='max(0,1-min(1,max(0,$t)/0.75))',eq=contrast=1.10";
        break;
      case 'B&W Film':
        filters = 'hue=s=0,eq=contrast=1.27:gamma=1.07,'
            'noise=alls=33:allf=t+u,vignette=angle=PI/3.2,'
            'drawgrid=w=iw:h=47:t=1:color=white@0.11';
        break;
      case 'Retro Burst':
        filters = "eq=contrast=1.22:saturation=1.35:brightness='0.06+0.25*pow(max(0,sin(9*$t)),8)':eval=frame,"
            'colorbalance=rs=0.21:bs=-0.11';
        break;
      case 'Black & White':
        filters = 'hue=s=0,eq=contrast=1.70:brightness=-0.04';
        break;
      case 'FPS Lag':
        filters = 'fps=5,fps=30,eq=contrast=1.19:saturation=1.25,'
            'rgbashift=rh=3:bh=-3';
        break;
      case '1998':
        filters = 'eq=contrast=1.08:saturation=0.80:gamma_r=1.13:gamma_g=1.01:gamma_b=0.94,'
            'chromashift=cbh=4:crh=-3,noise=alls=24:allf=t+u,'
            'drawgrid=w=iw:h=6:t=1:color=black@0.19';
        break;
      case 'JVC':
        filters = 'eq=contrast=1.15:saturation=1.1,'
            'chromashift=cbh=2:crh=-3,noise=alls=15:allf=t,'
            '${corners.join(',')},'
            'drawbox=x=${(w*.065).round()}:y=${(h*.055).round()}:w=${(w*.026).round()}:h=${(w*.026).round()}:color=red@0.94:t=fill';
        break;
      case 'Retro DV 3':
        filters = 'eq=saturation=1.35:contrast=1.05:gamma_r=1.05,'
            'rgbashift=rh=9:bh=-7:rv=2:bv=-2,'
            'noise=alls=17:allf=t+u,drawgrid=w=iw:h=8:t=1:color=white@0.13';
        break;
      case 'Black Sprock...':
        filters = 'eq=contrast=1.06:saturation=0.64,'
            'drawbox=x=0:y=0:w=$filmBar:h=$h:color=black:t=fill,'
            'drawbox=x=${w-filmBar}:y=0:w=$filmBar:h=$h:color=black:t=fill,'
            '${slotSequence.join(',')},noise=alls=12:allf=t';
        break;
      case 'Vintage Video':
        filters = 'eq=contrast=0.84:saturation=0.62:brightness=-0.025:gamma_r=1.13,'
            'chromashift=cbh=2:crh=-2,noise=alls=39:allf=t+u,'
            'drawgrid=w=iw:h=5:t=1:color=black@0.23';
        break;
      case 'Saturated Fil...':
        filters = 'eq=contrast=1.31:saturation=2.30:gamma_r=1.06:brightness=0.025,'
            'colorbalance=rs=0.13:bs=-0.11';
        break;
      case 'Out of Focus':
        filters = 'gblur=sigma=13,eq=contrast=0.87:brightness=0.045';
        break;
      case 'Noise I':
        filters = 'eq=saturation=1.26:contrast=1.19,'
            'noise=alls=74:allf=t+u';
        break;
      case 'White Retro ...':
        filters = 'eq=contrast=0.71:saturation=0.43:brightness=0.19:gamma=1.13,'
            'noise=alls=14:allf=t,'
            'drawbox=x=$border:y=$border:w=${w-2*border}:h=${h-2*border}:color=white@0.75:t=4';
        break;
      case '70s':
        filters = 'eq=contrast=0.91:saturation=0.93:gamma_r=1.23:gamma_b=0.73,'
            'colorbalance=rs=0.25:gs=0.09:bs=-0.19,'
            'noise=alls=14:allf=t+u,vignette=angle=PI/2.7';
        break;
      default:
        throw StateError('Missing Classic recipe: $name');
    }
    return ['[$input]$filters,format=yuv420p[$output]'];
  }
}
