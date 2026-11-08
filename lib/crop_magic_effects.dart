/// Local, per-clip Magic effects. No network inference or paid service.
/// The catalogue order matches the animated selector in crop_magic_panel.dart.
class CropMagicEffect {
  final String id;
  final String title;
  final bool isFrame;
  const CropMagicEffect(this.id, this.title, {this.isFrame = false});
}

class CropMagicEffects {
  static const List<CropMagicEffect> all = [
    CropMagicEffect('cinematic_zoom', 'تقريب سينمائي'),
    CropMagicEffect('whip_pan', 'حركة خاطفة'),
    CropMagicEffect('impact_shake', 'اهتزاز قوي'),
    CropMagicEffect('motion_echo', 'أثر الحركة'),
    CropMagicEffect('rgb_glitch', 'خلل رقمي'),
    CropMagicEffect('flash_beat', 'فلاش سريع'),
    CropMagicEffect('freeze_focus', 'تجميد سينمائي'),
    CropMagicEffect('kaleidoscope', 'مرآة سحرية'),
    CropMagicEffect('dynamic_split', 'تقسيم متحرك'),
    CropMagicEffect('vhs_retro', 'فيديو قديم'),
    CropMagicEffect('light_leak', 'تسرب الضوء'),
    CropMagicEffect('cinema_frame', 'إطار سينمائي', isFrame: true),
    CropMagicEffect('neon_frame', 'إطار نيون', isFrame: true),
    CropMagicEffect('film_strip', 'إطار فيلم قديم', isFrame: true),
    CropMagicEffect('floating_frame', 'إطار عائم', isFrame: true),
  ];

  static CropMagicEffect? find(String? id) {
    for (final effect in all) {
      if (effect.id == id) return effect;
    }
    return null;
  }

