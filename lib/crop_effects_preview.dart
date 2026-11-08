import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'crop_effects_model.dart';
import 'crop_color_filters.dart';
import 'crop_intro_effects_preview.dart';
import 'crop_basic_effects_preview.dart';
import 'crop_vibe_effects_painter.dart';
import 'crop_dynamic_effects_preview.dart';
import 'crop_lighting_effects_preview.dart';
import 'crop_amazing_next8_preview.dart';
import 'crop_amazing_ten_preview.dart';
import 'crop_amazing_effects_preview.dart';
import 'crop_glitch_effects_preview.dart';
import 'crop_distortion_effects_preview.dart';
import 'crop_classic_effects_preview.dart';
import 'crop_screen_effects_preview.dart';
import 'crop_nature_effects_preview.dart';
import 'crop_texture_effects_preview.dart';
import 'crop_body_fx_engine.dart';
import 'crop_sled_effect.dart';
import 'crop_scene_fx_engine.dart';

/// Lightweight live preview for effects with a matching Flutter primitive.
/// Complex FFmpeg-only transforms are not spoofed with an unrelated image.
class TiniEffectsPreview extends StatelessWidget {
  final List<TiniAppliedEffect> effects;
  final double elapsedSeconds;
  final Widget child;
  final CropFilterSelection colorFilter;
  final String? clipId;
  final VideoPlayerController? sledSourceController;
  final String? sledSourcePath;
  final int? sledSourceTimeMs;
  const TiniEffectsPreview({super.key, required this.effects,
      required this.elapsedSeconds, required this.child, this.clipId,
      this.colorFilter = const CropFilterSelection(),
      this.sledSourceController, this.sledSourcePath, this.sledSourceTimeMs});

  static Widget _matrix(Widget child, double saturation, double brightness) {
    final k = 1 - saturation;
    final b = brightness * 255;
    return ColorFiltered(colorFilter: ColorFilter.matrix([
      .2126 * k + saturation, .7152 * k, .0722 * k, 0, b,
      .2126 * k, .7152 * k + saturation, .0722 * k, 0, b,
      .2126 * k, .7152 * k, .0722 * k + saturation, 0, b,
      0, 0, 0, 1, 0,
    ]), child: child);
  }

  static bool _isSplitScreenName(String name) => const <String>{
    'Nine', 'Six', 'Four', 'Triptych', 'Focus Left', 'Focus Top',
  }.contains(name);

  static Widget _splitCell(Widget source, double width, double height,
      {Alignment alignment = Alignment.center}) {
    return ClipRect(child: FittedBox(
      fit: BoxFit.cover,
      alignment: alignment,
      child: SizedBox(width: width, height: height, child: source),
    ));
  }

