/// Standalone export recipes for the six Texture effects. Each effect retains
/// its own recipe, category and original label (including mosaic letter case).
/// Graph fragments can be composed by the existing timed TiniEffectsRender.
class TiniTextureEffectsExport {
  static const String category = 'ملمس';
  static const Set<String> supported = <String>{
    'Crease', 'Paper Border', 'Silkscreen',
    'blue mosaic', 'Grain', 'Blue Mosaic',
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
      throw UnsupportedError('Unsupported texture effect: $name');
    }
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Texture dimensions must be positive');
    }
    final w = width;
    final h = height;
    final phase = '(T-${startSeconds.toStringAsFixed(4)})';
    final filters = <String>[];
    // Scale tile size with the output frame. Fixed 36px blocks erase faces
    // in smaller recordings and do not match the live editor preview.
    final smallW = (w / 28).round().clamp(3, 64).toInt();
    final smallH = (h / 40).round().clamp(3, 64).toInt();
    final bigW = (w / 14).round().clamp(6, 108).toInt();
    final bigH = (h / 24).round().clamp(6, 108).toInt();

    if (name == 'Crease') {
      // Draw only the fold shading at one-quarter resolution, then overlay
      // it on the ORIGINAL full-resolution picture. This avoids applying an
      // expensive full-frame geq at every pixel of a 4K mobile export.
      final lowW = (w / 4).round().clamp(24, w).toInt();
      final lowH = (h / 4).round().clamp(24, h).toInt();
      final a = '(X-$lowW*.33-Y*.19-2*sin($phase*.8))';
      final b = '(X-$lowW*.70+Y*.095+2*cos($phase*.65))';
      final lightA = '53*exp(-pow($a,2)/(2*pow($lowW*.025,2)))';
      final darkA = '72*exp(-pow(($a-$lowW*.034),2)/(2*pow($lowW*.036,2)))';
      final lightB = '36*exp(-pow($b,2)/(2*pow($lowW*.024,2)))';
      final darkB = '44*exp(-pow(($b-$lowW*.045),2)/(2*pow($lowW*.040,2)))';
      final original = 'tx_orig$index';
      final small = 'tx_small$index';
      final shade = 'tx_shade$index';
      return <String>[
        '[$input]split=2[$original][$small]',
        '[$small]scale=$lowW:$lowH:flags=bilinear,format=yuv444p,'
            "geq=lum='clip(128+$lightA-$darkA+$lightB-$darkB,0,255)':"
            "cb='128':cr='128',"
            'scale=$w:$h:flags=bilinear,format=yuv420p[$shade]',
        '[$original][$shade]blend=all_mode=overlay:all_opacity=0.90,'
            'format=yuv420p[$output]',
      ];
    }

    switch (name) {
      case 'Paper Border':
        // A parchment-coloured surrounding sheet with a reduced photograph;
        // scratches and tiny flecks remain outside the picture itself.
        final iw = (w * .846).floor().clamp(2, w).toInt();
        final ih = (h * .828).floor().clamp(2, h).toInt();
        final px = (w - iw) ~/ 2;
        final py = (h - ih) ~/ 2;
        filters.add('scale=$iw:$ih:flags=lanczos');
        filters.add('pad=$w:$h:$px:$py:color=0xEEE1C8');
        filters.add('drawbox=x=$px:y=$py:w=$iw:h=$ih:color=0x6A5133@0.27:t=2');
        for (var i = 0; i < 36; i++) {
          final x = (i * 197 + 23) % w;
          final y = (i * 389 + 71) % h;
          final inPicture = x >= px && x < px + iw && y >= py && y < py + ih;
          if (inPicture) continue;
          filters.add('drawbox=x=$x:y=$y:w=${1 + i % 3}:h=${1 + i % 2}:'
              'color=0x806B4B@0.42:t=fill');
        }
        break;
      case 'Silkscreen':
        // Three actual ink levels, screen-door dots and a dark contour.
        // RGB thresholding gives a printmaking result unlike either mosaic.
        filters.add('format=gray,format=rgb24');
        filters.add("lutrgb=r='if(gt(val,175),245,if(gt(val,88),199,37))':"
            "g='if(gt(val,175),230,if(gt(val,88),82,35))':"
            "b='if(gt(val,175),205,if(gt(val,88),64,48))'");
        filters.add('drawgrid=w=7:h=7:t=1:c=black@0.16');
        break;
      case 'blue mosaic':
        // Small, precise turquoise/royal-blue tesserae, with visible grout.
        filters.add('pixelize=w=$smallW:h=$smallH');
        filters.add('colorchannelmixer=rr=.45:rg=.08:rb=.08:'
            'gr=.04:gg=.69:gb=.12:br=.16:bg=.22:bb=1.0');
        filters.add('eq=contrast=1.23:saturation=1.16');
        filters.add('drawgrid=w=$smallW:h=$smallH:t=1:c=0x98DFFF@0.40');
        break;
      case 'Grain':
        // Temporal film grain and a gently lifted textured negative.
        filters.add('eq=contrast=1.07:saturation=0.88:gamma=1.04');
        filters.add('noise=alls=40:allf=t+u');
        filters.add('drawgrid=w=3:h=3:t=1:c=white@0.035');
        break;
      case 'Blue Mosaic':
        // Bigger, darker cobalt glass blocks (not the small turquoise grid).
        // Heavy tile separation and saturated duotone make the two distinct.
        filters.add('pixelize=w=$bigW:h=$bigH');
        filters.add('format=gray,format=rgb24');
        filters.add("lutrgb=r='if(gt(val,190),147,if(gt(val,125),97,if(gt(val,60),47,21)))':"
            "g='if(gt(val,190),190,if(gt(val,125),141,if(gt(val,60),89,41)))':"
            "b='if(gt(val,190),254,if(gt(val,125),226,if(gt(val,60),172,119)))'");
        filters.add('drawgrid=w=$bigW:h=$bigH:t=2:c=0xC1DCFF@0.50');
        break;
    }
    return <String>[
      '[$input]${filters.join(',')},format=yuv420p[$output]',
    ];
  }
}
