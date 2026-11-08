/// Individual, reference-led lighting effects for the Lighting tab.
/// The low-resolution procedural light field is upscaled onto the *original*
/// video at output resolution. No asset downloads, temporary files or extra
/// native dependencies are required. A separate source branch preserves frame
/// timestamps; the parent composites the effect only over its chosen interval.
class TiniLightingEffectsExport {
  static const category = 'إضاءة';
  static const supported = <String>{
    'Frost Soft Le...', 'Diamond Sof...', 'Soft Light', 'Over Exposu...',
    'Dream Glow', 'Red Glow', 'Glow', 'Leak II', 'Leak 1', 'Leak',
    'Vaporwave', 'Neon', 'Halo Light II', 'Rainbow Sha...',
    'Water Reflec...', 'Angel', 'Tyndall Light', 'Backlight',
    'Prism I', 'Lights',
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
      throw UnsupportedError('Lighting effect is not implemented: $name');
    }
    // T is the input frame's presentation time. Unlike N/30, it remains
    // correct for 24, 30 and 60 fps videos, and after changes in clip speed.
    final t = '(T-${startSeconds.toStringAsFixed(4)})';
    const x = '(X/W)';
    const y = '(Y/H)';
    String spot(String cx, String cy, double sx, double sy) =>
        'exp(-(pow(($x-$cx)/$sx,2)+pow(($y-$cy)/$sy,2))*2)';
    String shaft(String xAtY, double spread) =>
        '(exp(-pow(($x-($xAtY))/$spread,2))*pow(1-$y,0.65))';
    String band(String offset, double width) =>
        'exp(-pow((sqrt(pow(($x-.92)*1.2,2)+pow(($y-.52)*.9,2))-$offset)/$width,2))';