  static Widget _buildSplitScreen(String name, Widget source) {
    return LayoutBuilder(builder: (context, bounds) {
      final w = bounds.maxWidth;
      final h = bounds.maxHeight;
      Widget cell({Alignment alignment = Alignment.center}) =>
          _splitCell(source, w, h, alignment: alignment);
      switch (name) {
        case 'Nine':
          return Column(children: [for (var row = 0; row < 3; row++)
            Expanded(child: Row(children: [for (var col = 0; col < 3; col++)
              Expanded(child: cell()),
            ])),
          ]);
        case 'Six':
          return Column(children: [for (var row = 0; row < 2; row++)
            Expanded(child: Row(children: [for (var col = 0; col < 3; col++)
              Expanded(child: cell()),
            ])),
          ]);
        case 'Four':
          return Column(children: [for (var row = 0; row < 2; row++)
            Expanded(child: Row(children: [for (var col = 0; col < 2; col++)
              Expanded(child: cell()),
            ])),
          ]);
        case 'Triptych':
          return Row(children: [for (var i = 0; i < 3; i++) Expanded(child: cell())]);
        case 'Focus Left':
          return Row(children: [
            Expanded(flex: 2, child: cell(alignment: Alignment.centerLeft)),
            Expanded(child: Column(children: [
              Expanded(child: cell(alignment: Alignment.topRight)),
              Expanded(child: cell(alignment: Alignment.bottomRight)),
            ])),
          ]);
        case 'Focus Top':
          return Column(children: [
            Expanded(flex: 2, child: cell(alignment: Alignment.topCenter)),
            Expanded(child: Row(children: [
              Expanded(child: cell(alignment: Alignment.bottomLeft)),
              Expanded(child: cell(alignment: Alignment.bottomRight)),
            ])),
          ]);
        default:
          return source;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget video = child;
    for (final effect in effects) {
      if (!effect.active(elapsedSeconds)) continue;
      final desc = effect.descriptor;
      if (desc == null || !desc.available) continue;
      if (desc.category == TiniBodyFxEngine.category) continue;
      final name = desc.name;
      if (desc.category == TiniFaceSceneFx.category &&
          name == TiniFaceSceneFx.dogName && sledSourceController != null &&
          sledSourcePath != null && sledSourcePath!.isNotEmpty) {
        video = TiniFaceScenePreview(
          key: ValueKey('tini_dog_scene_${clipId ?? ''}'),
          sourceController: sledSourceController!,
          sourcePath: sledSourcePath!,
          sourceTimeMs: sledSourceTimeMs ?? (elapsedSeconds * 1000).round(),
          effectSeconds: elapsedSeconds - effect.startSeconds,
          original: video,
        );
      } else if (desc.category == TiniSledEffect.category &&
          name == TiniSledEffect.name && sledSourceController != null &&
          sledSourcePath != null && sledSourcePath!.isNotEmpty) {
        video = TiniSledPreview(
          key: ValueKey('tini_sled_${clipId ?? ''}'),
          sourceController: sledSourceController!,
          sourcePath: sledSourcePath!,
          sourceTimeMs: sledSourceTimeMs ?? (elapsedSeconds * 1000).round(),
          effectSeconds: elapsedSeconds - effect.startSeconds,
          original: video,
        );
      } else if (desc.category == 'مقدمة وخاتمة') {
        video = TiniIntroEffectsPreview.apply(name: name, id: effect.id,
          child: video, elapsed: elapsedSeconds,
          start: effect.startSeconds, end: effect.endSeconds);
      } else if (desc.category == 'أساسية') {
        video = TiniBasicEffectsPreview.apply(name: name, child: video,
          elapsed: elapsedSeconds, start: effect.startSeconds,
          end: effect.endSeconds);
      } else if (desc.category == TiniDynamicEffectsPreview.category) {
        video = TiniDynamicEffectsPreview.apply(name: name, child: video,
          elapsed: elapsedSeconds, start: effect.startSeconds,
          end: effect.endSeconds);
      } else if (desc.category == TiniLightingEffectsPreview.category) {
        video = TiniLightingEffectsPreview.apply(name: name, child: video,
          elapsed: elapsedSeconds, start: effect.startSeconds,
          end: effect.endSeconds);
      } else if (desc.category == TiniAmazingEffectsPreview.category &&
          TiniAmazingEffectsPreview.supported.contains(name)) {
        video = TiniAmazingEffectsPreview.apply(name: name, child: video,
          elapsed: elapsedSeconds, start: effect.startSeconds,
          end: effect.endSeconds);
      } else if (desc.category == TiniAmazingNextEightPreview.category &&
          TiniAmazingNextEightPreview.supported.contains(name)) {
        video = TiniAmazingNextEightPreview.apply(name: name, child: video,
          elapsed: elapsedSeconds, start: effect.startSeconds,
          end: effect.endSeconds);
      } else if (desc.category == TiniAmazingTenPreview.category &&
          TiniAmazingTenPreview.supported.contains(name)) {
        video = TiniAmazingTenPreview.apply(name: name, child: video,
          elapsed: elapsedSeconds, start: effect.startSeconds,
          end: effect.endSeconds);
      } else if (desc.category == TiniGlitchEffectsPreview.category) {
        video = TiniGlitchEffectsPreview.apply(name: name, child: video,
          elapsed: elapsedSeconds, start: effect.startSeconds,
          end: effect.endSeconds);
      } else if (desc.category == TiniDistortionEffectsPreview.category) {
        video = TiniDistortionEffectsPreview.apply(name: name, child: video,
          elapsed: elapsedSeconds, start: effect.startSeconds,
          end: effect.endSeconds);
      } else if (desc.category == TiniClassicEffectsPreview.category) {
        video = TiniClassicEffectsPreview.apply(name: name, child: video,
          elapsed: elapsedSeconds, start: effect.startSeconds,
          end: effect.endSeconds);
      } else if (desc.category == TiniScreenEffectsPreview.category) {
        video = TiniScreenEffectsPreview.apply(name: name, child: video,
          elapsed: elapsedSeconds, start: effect.startSeconds,
          end: effect.endSeconds);
      } else if (desc.category == TiniNatureEffectsPreview.category) {
        video = TiniNatureEffectsPreview.apply(name: name, child: video,
          elapsed: elapsedSeconds, start: effect.startSeconds,
          end: effect.endSeconds);
      } else if (desc.category == TiniTextureEffectsPreview.category) {
        video = TiniTextureEffectsPreview.apply(name: name, child: video,
          elapsed: elapsedSeconds, start: effect.startSeconds,
          end: effect.endSeconds);
      } else if (_isSplitScreenName(name)) {
        video = _buildSplitScreen(name, video);
      } else if (name == 'To B&W' || name == 'Black & White' || name == 'B&W Film' ||
          name == 'Black Noise' || name == 'Surveillance ...') {
        video = _matrix(video, 0, 0);
      } else if (name.contains('Blur') || name == 'Hazy' ||
          name == 'Fuzzy' || name == 'Out of Focus' || name == 'Smog') {
        video = ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6), child: video);
      } else if (name == 'Zoom' || name == 'Zoom In' || name == 'Mini Zoom' || name == 'Pulse') {
        final inTime = (elapsedSeconds - effect.startSeconds).clamp(0.0, 2.0);
        final scale = name == 'Mini Zoom' ? 1.08 : (name == 'Zoom' ? 1.45 :
          name == 'Zoom In' ? 1.0 + inTime * .18 :
          1.08 + .08 * math.sin(elapsedSeconds * 9.6));
        video = Transform.scale(scale: scale, child: video);
      } else if (name == 'Horizon' || name == 'Reverse') {
        video = Transform.flip(flipX: true, child: video);
      } else if (name == 'Vertical') {
        video = Transform.flip(flipY: true, child: video);
      } else if (name == 'Rotate') {
        video = Transform.rotate(angle: .12, child: video);
      } else if (name == 'Black Flash' || name == 'Black Flash II') {
        video = _matrix(video, .8,
            -.2 - .15 * math.sin(elapsedSeconds * (name == 'Black Flash II' ? 25 : 17)));
      } else if (name == 'Low Exposure' || name == 'Switch Off') {
        video = _matrix(video, .75, -.22);
      } else if (name == 'Flash I' || name == 'Flash II' ||
          name == 'White Flash' || name == 'Strobe' || name == 'Flicker' ||
          name == 'Beat') {
        final rate = name == 'Flicker' ? 48.0 : name == 'Strobe' ? 65.0 :
          name == 'Flash II' ? 28.0 : name == 'Flash I' ? 18.0 :
          name == 'Beat' ? 13.0 : 19.0;
        video = _matrix(video, 1.05, .19 * math.sin(elapsedSeconds * rate));
      } else if (name == 'Switch On' || name == 'Sunshine') {
        video = _matrix(video, 1.12, .23);
      } else if (name == 'Negative Gra...' || name == 'Color Negati...' || name == 'Strobe') {
        video = ColorFiltered(colorFilter: const ColorFilter.matrix([
          -1, 0, 0, 0, 255, 0, -1, 0, 0, 255, 0, 0, -1, 0, 255, 0, 0, 0, 1, 0]), child: video);
      } else if (name == 'Shake' || name == 'Shake 1' || name == 'Shake 2' || name == 'Trembling') {
        final x = 4.0 * math.sin(elapsedSeconds * 35);
        video = Transform.translate(offset: Offset(x, 3 * math.cos(elapsedSeconds * 31)), child: video);
      } else if (name == 'Grain' || name == 'Vintage Film' || name == '1998' ||
          name == 'Vintage Video' || name == '70s' || name == '70\'s') {
        video = _matrix(video, .7, .015);
      } else if (name == 'Red Glow' || name == 'Sunset 1' || name == 'Sunset 2') {
        video = ColorFiltered(colorFilter: const ColorFilter.mode(
            Color(0x44EE5028), BlendMode.screen), child: video);
      } else if (name == 'Retro Blue' || name == 'Vaporwave' || name == 'bluegrain') {
        video = ColorFiltered(colorFilter: const ColorFilter.mode(
            Color(0x445C59FF), BlendMode.screen), child: video);
      } else if (name == 'blue mosaic' || name == 'Blue Mosaic' || name == 'Pixelate') {
        video = ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: 2, sigmaY: 2), child: video);
      } else if (name == 'Soft Light' || name == 'Lights' || name == 'Glow' ||
          name == 'Dream Glow' || name == 'تحسين لون' || name == 'Lux') {
        video = _matrix(video, 1.10, .07);
      } else if (name == 'Colorful' || name == 'HDR' || name == 'Neon' ||
          name == 'Saturated Fil...' || name == 'Disco') {
        video = _matrix(video, 1.6, 0);
      }
    }
    // Overlay particle sprites last, matching their post-composition in export.
    final vibe = effects.where((effect) => effect.active(elapsedSeconds) &&
        effect.descriptor?.category == TiniVibeEffectsPainter.category &&
        effect.descriptor?.available == true).toList(growable: false);
    if (vibe.isNotEmpty) {
      video = Stack(fit: StackFit.passthrough, children: [
        video,
        Positioned.fill(child: IgnorePointer(child: CustomPaint(
          painter: TiniVibeEffectsPainter(effects: vibe, seconds: elapsedSeconds)))),
      ]);
    }
    // Render the most recent tracked VIDEO frame directly in Flutter's canvas.
    // No full-video preprocessing, PNG sequence, or playback suspension.
    if (TiniBodyFxEngine.hasBodyEffects(effects)) {
      video = Stack(fit: StackFit.expand, children: [
        video,
        Positioned.fill(child: IgnorePointer(child: ValueListenableBuilder<int>(
          valueListenable: TiniBodyFxEngine.liveRevision,
          builder: (context, revision, _) => CustomPaint(
            painter: _TiniLiveBodyPainter(clipId, effects, elapsedSeconds,
                revision),
          ),
        ))),
      ]);
    }
    return ClipRect(child: colorFilter.apply(video));
  }
}


/// Body overlays share the same effect painter as export, without disk frames.
class _TiniLiveBodyPainter extends CustomPainter {
  final String? clipId;
  final List<TiniAppliedEffect> effects;
  final double elapsedSeconds;
  final int revision;
  const _TiniLiveBodyPainter(this.clipId, this.effects,
      this.elapsedSeconds, this.revision);

  @override
  void paint(Canvas canvas, Size size) {
    TiniBodyFxEngine.paintLive(canvas, size, clipId, effects, elapsedSeconds);
  }

  @override
  bool shouldRepaint(covariant _TiniLiveBodyPainter oldDelegate) =>
      oldDelegate.revision != revision ||
      oldDelegate.elapsedSeconds != elapsedSeconds ||
      oldDelegate.clipId != clipId ||
      !sameTiniEffects(oldDelegate.effects, effects);
}
