/// Six distinct video treatments for the Glitch tab.
/// They operate on frames, never edit source media, and are blended by the
/// existing TiniEffectsRender only over the selected effect's time range.
class TiniGlitchEffectsExport {
  static const category = 'خلل';
  static const supported = <String>{
    'Fuzzy', 'X-Signal', 'Edgy', 'Edge Glitch', 'خلل', "70's",
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
      throw UnsupportedError('Unsupported Glitch effect: $name');
    }
    final result = <String>[];
    final prefix = 'tg${index}_';
    final s = startSeconds.toStringAsFixed(5);
    // GEQ's T is presentation time (not time since selection). Keep motion
    // phase-aligned with the preview so a late-placed effect starts at zero.
    final t = '(T-$s)';
    void single(String filters) =>
        result.add('[$input]$filters,format=yuv420p[$output]');

    switch (name) {
      case 'Fuzzy':
        // Soft, unstable analogue snow, with fine CRT horizontal structure.
        single('gblur=sigma=2.0,'
            'eq=contrast=1.18:saturation=0.59:brightness=-0.045,'
            'noise=alls=68:allf=t+u,'
            'drawgrid=w=iw:h=4:t=1:color=white@0.18');
        break;
      case 'X-Signal':
        // Satellite dropouts: horizontal tearing in intermittent bands, then
        // separated RGB channels. Unlike Fuzzy, most pixels stay sharp.
        final tear = '(24*sin(24*$t+Y*.085)*lt(mod(Y+13*$t,93),18)'
            '+8*sin(57*$t)*lt(mod(Y+9*$t,43),5))';
        single("geq=lum='lum(max(0,min(W-1,X+$tear)),Y)':"
            "cb='cb(X,Y)':cr='cr(X,Y)',"
            'rgbashift=rh=18:gh=-2:bh=-18:rv=2:bv=-2,'
            'noise=alls=14:allf=t+u');
        break;
      case 'Edgy':
        // Graphic ink-outline image, NOT a duplicate of digital RGB glitches.
        result.add('[$input]split=2[${prefix}base][${prefix}edges]');
        result.add('[${prefix}base]eq=contrast=1.36:saturation=1.7,'
            'unsharp=5:5:0.95,format=yuv420p[${prefix}bright]');
        result.add('[${prefix}edges]format=gray,'
            'edgedetect=mode=wires:low=0.06:high=0.15,'
            'format=yuv420p[${prefix}ink]');
        result.add('[${prefix}bright][${prefix}ink]'
            "blend=all_expr='if(gt(B,28),clip(A*.26+B*.82,0,255),A)',"
            'format=yuv420p[$output]');
        break;
      case 'Edge Glitch':
        // Animated electronic contour outlines and intermittent bright borders.
        result.add('[$input]split=2[${prefix}base][${prefix}edge]');
        result.add('[${prefix}base]eq=contrast=1.11:saturation=0.75,'
            'format=yuv420p[${prefix}b]');
        result.add('[${prefix}edge]edgedetect=mode=wires:low=0.07:high=0.20,'
            'rgbashift=rh=11:bh=-11,'
            'eq=contrast=1.9:brightness=-0.04,'
            'format=yuv420p[${prefix}e]');
        result.add('[${prefix}b][${prefix}e]'
            "blend=all_expr='clip(A*.68+B*.71+13*sin(T*18+Y*.09),0,255)',"
            'drawgrid=w=iw:h=9:t=1:color=0x21D3FF@0.19,'
            'format=yuv420p[$output]');
        break;
      case 'خلل':
        // Abrupt block decoding errors plus horizontal scrambling. This is
        // intentionally unrelated to the effect named خلل in Amazing.
        final tear = '(36*sin(11*$t+floor(Y/32)*4)*'
            'lt(mod(Y+7*$t,113),38))';
        result.add('[$input]split=2[${prefix}source][${prefix}blocks]');
        result.add('[${prefix}source]eq=contrast=1.12:saturation=1.25,'
            'format=yuv420p[${prefix}clean]');
        result.add('[${prefix}blocks]pixelize=w=24:h=18,'
            "geq=lum='lum(max(0,min(W-1,X+$tear)),Y)':"
            "cb='cb(X,Y)':cr='cr(X,Y)',"
            'rgbashift=rh=10:bh=-11,'
            'format=yuv420p[${prefix}damaged]');
        result.add('[${prefix}clean][${prefix}damaged]'
            "blend=all_expr='if(lt(mod(Y+T*75,119),53),B,A)',"
            'format=yuv420p[$output]');
        break;
      case "70's":
        // Warm, bleeding analogue tape with unstable tracking and dust.
        // No chromatic tearing, macroblocks or edge detection.
        single('eq=contrast=0.91:saturation=0.76:brightness=0.035:gamma_r=1.13:gamma_b=0.83,'
            'colorbalance=rs=0.20:gs=0.055:bs=-0.16,'
            'chromashift=cbh=3:crh=-4,'
            'noise=alls=22:allf=t+u,'
            'drawgrid=w=iw:h=6:t=1:color=black@0.21,'
            'vignette=angle=PI/2.6');
        break;
    }
    return result;
  }
}
