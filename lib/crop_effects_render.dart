import 'crop_effects_model.dart';
import 'crop_intro_effects_export.dart';
import 'crop_basic_effects_export.dart';
import 'crop_vibe_effects_painter.dart';
import 'crop_dynamic_effects_export.dart';
import 'crop_lighting_effects_export.dart';
import 'crop_amazing_next8_export.dart';
import 'crop_amazing_ten_export.dart';
import 'crop_amazing_effects_export.dart';
import 'crop_glitch_effects_export.dart';
import 'crop_distortion_effects_export.dart';
import 'crop_classic_effects_export.dart';
import 'crop_screen_effects_export.dart';
import 'crop_nature_effects_export.dart';
import 'crop_texture_effects_export.dart';
import 'crop_body_fx_names.dart';

/// Independent FFmpeg graph. The effect output is composited over the original
/// only inside its recorded time interval (seconds after speed processing).
/// Neither existing magic nor animation filters are modified.
class TiniEffectsRender {
  static bool _isSplitScreenName(String name) => const <String>{
    'Nine', 'Six', 'Four', 'Triptych', 'Focus Left', 'Focus Top',
  }.contains(name);

  static String _coverScaleCrop(int width, int height) =>
      'scale=$width:$height:force_original_aspect_ratio=increase,'
      'crop=$width:$height';

