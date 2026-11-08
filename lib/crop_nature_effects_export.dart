/// Independent FFmpeg recipes for the Nature effects category. No files,
/// network requests or platform channels are introduced by these recipes.
/// All animation coordinates use the source video clock (t-startSeconds).
class TiniNatureEffectsExport {
  static const category = 'الطبيعة';
  static const supported = <String>{
    'Fluffy Snow', 'Snowfall', 'Snow', 'Snowflake', 'Snow II',
    'Flying Snow', 'Rain FX', 'Rain', 'Falling Leaves', 'Petals',
    'Rose Petals', 'Soft Rose', 'Pink Petals', 'Sakura',
    'Sunset 1', 'Sunset 2', 'Sunshine', 'Tree Shade 2', 'Heat Wave', 'Smog',
  };

  static List<String> filterGraph({required String input,
      required String output, required String name,
      required double startSeconds, required double endSeconds,
      required int width, required int height, required int index}) {
    if (!supported.contains(name)) {
      throw UnsupportedError('Unsupported Nature effect: $name');
    }
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Nature effect video dimensions must be positive');
    }
    final start = startSeconds.toStringAsFixed(4);
    final local = '(t-$start)';
    final w = width;
    final h = height;
    final filters = <String>[];

    // drawtext evaluates x and y on each frame (unlike drawbox); generated
    // glyphs are fallback vector artwork, not source-app particle assets.
    String particle(int i, String glyph, String color, int size, double speed,
        {double sway = 0, double drift = 0, double wobble = 1.0,
        double opacity = .83}) {
      final seed = (i * 131 + 23) % 997;
      final x0 = (seed * 47 + 31) % (w + size);
      final y0 = (seed * 191 + 19) % (h + size);
      final phase = (seed % 53) / 7.0;
      final x = '$x0+$drift*$local+$sway*sin($wobble*$local+$phase)';
      // The two backslashes below encode an escaped comma for the FFmpeg
      // expression parser inside a filtergraph argument.
      final y = 'mod($y0+${speed.toStringAsFixed(2)}*$local\\,${h + size * 2})-$size';
      return "drawtext=font='DejaVu Sans':text='$glyph':x='$x':y='$y':fontsize=$size:"
          "fontcolor=$color@${opacity.toStringAsFixed(2)}:"
          'fix_bounds=0';
    }

    void snowfall({required String glyph, required int count,
        required int baseSize, required double speed,
        required String color, double sway = 8, double drift = 2}) {
      for (var i = 0; i < count; i++) {
        final size = (baseSize * (.70 + ((i*7)%11)/18)).round();
        filters.add(particle(i, glyph, color, size,
          speed * (.65 + ((i*13)%17)/19),
          sway: sway, drift: drift, wobble:.85+(i%4)*.14,
          opacity:.48+(i%6)*.07));
      }
    }

    // Per-frame dynamic text placement is used only for snow particles. Unlike
    // the original shared snowfall() recipe, each snow style owns its geometry
    // and motion. ASCII symbols are used where possible for font resilience.
    void snowGlyph(int i, String glyph, String color, int size,
        {required double xSpeed, required double ySpeed,
        double sway = 0, double frequency = 1, double opacity = .8,
        int salt = 0}) {
      final seed = (i * 131 + salt * 73 + 29) % 997;
      // Use normalized anchors shared with the preview, so seeking and
      // export start particles at the same on-screen locations.
      final x0 = ((seed * 47 + 31) % 997) * w / 997.0;
      final y0 = ((seed * 191 + 19) % 997) * h / 997.0;
      final phase = ((seed % 67) / 11).toStringAsFixed(4);
      final inset = (size / 2).toStringAsFixed(2);
      final x = 'mod(${x0.toStringAsFixed(4)}+'
          '${xSpeed.toStringAsFixed(3)}*$local+'
          '${sway.toStringAsFixed(3)}*sin(${frequency.toStringAsFixed(3)}*'
          '$local+$phase)\\,$w)-$inset';
      final y = 'mod(${y0.toStringAsFixed(4)}+'
          '${ySpeed.toStringAsFixed(3)}*$local\\,$h)-$inset';
      filters.add("drawtext=font='DejaVu Sans':text='$glyph':x='$x':y='$y':"
          "fontsize=$size:fontcolor=$color@${opacity.toStringAsFixed(2)}:"
          'fix_bounds=0');
    }