  /// Append FFmpeg filtergraph statements to turn [input] into [output].
  /// Inputs/outputs are label names without square brackets. The caller
  /// normalizes timestamps before invoking these filters.
  /// Filters use stock FFmpeg primitives rather than platform-specific shaders.
  static List<String> filterGraph({
    required String input,
    required String output,
    required String? id,
    required double seconds,
    required int width,
    required int height,
  }) {
    if (id == null) return ['[$input]null[$output]'];
    switch (id) {
      case 'cinematic_zoom':
        return ["[$input]zoompan=z='1.05+0.20*(1-cos(on*0.12))':"
            "x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':"
            "d=1:s=${width}x$height:fps=30[$output]"];
      case 'whip_pan':
        return ["[$input]crop=w=iw*0.80:h=ih:x='(iw-ow)*(0.5+0.48*sin(t*4.1))':y=0[$output]"];
      case 'impact_shake':
        return ["[$input]crop=w=iw*0.91:h=ih*0.91:x='(iw-ow)*(0.5+0.23*sin(t*29)+0.20*sin(t*41))':y='(ih-oh)*(0.5+0.21*cos(t*33))'[$output]"];
      case 'motion_echo':
        // Real temporal mixing, not just stacking the current frame.
        // Calculate one short frame-history buffer, reuse it for two coloured
        // offset echoes, and preserve the original duration and frame rate.
        // Splitting the mixed output also avoids a second expensive tmix.
        return [
          '[$input]split=2[me_base][me_tail]',
          '[me_tail]tmix=frames=7,split=2[me_ta][me_tb]',
          '[me_ta]format=rgba,'
              'colorchannelmixer=rr=0.65:gg=1.0:bb=1.08:aa=0.38[me_a]',
          '[me_tb]format=rgba,'
              'colorchannelmixer=rr=1.0:gg=0.65:bb=0.88:aa=0.27[me_b]',
          '[me_base][me_a]overlay=x=-18:y=0:format=auto:'
              'shortest=1[me_mix]',
          '[me_mix][me_b]overlay=x=18:y=0:format=auto:'
              'shortest=1[$output]',
        ];
      case 'rgb_glitch':
        return ['[$input]chromashift=cbh=5:crh=-5:cbv=2:crv=-2[$output]'];
      case 'flash_beat':
        // Modest brightness pulses; avoid full-white strobing.
        return ["[$input]eq=brightness='0.07+0.09*sin(t*10)':eval=frame[$output]"];
      case 'freeze_focus':
        // Hold a frame briefly without lengthening the entire clip.
        final frame = ((seconds * 0.30 * 30).floor()).clamp(0, 100000);
        return ['[$input]fps=30,loop=loop=12:size=1:start=$frame,trim=duration=${seconds.toStringAsFixed(6)},setpts=PTS-STARTPTS[$output]'];
      case 'kaleidoscope':
        return [
          '[$input]split=2[k0][k1]',
          '[k0]crop=w=iw/2:h=ih:x=0:y=0[kl]',
          '[k1]crop=w=iw/2:h=ih:x=0:y=0,hflip[kr]',
          '[kl][kr]hstack=inputs=2[$output]',
        ];
      case 'dynamic_split':
        return [
          '[$input]split=4[d0][d1][d2][d3]',
          '[d0]scale=ceil(iw/4)*2:ceil(ih/4)*2[d00]',
          '[d1]scale=ceil(iw/4)*2:ceil(ih/4)*2,hflip[d01]',
          '[d2]scale=ceil(iw/4)*2:ceil(ih/4)*2,vflip[d10]',
          '[d3]scale=ceil(iw/4)*2:ceil(ih/4)*2,hflip,vflip[d11]',
          '[d00][d01]hstack=inputs=2[dt]',
          '[d10][d11]hstack=inputs=2[db]',
          '[dt][db]vstack=inputs=2[$output]',
        ];
      case 'vhs_retro':
        return ['[$input]noise=alls=11:allf=t+u,eq=saturation=0.77,chromashift=cbh=2:crh=-2[$output]'];
      case 'light_leak':
        return ["[$input]colorbalance=rs=0.25:gs=0.08:bs=-0.12,eq=brightness='0.04+0.035*sin(t*2.4)':eval=frame[$output]"];
      case 'cinema_frame':
        // Grade the picture and create an unmistakable inside-video frame,
        // including picture-edge strokes visible on already-dark footage.
        return ["[$input]eq=contrast=1.06:saturation=0.83,"
            "drawbox=x=0:y=0:w=iw:h=ih*0.14:color=black:t=fill,"
            "drawbox=x=0:y=ih*0.86:w=iw:h=ih*0.14:color=black:t=fill,"
            "drawbox=x=0:y=ih*0.14:w=iw:h=3:color=0xDCE1E6@0.75:t=fill,"
            "drawbox=x=0:y=ih*0.86-3:w=iw:h=3:"
            "color=0xDCE1E6@0.75:t=fill[$output]"];
      case 'neon_frame':
        return ["[$input]drawbox=x=7:y=7:w=iw-14:h=ih-14:color=0x00BFA5@0.95:t=6,drawbox=x=15:y=15:w=iw-30:h=ih-30:color=0x60FFF0@0.65:t=2,eq=brightness='0.015+0.025*sin(t*2.5)':eval=frame[$output]"];
      case 'film_strip':
        final holes = <String>[];
        for (var i = 0; i < 8; i++) {
          final y = ((i + .25) / 8).toStringAsFixed(5);
          holes.add('drawbox=x=iw*0.023:y=ih*$y:w=iw*0.042:'
              'h=ih*0.045:color=0xF0EBD8@0.9:t=fill');
          holes.add('drawbox=x=iw*0.935:y=ih*$y:w=iw*0.042:'
              'h=ih*0.045:color=0xF0EBD8@0.9:t=fill');
        }
        return ["[$input]noise=alls=5:allf=t,"
            "drawbox=x=0:y=0:w=iw*0.09:h=ih:color=black:t=fill,"
            "drawbox=x=iw*0.91:y=0:w=iw*0.09:h=ih:color=black:t=fill,"
            "${holes.join(',')}[$output]"];
      case 'floating_frame':
        return [
          '[$input]split=2[fsrc][bsrc]',
          '[fsrc]scale=ceil(iw*0.80/2)*2:ceil(ih*0.80/2)*2[floatfg]',
          '[bsrc]drawbox=x=0:y=0:w=iw:h=ih:color=0x1A222C:t=fill[floatbg]',
          "[floatbg][floatfg]overlay=x='(W-w)/2':"
              "y='(H-h)/2+8*sin(t*2)':eval=frame[$output]",
        ];
      default:
        throw ArgumentError.value(id, 'id', 'Unknown Magic effect');
    }
  }
}
