/// Five independent, time-varying pixel displacement fields for the
/// Distortion tab. No source-media changes, external textures or extra assets.
/// FFmpeg uses the source frame's luminance and chroma samples; all planes are
/// warped with identical normalized coordinates, retaining output dimensions.
class TiniDistortionEffectsExport {
  static const category = 'تشويه';
  static const supported = <String>{
    'Waves 2', 'Concentric C...', 'Stretched W...',
    'Ripple Distor...', 'Ripples',
  };

  /// Coordinates are normalized by each YUV plane's W and H. This matters:
  /// chroma planes may be subsampled, but must follow the same spatial warp.
  static ({String x, String y}) _coordinates(String name, String t) {
    const x = '(X/W)';
    const y = '(Y/H)';
    switch (name) {
      case 'Waves 2':
        // Two large travelling elastic waves bend the image side-to-side,
        // with a smaller cross-axis undulation and a central swelling.
        final wave = 'sin(6.2831853*(2.35*$y-1.20*$t))';
        final bulge = 'exp(-6*(pow($x-.5,2)+pow($y-.47,2)))';
        return (
          x: '$x+.118*$wave*(.72+.28*cos(9.42478*$x))'
             '+.21*sin(2.8*$t)*$bulge*($x-.5)',
          y: '$y+.033*sin(6.2831853*(1.8*$x+.60*$y)+3.2*$t)',
        );
      case 'Concentric C...':
        // Annular sectors rotate in alternating directions. Unlike Ripples,
        // the samples travel tangentially around the image centre.
        final dx = '($x-.5)';
        final dy = '($y-.5)';
        final r = 'sqrt($dx*$dx+$dy*$dy)';
        final angle = '(.64*sin(39*$r-5.7*$t)*exp(-.85*$r))';
        return (
          x: '.5+$dx*cos($angle)-$dy*sin($angle)',
          y: '.5+$dx*sin($angle)+$dy*cos($angle)',
        );
      case 'Stretched W...':
        // Elastic horizontal compression / expansion, phase displaced by Y.
        // Large regions stretch while adjacent regions are squeezed.
        final stretch = '(1+.48*sin(9.424777*$y-4.3*$t))';
        return (
          x: '.5+($x-.5)/$stretch',
          y: '$y+.033*sin(15.70796*$x+3.6*$t)',
        );
      case 'Ripple Distor...':
        // A strong, asymmetric ripple travels around a moving focal point.
        final dx = '($x-(.5+.18*sin(1.25*$t)))';
        final dy = '($y-(.46+.14*cos(.93*$t)))';
        final r = 'sqrt($dx*$dx+$dy*$dy)';
        final push = '(.086*sin(58*$r-10*$t)*exp(-1.9*$r)/($r+.035))';
        return (x: '$x+$dx*$push', y: '$y+$dy*$push');
      case 'Ripples':
        // Fine water waves radiate from two different impact points. No
        // alternating annular rotation; both waves are purely radial.
        final dx = '($x-.48)';
        final dy = '($y-.51)';
        final dx2 = '($x-.21)';
        final dy2 = '($y-.68)';
        final r = 'sqrt($dx*$dx+$dy*$dy)';
        final r2 = 'sqrt($dx2*$dx2+$dy2*$dy2)';
        final a = '(.026*sin(101*$r-11.4*$t)*exp(-2.6*$r)/($r+.025))';
        final b = '(.012*sin(122*$r2-12.7*$t)*exp(-3.8*$r2)/($r2+.025))';
        return (
          x: '$x+$dx*$a+$dx2*$b',
          y: '$y+$dy*$a+$dy2*$b',
        );
      default:
        throw UnsupportedError('Unsupported Distortion effect: $name');
    }
  }

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
      throw UnsupportedError('Unsupported Distortion effect: $name');
    }
    // GEQ's T is the absolute output timeline. Shift it by the effect start
    // so that applying an effect halfway through a video resets its motion.
    final time = '(T-${startSeconds.toStringAsFixed(5)})';
    final coords = _coordinates(name, time);
    final sx = 'clip(W*(${coords.x}),0,W-1)';
    final sy = 'clip(H*(${coords.y}),0,H-1)';
    // FFmpeg interprets geq(x,y) within each plane at its native resolution.
    // Bilinear sampling avoids the harsh, aliased edges of nearest-neighbour.
    final filter = 'geq='
        "lum='lum($sx,$sy)':"
        "cb='cb($sx,$sy)':"
        "cr='cr($sx,$sy)':interpolation=bilinear";
    return ['[$input]$filter,format=yuv420p[$output]'];
  }
}