    switch (name) {
      case 'Fluffy Snow':
        // Airy, slowly drifting bokeh-like flakes. Two sizes create depth.
        for (var i=0; i<23; i++) {
          final big = i%3==0;
          snowGlyph(i, '●', '0xF4FAFF',
            (w*(big ? .030 : .012)).round().clamp(5,34).toInt(),
            xSpeed:0, ySpeed:h*(big ? .036 : .076),
            sway:w*.026, frequency:big ? .43 : .70,
            opacity:big ? .29 : .70, salt:1);
        }
        break;
      case 'Snowfall':
        // Branched crystals, visible glow and pronounced falling motion.
        for (var i=0; i<26; i++) {
          snowGlyph(i,'❄','0xE5F5FF',
              (w*(.027+(i%4)*.007)).round().clamp(10,50).toInt(),
              xSpeed:w*.008,ySpeed:h*(.09+(i%5)*.012),
              sway:w*.045,frequency:.7,opacity:.67+(i%4)*.075,salt:2);
        }
        break;
      case 'Snow':
        // Tiny bright dots without decorative snowflake silhouettes.
        for (var i=0; i<49; i++) {
          snowGlyph(i,'·','0xFFFFFF',
              (w*(.013+(i%3)*.004)).round().clamp(6,18).toInt(),
              xSpeed:0,ySpeed:h*(.05+(i%5)*.013),
              sway:w*.012,frequency:.8,opacity:.5+(i%4)*.10,salt:3);
        }
        break;
      case 'Snowflake':
        // Large isolated crystal silhouettes with slow oscillation.
        for (var i=0; i<13; i++) {
          snowGlyph(i,'❄','0xF1F9FF',
              (w*(.048+(i%3)*.013)).round().clamp(20,70).toInt(),
              xSpeed:0,ySpeed:h*(.05+(i%3)*.018),
              sway:w*.06,frequency:.65,opacity:.82,salt:4);
        }
        break;
      case 'Snow II':
        // A noticeably denser cool-blue diagonal sleet shower.
        filters.add('colorbalance=bs=0.09:rs=-0.035');
        for (var i=0; i<65; i++) {
          snowGlyph(i,'/','0xD5E9FF',
              (w*(.010+(i%3)*.005)).round().clamp(7,21).toInt(),
              xSpeed:w*(.018+(i%4)*.004),
              ySpeed:h*(.125+(i%6)*.032),
              sway:0,opacity:.36+(i%5)*.11,salt:5);
        }
        break;
      case 'Flying Snow':
        // Wind-driven horizontal streaks; much faster than every snow mode.
        for (var i=0; i<59; i++) {
          snowGlyph(i,'-','0xEDF8FF',
              (w*(.013+(i%4)*.004)).round().clamp(7,28).toInt(),
              xSpeed:w*(.19+(i%6)*.048),
              ySpeed:h*(.017+(i%5)*.008),
              sway:w*.013,frequency:2.4,
              opacity:.41+(i%5)*.11,salt:6);
        }
        break;
      case 'Rain FX':
        filters.add('colorbalance=bs=0.075:gs=0.03');
        snowfall(glyph:'/',count:46,baseSize:(w*.042).round().clamp(10,40).toInt(),
          speed:h*.83,color:'0xC9E7FF',sway:1,drift:-w*.11);
        break;
      case 'Rain':
        filters.add('eq=brightness=-0.045:saturation=0.87');
        snowfall(glyph:'/',count:48,baseSize:(w*.032).round().clamp(9,36).toInt(),
          speed:h*.62,color:'0xC0E0EA',sway:1,drift:-w*.09);
        break;
      case 'Falling Leaves':
        const colors = <String>['0xF5B72F','0xDF6B26','0xE14B25',
          '0xFFCF4B','0xB8812C'];
        for (var i=0;i<17;i++) {
          filters.add(particle(i,'❧',colors[i%colors.length],
            (w*(.047+(i%4)*.010)).round().clamp(11,52).toInt(),h*(.09+i%5*.015),
            sway:w*.06,drift:w*.014,opacity:.84));
        }
        break;
      case 'Petals':
        snowfall(glyph:'❥',count:23,baseSize:(w*.037).round().clamp(10,37).toInt(),
          speed:h*.13,color:'0xF7A3BF',sway:w*.035);
        break;
      case 'Rose Petals':
        const colors = <String>['0xF46A86','0xE64266','0xFFC0C7'];
        for(var i=0;i<25;i++) {
          filters.add(particle(i,'❥',colors[i%3],
            (w*(.027+(i%4)*.008)).round().clamp(10,38).toInt(),
            h*(.12+(i%5)*.015),sway:w*.038,drift:w*.005,
            opacity:.62+(i%4)*.09));
        }
        break;
      case 'Soft Rose':
        snowfall(glyph:'❥',count:19,baseSize:(w*.033).round().clamp(10,40).toInt(),
          speed:h*.07,color:'0xF1CBD9',sway:w*.04);
        break;
      case 'Pink Petals':
        snowfall(glyph:'❥',count:30,baseSize:(w*.030).round().clamp(9,37).toInt(),
          speed:h*.14,color:'0xF17DA5',sway:w*.04);
        break;
      case 'Sakura':
        snowfall(glyph:'✿',count:22,baseSize:(w*.038).round().clamp(12,40).toInt(),
          speed:h*.10,color:'0xFFC3D5',sway:w*.052);
        break;
      case 'Sunset 1':
        filters.add('colorbalance=rs=0.24:gs=0.09:bs=-0.19,'
            'eq=brightness=0.042:contrast=1.04:saturation=1.10:gamma_r=1.1');
        break;
      case 'Sunset 2':
        filters.add('colorbalance=rs=0.26:gs=-0.025:bs=0.065,'
            'eq=brightness=0.038:contrast=0.98:saturation=1.11:gamma_r=1.09');
        break;
      case 'Sunshine':
        filters.add('colorbalance=rs=0.18:gs=0.10:bs=-0.10,'
            "eq=brightness='0.055+0.032*sin(3*$local)':eval=frame:"
            'contrast=1.06:saturation=1.13');
        break;
      case 'Tree Shade 2':
        filters.add('eq=brightness=-0.035:contrast=1.07');
        // Sparse shifting canopy shadows; overlays remain translucent.
        for(var i=0;i<13;i++) {
          filters.add(particle(i,'●','0x182A16',
            (w*(.14+(i%4)*.05)).round().clamp(15,130).toInt(),
            0,sway:w*.037,drift:0,wobble:.35+(i%3)*.16,
            opacity:.12+(i%4)*.018));
        }
        break;
      case 'Heat Wave':
        // True time-dependent sample displacement, rather than a static lens.
        filters.add('format=yuv444p,geq='
          "lum='lum(X+6*sin(Y/25+T*8)+3*sin(Y/71-T*5),Y)':"
          "cb='cb(X+3*sin(Y/19+T*6),Y)':"
          "cr='cr(X+3*sin(Y/19+T*6),Y)'"
          ',format=yuv420p');
        break;
      case 'Smog':
        filters.add('gblur=sigma=2.3,eq=contrast=0.73:'
          'saturation=0.72:brightness=0.075');
        break;
    }
    if (filters.isEmpty) {
      throw StateError('Missing Nature recipe: $name');
    }
    return ['[$input]${filters.join(',')},format=yuv420p[$output]'];
  }
}