  static List<String> _splitScreenGraph({required String input,
      required String output, required String name, required int width,
      required int height, required int index}) {
    final graph = <String>[];
    if (name == 'Nine' || name == 'Six' || name == 'Four' || name == 'Triptych') {
      final cols = switch (name) {
        'Four' => 2,
        'Triptych' => 3,
        _ => 3,
      };
      final rows = switch (name) {
        'Nine' => 3,
        'Triptych' => 1,
        'Four' => 2,
        _ => 2,
      };
      final count = cols * rows;
      final cw = (width / cols).ceil();
      final ch = (height / rows).ceil();
      final slices = [for (var j = 0; j < count; j++) 'te_part${index}_$j'];
      graph.add('[$input]split=$count${slices.map((e) => '[$e]').join()}');
      for (var j = 0; j < count; j++) {
        graph.add('[${slices[j]}]${_coverScaleCrop(cw, ch)}[te_small${index}_$j]');
      }
      for (var row = 0; row < rows; row++) {
        graph.add('${[for (var col = 0; col < cols; col++)
          '[te_small${index}_${row * cols + col}]'].join()}'
          'hstack=inputs=$cols[te_row${index}_$row]');
      }
      graph.add('${[for (var row = 0; row < rows; row++) '[te_row${index}_$row]'].join()}'
        'vstack=inputs=$rows,scale=$width:$height,format=yuv420p[$output]');
      return graph;
    }
    switch (name) {
      case 'Focus Left':
        final leftW = (width * 0.66).round();
        final rightW = width - leftW;
        final topH = (height / 2).ceil();
        final bottomH = height - topH;
        graph.add('[$input]split=3[te_part${index}_0][te_part${index}_1][te_part${index}_2]');
        graph.add('[te_part${index}_0]${_coverScaleCrop(leftW, height)}[te_focus_left_${index}]');
        graph.add('[te_part${index}_1]${_coverScaleCrop(rightW, topH)}[te_focus_rt_${index}]');
        graph.add('[te_part${index}_2]${_coverScaleCrop(rightW, bottomH)}[te_focus_rb_${index}]');
        graph.add('[te_focus_rt_${index}][te_focus_rb_${index}]vstack=inputs=2[te_focus_right_${index}]');
        graph.add('[te_focus_left_${index}][te_focus_right_${index}]hstack=inputs=2,scale=$width:$height,format=yuv420p[$output]');
        return graph;
      case 'Focus Top':
        final topH = (height * 0.66).round();
        final bottomH = height - topH;
        final leftW = (width / 2).ceil();
        final rightW = width - leftW;
        graph.add('[$input]split=3[te_part${index}_0][te_part${index}_1][te_part${index}_2]');
        graph.add('[te_part${index}_0]${_coverScaleCrop(width, topH)}[te_focus_top_${index}]');
        graph.add('[te_part${index}_1]${_coverScaleCrop(leftW, bottomH)}[te_focus_bl_${index}]');
        graph.add('[te_part${index}_2]${_coverScaleCrop(rightW, bottomH)}[te_focus_br_${index}]');
        graph.add('[te_focus_bl_${index}][te_focus_br_${index}]hstack=inputs=2[te_focus_bottom_${index}]');
        graph.add('[te_focus_top_${index}][te_focus_bottom_${index}]vstack=inputs=2,scale=$width:$height,format=yuv420p[$output]');
        return graph;
      default:
        throw UnsupportedError('Subject tiling requires separate implementation');
    }
  }

  static String recipe(String name, int w, int h) {
    // Output dimensions are constant for use with blend and existing export.
    final pixel = 'pixelize=w=12:h=12';
    final pixelBig = 'pixelize=w=22:h=22';
    switch (name) {
      case 'Low Exposure': return 'eq=brightness=-0.23:contrast=1.08';
      case 'Zoom In': return "zoompan=z='min(1.4,1+on*0.015)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:s=${w}x$h:fps=30";
      case 'Switch Off': return 'eq=brightness=-0.55:saturation=0.35';
      case 'Switch On': return 'eq=brightness=0.28:contrast=1.15';
      case 'Rotate': return 'rotate=a=0.12:ow=iw:oh=ih:c=black';
      case 'Vertical': return 'vflip';
      case 'Horizon': return 'hflip';
      case 'Noise': return 'noise=alls=38:allf=t+u';
      case 'Halo Blur': return 'gblur=sigma=9';
      case 'Hazy': return 'gblur=sigma=4,eq=brightness=0.07:contrast=0.85';
      case 'Vertical Blur': return 'gblur=sigma=10:sigmaV=16';
      case 'Blurry Focus': return 'gblur=sigma=5';
      case 'Vignette': return 'vignette=angle=PI/3';
      case 'Blur': return 'gblur=sigma=12';
      case 'Fisheye III': return 'lenscorrection=cx=0.5:cy=0.5:k1=-0.38:k2=0.08';
      case 'Motion Blur': return 'tblend=all_mode=average';
      case 'Mini Zoom': return 'crop=iw*0.92:ih*0.92,scale=$w:$h';
      case 'Slanted Blur': return 'gblur=sigma=6,rotate=a=0.028:ow=iw:oh=ih';
      case 'TV Jitter': return 'noise=alls=29:allf=t,rgbashift=rh=5:bh=-4';
      case 'Zoom': return 'crop=iw*0.68:ih*0.68,scale=$w:$h';
      case 'HDR': return 'eq=contrast=1.32:saturation=1.28:gamma=1.08';
      case 'Disco': return 'hue=h=65:s=1.8';
      case 'Club Mood': return 'colorbalance=rs=0.24:bs=0.35';
      case 'Club lights': return 'hue=h=-95:s=2';
      case 'Shake 1': return 'crop=iw*0.94:ih*0.94:x=iw*0.03+sin(n*0.9)*6:y=ih*0.03,scale=$w:$h';
      case 'Shake 2': return 'crop=iw*0.92:ih*0.92:x=iw*0.04:y=ih*0.04+sin(n*1.4)*7,scale=$w:$h';
      case 'Shake': return 'crop=iw*0.93:ih*0.93:x=iw*0.035+sin(n*1.2)*5:y=ih*0.035+cos(n*0.8)*5,scale=$w:$h';
      case 'Trembling': return 'crop=iw*0.96:ih*0.96:x=iw*0.02+sin(n*2.1)*3:y=ih*0.02+cos(n*1.7)*3,scale=$w:$h';
      case 'Colorful': return 'eq=saturation=2.0:contrast=1.13';
      case 'Neon': return 'eq=saturation=2.6:contrast=1.4:brightness=-0.04';
      case 'Chromatic': return 'rgbashift=rh=7:bh=-7';
      case 'Flash II': return "eq=brightness='0.24*sin(t*28)':eval=frame";
      case 'Flash I': return "eq=brightness='0.13*sin(t*18)':eval=frame";
      case 'Black Flash II': return "eq=brightness='-0.25-0.25*sin(t*25)':eval=frame";
      case 'Black Flash': return "eq=brightness='-0.18-0.17*sin(t*17)':eval=frame";
      case 'White Flash': return "eq=brightness='0.2+0.26*sin(t*19)':eval=frame";
      case 'Flicker': return "eq=brightness='0.12*sin(t*48)':eval=frame";
      case 'Throb': return 'eq=saturation=1.48:contrast=1.17';
      case 'Beat': return "eq=brightness='0.08+0.1*sin(t*13)':eval=frame";
      case 'Pulse': return "zoompan=z='1.08+0.08*sin(on*0.32)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:s=${w}x$h:fps=30";
      case 'Strobe': return "eq=brightness='0.16*sin(t*65)':eval=frame";
      case 'Soft Light': return 'eq=brightness=0.07:contrast=0.86';
      case 'Dream Glow': return 'gblur=sigma=2,eq=brightness=0.10:saturation=1.18';
      case 'Red Glow': return 'colorbalance=rs=0.42:gs=-0.11:bs=-0.08';
      case 'Glow': return 'eq=brightness=0.16:contrast=0.92';
      case 'Vaporwave': return 'colorbalance=rs=0.25:bs=0.41:gs=-0.15';
      case 'Backlight': return 'eq=brightness=-0.14:contrast=1.38';
      case 'Lights': return 'eq=brightness=0.22:saturation=1.15';
      case 'Color Negati...': return 'negate';
      case 'Reverse': return 'hflip';
      case 'Surveillance ...': return 'hue=s=0,noise=alls=17:allf=t';
      case 'خلل': return 'rgbashift=rh=8:bh=-8,noise=alls=15:allf=t';
      case 'Fuzzy': return 'gblur=sigma=7,noise=alls=15:allf=t';
      case 'X-Signal': return 'rgbashift=rh=13:bh=-13,noise=alls=18:allf=t';
      case 'Edgy': return 'edgedetect=low=0.12:high=0.35';
      case 'Edge Glitch': return 'edgedetect=low=0.05:high=0.2,negate';
      case "70's": return 'eq=saturation=0.82:contrast=0.85,noise=alls=12:allf=t';
      case 'Waves 2': return 'lenscorrection=cx=0.5:cy=0.5:k1=0.26:k2=-0.12';
      case 'Ripples': return 'lenscorrection=cx=0.5:cy=0.5:k1=-0.25:k2=0.14';
      case 'Black Noise': return 'noise=alls=48:allf=t,eq=saturation=0';
      case 'Vintage Film': return 'eq=saturation=0.65:contrast=0.95:gamma=1.1,noise=alls=12:allf=t';
      case 'Film Freeze': return 'tblend=all_mode=average';
      case 'Retro Blue': return 'colorbalance=bs=0.30:rs=-0.14';
      case 'To B&W': return 'hue=s=0';
      case 'B&W Film': return 'hue=s=0,noise=alls=11:allf=t';
      case 'Black & White': return 'hue=s=0';
      case '1998': return 'eq=saturation=0.83:contrast=1.06,noise=alls=21:allf=t';
      case 'Vintage Video': return 'eq=saturation=0.72,noise=alls=30:allf=t';
      case 'Saturated Fil...': return 'eq=saturation=1.8:contrast=1.13';
      case 'Out of Focus': return 'gblur=sigma=11';
      case 'Noise I': return 'noise=alls=24:allf=t';
      case '70s': return 'eq=saturation=0.72:gamma_r=1.13:gamma_b=0.9';
      case 'DV': return 'noise=alls=20:allf=t,rgbashift=rh=2:bh=-2';
      case 'DV II': return 'noise=alls=32:allf=t,rgbashift=rh=4:bh=-3';
      case 'Camera Grid': return "drawgrid=w=iw/3:h=ih/3:t=2:c=white@0.45";
      case 'Viewfinder II': return 'vignette=angle=PI/2';
      case 'Cinema': return 'eq=contrast=1.23:saturation=0.87';
      case 'Camcorder II': return 'noise=alls=14:allf=t,eq=contrast=0.96';
      case 'Sunset 1': return 'colorbalance=rs=0.19:gs=0.08:bs=-0.18';
      case 'Sunset 2': return 'colorbalance=rs=0.3:gs=0.12:bs=-0.23';
      case 'Sunshine': return 'eq=brightness=0.16:saturation=1.18';
      case 'Heat Wave': return 'lenscorrection=cx=0.5:cy=0.5:k1=0.09:k2=-0.06';
      case 'Smog': return 'gblur=sigma=2,eq=contrast=0.78:brightness=0.10';
      case 'Silkscreen': return 'edgedetect=low=0.17:high=0.43';
      case 'blue mosaic': return '$pixel,colorbalance=bs=0.3';
      case 'Grain': return 'noise=alls=34:allf=t+u';
      case 'Blue Mosaic': return '$pixelBig,colorbalance=bs=0.37';
      // Split-screen requires real tiled frames; do not use a generic filter.
      case 'Nine': throw UnsupportedError('Subject tiling requires separate implementation');
      case 'Six': throw UnsupportedError('Subject tiling requires separate implementation');
      case 'Four': throw UnsupportedError('Subject tiling requires separate implementation');
      case 'Triptych': throw UnsupportedError('Subject tiling requires separate implementation');
      case 'Focus Left': throw UnsupportedError('Subject tiling requires separate implementation');
      case 'Focus Top': throw UnsupportedError('Subject tiling requires separate implementation');
      case 'تحسين لون': return 'eq=contrast=1.1:saturation=1.15';
      case 'bluegrain': return 'noise=alls=19:allf=t,colorbalance=bs=0.2';
      case 'vintage look': return 'eq=saturation=0.78:contrast=0.9';
      case 'Lux': return 'eq=contrast=1.28:brightness=0.04';
      case 'Soft Latte': return 'colorbalance=rs=0.13:gs=0.07:bs=-0.07';
      case 'Pixelate': return pixel;
      default: throw ArgumentError.value(name, 'effect', 'Effect not implemented');
    }
  }

  static List<String> filterGraph({required String input, required String output,
      required List<TiniAppliedEffect> effects, required double seconds,
      required int width, required int height}) {
    if (effects.isEmpty) return ['[$input]null[$output]'];
    // These effects are composited in later passes. Do not resize and pad
    // every frame an extra time just to run a graph containing no filters.
    // The normal final output stage still performs the original scaling.
    final externalOnly = effects.every((effect) {
      final descriptor = effect.descriptor;
      if (descriptor == null || !descriptor.available) return false;
      return descriptor.category == TiniBodyFxNames.category ||
          descriptor.category == TiniVibeEffectsPainter.category ||
          (descriptor.category == 'مؤثر شكل الوجه' &&
              {'Bobsledder', '2014 Dog Ch...'}.contains(descriptor.name));
    });
    if (externalOnly) return ['[$input]null[$output]'];
    final graph = <String>[];
    // A zoompan effect outputs a fixed 30-fps stream. Normalize its source
    // and sibling branches to the same clock before any split/blend; this
    // preserves clip duration even when the camera recorded at 60 fps.
    final requires30Fps = effects.any((effect) {
      final descriptor = effect.descriptor;
      return descriptor?.category == TiniIntroEffectsExport.category ||
          (descriptor?.category == TiniBasicEffectsExport.category &&
          TiniBasicEffectsExport.frameRateDependent.contains(descriptor?.name)) ||
          (descriptor?.category == TiniAmazingTenExport.category &&
          TiniAmazingTenExport.frameRateDependent.contains(descriptor?.name)) ||
          (descriptor?.category == TiniDynamicEffectsExport.category &&
          TiniDynamicEffectsExport.frameRateDependent.contains(descriptor?.name)) ||
          (descriptor?.category == TiniClassicEffectsExport.category &&
          TiniClassicEffectsExport.frameRateDependent.contains(descriptor?.name));
    });
    graph.add('[$input]${requires30Fps ? 'fps=30,' : ''}'
        'scale=$width:$height:force_original_aspect_ratio=decrease,'
        'pad=$width:$height:(ow-iw)/2:(oh-ih)/2,setsar=1,format=yuv420p[te_source]');
    var previous = 'te_source';
    var index = 0;
    for (final effect in effects) {
      final descriptor = effect.descriptor;
      if (descriptor == null || !descriptor.available) {
        throw StateError('Unsupported Tini effect: ${effect.id}');
      }
      // Body effects are composited later from REAL person segmentation masks
      // on the final speed-adjusted stream, never from whole-frame filters.
      if (descriptor.category == TiniBodyFxNames.category ||
          (descriptor.category == 'مؤثر شكل الوجه' &&
              {'Bobsledder', '2014 Dog Ch...'}.contains(descriptor.name))) continue;
      final start = effect.startSeconds.clamp(0.0, seconds).toDouble();
      final end = effect.endSeconds.clamp(0.0, seconds).toDouble();
      if (end <= start) continue;
      // Vibe is alpha-composited as a separate video pass using the SAME
      // CustomPainter as preview; applying an unrelated colour filter here
      // would be visually incorrect and duplicate the effect.
      if (descriptor.category == TiniVibeEffectsPainter.category) continue;
      final base = 'te_base$index';
      final branch = 'te_branch$index';
      final edited = 'te_edited$index';
      final mixed = 'te_mixed$index';
      graph.add('[$previous]split=2[$base][$branch]');
      if (_isSplitScreenName(descriptor.name)) {
        graph.addAll(_splitScreenGraph(input: branch, output: edited,
          name: descriptor.name, width: width, height: height, index: index));
      } else if (descriptor.category == TiniIntroEffectsExport.category) {
        graph.addAll(TiniIntroEffectsExport.filterGraph(
          input: branch, output: edited, name: descriptor.name,
          id: effect.id, startSeconds: start, endSeconds: end,
          width: width, height: height, index: index));
      } else if (descriptor.category == TiniBasicEffectsExport.category) {
        graph.addAll(TiniBasicEffectsExport.filterGraph(
          input: branch, output: edited, name: descriptor.name,
          startSeconds: start, endSeconds: end,
          width: width, height: height, index: index));
      } else if (descriptor.category == TiniDynamicEffectsExport.category) {
        graph.addAll(TiniDynamicEffectsExport.filterGraph(
          input: branch, output: edited, name: descriptor.name,
          startSeconds: start, endSeconds: end,
          width: width, height: height, index: index));
      } else if (descriptor.category == TiniLightingEffectsExport.category) {
        graph.addAll(TiniLightingEffectsExport.filterGraph(
          input: branch, output: edited, name: descriptor.name,
          startSeconds: start, endSeconds: end,
          width: width, height: height, index: index));
      } else if (descriptor.category == TiniAmazingEffectsExport.category &&
          TiniAmazingEffectsExport.supported.contains(descriptor.name)) {
        graph.addAll(TiniAmazingEffectsExport.filterGraph(
          input: branch, output: edited, name: descriptor.name,
          startSeconds: start, endSeconds: end,
          width: width, height: height, index: index));
      } else if (descriptor.category == TiniAmazingNextEightExport.category &&
          TiniAmazingNextEightExport.supported.contains(descriptor.name)) {
        graph.addAll(TiniAmazingNextEightExport.filterGraph(
          input: branch, output: edited, name: descriptor.name,
          startSeconds: start, endSeconds: end,
          width: width, height: height, index: index));
      } else if (descriptor.category == TiniGlitchEffectsExport.category) {
        graph.addAll(TiniGlitchEffectsExport.filterGraph(
          input: branch, output: edited, name: descriptor.name,
          startSeconds: start, endSeconds: end,
          width: width, height: height, index: index));
      } else if (descriptor.category == TiniDistortionEffectsExport.category) {
        graph.addAll(TiniDistortionEffectsExport.filterGraph(
          input: branch, output: edited, name: descriptor.name,
          startSeconds: start, endSeconds: end,
          width: width, height: height, index: index));
      } else if (descriptor.category == TiniClassicEffectsExport.category) {
        graph.addAll(TiniClassicEffectsExport.filterGraph(
          input: branch, output: edited, name: descriptor.name,
          startSeconds: start, endSeconds: end,
          width: width, height: height, index: index));
      } else if (descriptor.category == TiniScreenEffectsExport.category) {
        graph.addAll(TiniScreenEffectsExport.filterGraph(
          input: branch, output: edited, name: descriptor.name,
          startSeconds: start, endSeconds: end,
          width: width, height: height, index: index));
      } else if (descriptor.category == TiniNatureEffectsExport.category) {
        graph.addAll(TiniNatureEffectsExport.filterGraph(
          input: branch, output: edited, name: descriptor.name,
          startSeconds: start, endSeconds: end,
          width: width, height: height, index: index));
      } else if (descriptor.category == TiniTextureEffectsExport.category) {
        graph.addAll(TiniTextureEffectsExport.filterGraph(
          input: branch, output: edited, name: descriptor.name,
          startSeconds: start, endSeconds: end,
          width: width, height: height, index: index));
      } else if (descriptor.category == TiniAmazingTenExport.category &&
          TiniAmazingTenExport.supported.contains(descriptor.name)) {
        graph.addAll(TiniAmazingTenExport.filterGraph(
          input: branch, output: edited, name: descriptor.name,
          startSeconds: start, endSeconds: end,
          width: width, height: height, index: index));
      } else {
        final recipeText = recipe(descriptor.name, width, height);
        graph.add('[$branch]$recipeText,format=yuv420p[$edited]');
      }
      // The time window is constant across a frame. FFmpeg's timeline selector
      // copies the chosen branch without interpreting a condition per pixel.
      graph.add('[$base][$edited]blend=all_mode=normal:all_opacity=0:enable='
          "'between(t,${start.toStringAsFixed(4)},${end.toStringAsFixed(4)})'"
          '[$mixed]');
      previous = mixed;
      index++;
    }
    graph.add('[$previous]null[$output]');
    return graph;
  }
}