    String base = 'null';
    String r = '0';
    String g = '0';
    String b = '0';
    double opacity = .75;
    switch (name) {
      case 'Frost Soft Le...':
        base = 'colorbalance=bs=0.08:rs=0.02,eq=contrast=0.93:saturation=0.78:brightness=0.035,gblur=sigma=0.8';
        final frost = '${spot('0.08', '.30', .36, .55)}+${spot('.91', '.71', .31, .49)}';
        r = '101*$frost'; g = '79*$frost'; b = '173*$frost'; opacity = .72;
        break;
      case 'Diamond Sof...':
        base = 'eq=brightness=0.035:contrast=1.05:saturation=1.08';
        final stars = '(pow(max(0,sin(37*$x+13*$y+2.4*$t)*sin(21*$y-9*$x-1.8*$t)),12))';
        final streaks = 'exp(-pow(($x-.76-.09*sin(1.5*$t))/.018,2))*exp(-pow(($y-.28)/.16,2))';
        r = '238*$stars+150*$streaks'; g = '230*$stars+195*$streaks'; b = '255*$stars+240*$streaks'; opacity = .91;
        break;
      case 'Soft Light':
        base = 'eq=brightness=0.065:contrast=0.87:saturation=1.04';
        final soft = spot('.54', '.42', .80, .86);
        r = '93*$soft'; g = '77*$soft'; b = '62*$soft'; opacity = .40;
        break;
      case 'Over Exposu...':
        base = 'eq=brightness=0.22:contrast=0.83:gamma=1.12';
        final white = spot('.50', '.30', .68, .66);
        r = '225*$white'; g = '217*$white'; b = '198*$white'; opacity = .81;
        break;
      case 'Dream Glow':
        base = 'eq=brightness=0.055:contrast=0.92:saturation=1.09';
        final peach = spot('.90', '.23', .57, .55);
        final blush = spot('.08', '.83', .43, .45);
        r = '177*$peach+99*$blush'; g = '116*$peach+49*$blush'; b = '69*$peach+121*$blush'; opacity = .56;
        break;
      case 'Red Glow':
        base = 'eq=brightness=-0.06:contrast=1.13:saturation=1.11';
        final red = spot('.09', '.67', .45, .67);
        r = '250*$red'; g = '17*$red'; b = '24*$red'; opacity = .86;
        break;
      case 'Glow':
        base = 'eq=brightness=0.08:contrast=0.94';
        final whiteGlow = spot('.55', '.42', .64, .77);
        r = '158*$whiteGlow'; g = '164*$whiteGlow'; b = '167*$whiteGlow'; opacity = .58;
        break;
      case 'Leak II':
        base = 'eq=contrast=1.03:saturation=1.09';
        final edgeLeakII = spot('1.13', '.28', .40, .48);
        final slit = shaft('1.05-.38*$y+.09*sin($t*.9)', .095);
        r = '245*$edgeLeakII+172*$slit'; g = '100*$edgeLeakII+121*$slit'; b = '24*$edgeLeakII+51*$slit'; opacity = .81;
        break;
      case 'Leak 1':
        base = 'eq=brightness=0.055:contrast=0.92';
        final top = spot('1.05', '.18', .52, .57);
        final bottom = spot('-.07', '1.06', .43, .44);
        r = '250*$top+155*$bottom'; g = '184*$top+103*$bottom'; b = '99*$top+37*$bottom'; opacity = .88;
        break;
      case 'Leak':
        base = 'eq=contrast=1.08:saturation=1.10';
        final flare = spot('-.16', '.79', .48, .55);
        final edgeLeak = 'exp(-pow($x/.10,2))*(.50+.50*sin(4*$y+1.2*$t))';
        r = '235*$flare+135*$edgeLeak'; g = '100*$flare+31*$edgeLeak'; b = '29*$flare+15*$edgeLeak'; opacity = .88;
        break;
      case 'Vaporwave':
        base = 'colorbalance=rs=0.09:gs=-0.11:bs=0.20,eq=saturation=1.18:contrast=1.08';
        final pink = spot('.79', '.30', .76, .79);
        final cyan = spot('-.06', '.16', .58, .80);
        r = '188*$pink+16*$cyan'; g = '31*$pink+108*$cyan'; b = '150*$pink+175*$cyan'; opacity = .70;
        break;
      case 'Neon':
        base = 'eq=contrast=1.22:saturation=1.29:brightness=-0.055';
        final magenta = spot('.80', '.70', .57, .60);
        final ice = spot('.03', '.06', .59, .66);
        r = '255*$magenta+24*$ice'; g = '21*$magenta+136*$ice'; b = '151*$magenta+215*$ice'; opacity = .84;
        break;
      case 'Halo Light II':
        base = 'eq=contrast=1.01:saturation=1.06:brightness=0.012';
        r = '245*${band('.30', .075)}';
        g = '206*${band('.37', .075)}';
        b = '237*${band('.46', .085)}'; opacity = .97;
        break;
      case 'Rainbow Sha...':
        base = 'eq=brightness=0.008:contrast=1.05';
        final off = '($x-.16-.55*$y-.18*sin($t*.65))';
        r = '200*exp(-pow(($off-.03)/.13,2))';
        g = '178*exp(-pow(($off-.15)/.13,2))';
        b = '215*exp(-pow(($off-.29)/.13,2))'; opacity = .75;
        break;
      case 'Water Reflec...':
        base = 'colorbalance=bs=0.09,eq=contrast=1.07:saturation=1.08';
        final ripples = 'pow(max(0,sin(62*$y+5*sin(12*$x+1.6*$t)+3*$t)),12)';
        final caustic = 'pow(max(0,cos(37*$x+9*sin(9*$y-$t))),14)';
        final upper = '${spot('.52', '.18', 1.0, .47)}';
        r = '(28*$ripples+18*$caustic)*$upper';
        g = '(94*$ripples+75*$caustic)*$upper';
        b = '(156*$ripples+120*$caustic)*$upper'; opacity = .64;
        break;
      case 'Angel':
        base = 'eq=brightness=0.13:contrast=0.80:gamma=1.14';
        final angelGlow = spot('.52', '-.04', .62, .65);
        final ray = shaft('.51+.47*$y', .22);
        r = '211*$angelGlow+104*$ray'; g = '205*$angelGlow+101*$ray'; b = '185*$angelGlow+91*$ray'; opacity = .77;
        break;
      case 'Tyndall Light':
        base = 'eq=contrast=0.96:brightness=0.035:saturation=0.98';
        final ray1 = shaft('-.12+.52*$y+.04*sin($t*.6)', .085);
        final ray2 = shaft('.08+.63*$y', .09);
        final ray3 = shaft('.29+.69*$y', .072);
        r = '187*$ray1+148*$ray2+112*$ray3';
        g = '151*$ray1+119*$ray2+94*$ray3';
        b = '78*$ray1+67*$ray2+52*$ray3'; opacity = .77;
        break;
      case 'Backlight':
        base = 'eq=contrast=0.90:brightness=0.025';
        final back = spot('.53', '.09', .50, .49);
        final ring = 'exp(-pow((sqrt(pow(($x-.52)/.50,2)+pow(($y-.53)/.50,2))-.77)/.23,2))';
        r = '192*$back+113*$ring'; g = '208*$back+116*$ring'; b = '218*$back+128*$ring'; opacity = .78;
        break;
      case 'Prism I':
        base = 'eq=contrast=1.18:brightness=-0.22:saturation=0.77';
        final beam = '(($x-.70+.57*$y)+.12*sin($t*.45))';
        r = '164*exp(-pow(($beam+.20)/.14,2))';
        g = '230*exp(-pow(($beam+.03)/.14,2))';
        b = '224*exp(-pow(($beam-.15)/.14,2))'; opacity = .90;
        break;
      case 'Lights':
        base = 'eq=brightness=0.025:saturation=1.10';
        String orb(int index, double dx, double dy) {
          final cx = '(.12+${dx.toStringAsFixed(2)}+.12*sin($t*${(.63 + index*.16).toStringAsFixed(2)}+$index))';
          final cy = '(.08+${dy.toStringAsFixed(2)}+.16*cos($t*${(.51+index*.19).toStringAsFixed(2)}+$index))';
          return spot(cx, cy, .105, .115);
        }
        r = '195*${orb(0, .08, .10)}+235*${orb(2, .53, .34)}+155*${orb(4, .46, .65)}';
        g = '218*${orb(1, .32, .18)}+143*${orb(2, .53, .34)}+227*${orb(3, .70, .54)}';
        b = '222*${orb(0, .08, .10)}+236*${orb(1, .32, .18)}+180*${orb(3, .70, .54)}'; opacity = .96;
        break;
    }

    final n = 'tl${index}_';
    final smallWidth = 128;
    final smallHeight = (height / width * smallWidth).round().clamp(96, 256).toInt();
    // Values are bounded so blend never wraps when several light sources meet.
    String channel(String expression) => "clip($expression,0,255)";
    return [
      '[$input]split=2[${n}base][${n}field]',
      '[${n}base]$base,format=gbrp[${n}lit]',
      '[${n}field]scale=$smallWidth:$smallHeight:flags=fast_bilinear,'
          'format=gbrp,geq=r=\'${channel(r)}\':g=\'${channel(g)}\':b=\'${channel(b)}\','
          'scale=$width:$height:flags=bicubic,format=gbrp[${n}light]',
      '[${n}lit][${n}light]blend=all_mode=screen:'
          'all_opacity=${opacity.toStringAsFixed(3)},format=yuv420p[$output]',
    ];
  }
}
