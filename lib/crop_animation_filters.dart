import 'crop_animation_model.dart';

/// Time-local FFmpeg filters; they do not alter audio or the clip's duration.
/// Exported animations are composited after Magic and before final scaling.
class CropAnimationFilters {
  static List<String> filterGraph({required String input,
    required String output, required CropAnimationSettings settings,
    required double seconds, required int width, required int height}) {
    if (!settings.hasEffects || seconds <= 0) return ['[$input]null[$output]'];
    final filters = <String>[];
    if (settings.start != null) {
      filters.addAll(_filter(settings.start!,
          settings.startSeconds.clamp(.1, seconds).toDouble(), seconds, width, height));
    }
    if (settings.end != null) {
      filters.addAll(_filter(settings.end!,
          settings.endSeconds.clamp(.1, seconds).toDouble(), seconds, width, height));
    }
    if (settings.group != null) {
      filters.addAll(_filter(settings.group!,
          settings.groupSeconds.clamp(.2, seconds > .2 ? seconds : .2).toDouble(), seconds, width, height));
    }
    if (filters.isEmpty) return ['[$input]null[$output]'];
    return ['[$input]${filters.join(',')}[$output]'];
  }

  static List<String> _filter(String id, double duration, double total, int width, int height) {
    final d = duration.toStringAsFixed(6);
    final out = (total - duration).clamp(0.0, total).toStringAsFixed(6);
    switch (id) {
      case 'fade_in': return ['fade=t=in:st=0:d=$d'];
      case 'fade_out': return ['fade=t=out:st=$out:d=$d'];
      // Pad first so translated pixels reveal an empty canvas, just as the
      // editor preview does. Crop x/y are evaluated for each decoded frame.
      case 'slide_in':
        return ['pad=iw*2:ih:iw:0:color=black',
          "crop=w=iw/2:h=ih:x='ow*min(t/$d,1)':y=0"];
      case 'slide_in_left':
        return ['pad=iw*2:ih:0:0:color=black',
          "crop=w=iw/2:h=ih:x='ow*(1-min(t/$d,1))':y=0"];
      case 'slide_out':
        return ['pad=iw*2:ih:0:0:color=black',
          "crop=w=iw/2:h=ih:x='ow*min(max((t-$out)/$d,0),1)':y=0"];
      case 'slide_out_left':
        return ['pad=iw*2:ih:iw:0:color=black',
          "crop=w=iw/2:h=ih:x='ow*(1-min(max((t-$out)/$d,0),1))':y=0"];
      case 'rise_in':
        return ['pad=iw:ih*2:0:ih:color=black',
          "crop=w=iw:h=ih/2:x=0:y='oh*min(t/$d,1)'",
          'fade=t=in:st=0:d=$d'];
      case 'fall_out':
        return ['pad=iw:ih*2:0:0:color=black',
          "crop=w=iw:h=ih/2:x=0:y='oh*min(max((t-$out)/$d,0),1)'",
          'fade=t=out:st=$out:d=$d'];
      case 'zoom_in':
        return ["zoompan=z='1.45-0.45*min(on/($d*30),1)':"
          "x='(iw-iw/zoom)/2':y='(ih-ih/zoom)/2':d=1:"
          "s=${width}x$height:fps=30", 'fade=t=in:st=0:d=$d'];
      case 'zoom_out':
        return ["zoompan=z='1+0.45*min(max((on/30-$out)/$d,0),1)':"
          "x='(iw-iw/zoom)/2':y='(ih-ih/zoom)/2':d=1:"
          "s=${width}x$height:fps=30", 'fade=t=out:st=$out:d=$d'];
      case 'fold_in': return [
        "rotate='-0.15*(1-min(t/$d,1))':fillcolor=black",
        'fade=t=in:st=0:d=$d'];
      case 'fold_out': return [
        "rotate='0.15*min(max((t-$out)/$d,0),1)':fillcolor=black",
        'fade=t=out:st=$out:d=$d'];
      case 'dynamic_shake':
        return ['scale=ceil(iw*1.12/2)*2:ceil(ih*1.12/2)*2',
          "crop=w=iw/1.12:h=ih/1.12:"
          "x='(iw-ow)*(0.5+0.37*sin(t*45))':"
          "y='(ih-oh)*(0.5+0.32*cos(t*37))'"];
      case 'vertical_glitch':
        return ['scale=ceil(iw*1.14/2)*2:ceil(ih*1.14/2)*2',
          "crop=w=iw/1.14:h=ih/1.14:"
          "x='(iw-ow)/2':y='(ih-oh)*(0.5+0.40*sin(t*48))'"];
      case 'pendulum':
        return ["rotate='0.13*sin(t*2*PI/$d)':fillcolor=black"];
      case 'pulse':
        return ["zoompan=z='1.04+0.08*(1+sin(on*2*PI/(30*$d)))/2':"
          "x='(iw-iw/zoom)/2':y='(ih-ih/zoom)/2':d=1:"
          "s=${width}x$height:fps=30"];
      case 'float':
        return ['scale=ceil(iw*1.10/2)*2:ceil(ih*1.10/2)*2',
          "crop=w=iw/1.10:h=ih/1.10:x='(iw-ow)/2':"
          "y='(ih-oh)*(0.5+0.4*sin(t*2*PI/$d))'"];
      case 'rock':
        return ["rotate='0.045*sin(t*4*PI/$d)':fillcolor=black"];
      // Additional entrance animations (0..duration).
      case 'spin_in':
        return ["rotate='2*PI*(1-min(t/$d,1))':fillcolor=black", 'fade=t=in:st=0:d=$d'];
      case 'drop_in':
        return ['pad=iw:ih*2:0:0:color=black',
          "crop=w=iw:h=ih/2:x=0:y='oh*(1-min(t/$d,1))'"];
      case 'diagonal_in':
        return ['pad=iw*2:ih*2:iw:ih:color=black',
          "crop=w=iw/2:h=ih/2:x='ow*min(t/$d,1)':y='oh*min(t/$d,1)'"];
      case 'mirror_in':
        return ["hflip=enable='lt(t,$d*0.5)'", 'fade=t=in:st=0:d=$d'];
      case 'blur_in':
        return ["boxblur=luma_radius=7:luma_power=1:enable='lt(t,$d*0.55)'",
          'fade=t=in:st=0:d=$d'];
      case 'flash_in':
        return ["eq=brightness='0.55*(1-min(t/$d,1))':eval=frame"];
      case 'mono_in':
        return ["hue=s='min(t/$d,1)'"];
      case 'negative_in':
        return ["negate=enable='lt(t,$d*0.55)'", 'fade=t=in:st=0:d=$d'];
      case 'bounce_in':
        return ["zoompan=z='1+0.45*(1-min(on/(30*$d),1))-0.08*sin(2*PI*min(on/(30*$d),1))':"
            "x='(iw-iw/zoom)/2':y='(ih-ih/zoom)/2':d=1:s=${width}x$height:fps=30"];
      case 'shutter_in':
        return ["vflip=enable='lt(t,$d*0.5)'", 'fade=t=in:st=0:d=$d'];
      // Additional exit animations (total-duration..total).
      case 'spin_out':
        return ["rotate='2*PI*min(max((t-$out)/$d,0),1)':fillcolor=black",
          'fade=t=out:st=$out:d=$d'];
      case 'lift_out':
        return ['pad=iw:ih*2:0:ih:color=black',
          "crop=w=iw:h=ih/2:x=0:y='oh*(1-min(max((t-$out)/$d,0),1))'"];
      case 'diagonal_out':
        return ['pad=iw*2:ih*2:iw:ih:color=black',
          "crop=w=iw/2:h=ih/2:x='ow*(1-min(max((t-$out)/$d,0),1))':"
            "y='oh*(1-min(max((t-$out)/$d,0),1))'"];
      case 'mirror_out':
        return ["hflip=enable='gte(t,$out+0.5*$d)'", 'fade=t=out:st=$out:d=$d'];
      case 'blur_out':
        return ["boxblur=luma_radius=7:luma_power=1:enable='gte(t,$out+0.45*$d)'",
          'fade=t=out:st=$out:d=$d'];
      case 'flash_out':
        return ["eq=brightness='0.55*min(max((t-$out)/$d,0),1)':eval=frame"];
      case 'mono_out':
        return ["hue=s='1-min(max((t-$out)/$d,0),1)'"];
      case 'negative_out':
        return ["negate=enable='gte(t,$out+0.45*$d)'", 'fade=t=out:st=$out:d=$d'];
      case 'bounce_out':
        return ["zoompan=z='1+0.45*min(max((on/30-$out)/$d,0),1)':"
            "x='(iw-iw/zoom)/2':y='(ih-ih/zoom)/2':d=1:s=${width}x$height:fps=30",
          'fade=t=out:st=$out:d=$d'];
      case 'shutter_out':
        return ["vflip=enable='gte(t,$out+0.5*$d)'", 'fade=t=out:st=$out:d=$d'];
      // Ten independent repeating group looks. The adjustable period controls
      // both the visual oscillation and the coloured timeline subdivisions.
      case 'orbit':
        return ['scale=ceil(iw*1.12/2)*2:ceil(ih*1.12/2)*2',
          "crop=w=iw/1.12:h=ih/1.12:"
          "x='(iw-ow)*(0.5+0.44*cos(2*PI*t/$d))':"
          "y='(ih-oh)*(0.5+0.44*sin(2*PI*t/$d))'"];
      case 'full_spin':
        return ["rotate='2*PI*t/$d':fillcolor=black"];
      case 'rainbow':
        return ["hue=h='360*t/$d'"];
      case 'strobe':
        return ["eq=brightness='if(lt(mod(t,$d),$d/6),0.50,0)':eval=frame"];
      case 'flip_h_loop':
        return ["hflip=enable='lt(mod(t,$d),$d/2)'"];
      case 'flip_v_loop':
        return ["vflip=enable='lt(mod(t,$d),$d/2)'"];
      case 'negative_loop':
        return ["negate=enable='lt(mod(t,$d),$d/2)'"];
      case 'greyscale_loop':
        return ["hue=s='if(lt(mod(t,$d),$d/2),0,1)'"];
      case 'grid_flash':
        return ["drawgrid=w=iw/12:h=ih/12:t=2:c=white@0.45:"
            "enable='lt(mod(t,$d),$d/2)'"];
      case 'exposure_wave':
        return ["eq=brightness='0.22*sin(2*PI*t/$d)':eval=frame"];
      default: throw ArgumentError.value(id, 'id', 'Unknown animation preset');
    }
  }
}
