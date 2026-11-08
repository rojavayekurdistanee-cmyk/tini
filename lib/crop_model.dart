import 'crop_speed_model.dart';
import 'crop_retouch_model.dart';
import 'crop_color_filters.dart';
import 'crop_animation_model.dart';
import 'crop_background_model.dart';
import 'crop_effects_model.dart';
import 'package:flutter/material.dart';

class CropClip {
  final String id;
  final Duration startTime;
  final Duration endTime;
  final double startFraction; // 0.0 to 1.0
  final double endFraction; // 0.0 to 1.0
  final CropSpeed speed;
  final CropRetouchSettings retouch;
  final CropFilterSelection colorFilter;
  final CutoutSettings? cutout;
  final String? backgroundPath;
  final String? magicEffectId; // null = no Magic effect on this segment.
  final CropAnimationSettings animations;
  final List<TiniAppliedEffect> videoEffects; // New, non-destructive editor effects.
  final int rotationQuarterTurns; // Counterclockwise, relative to the source.
  final bool isMuted; // جديد: حالة الكتم لكل تقسيمة
  // Optional alternative source for this timeline segment; source boundaries
  // above stay in the original project's time coordinate system.
  final String? replacementPath;
  final Duration replacementStartTime;
  final Duration? replacementSourceDuration;

  CropClip({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.startFraction,
    required this.endFraction,
    this.speed = const CropSpeed.normal(),
    this.retouch = const CropRetouchSettings(),
    this.colorFilter = const CropFilterSelection(),
    this.cutout,
    this.backgroundPath,
    this.magicEffectId,
    this.animations = const CropAnimationSettings(),
    this.videoEffects = const [],
    this.rotationQuarterTurns = 0,
    this.isMuted = false, // الافتراضي مو مكتم
    this.replacementPath,
    this.replacementStartTime = Duration.zero,
    this.replacementSourceDuration,
  });

  CropClip copyWith({
    String? id,
    Duration? startTime,
    Duration? endTime,
    double? startFraction,
    double? endFraction,
    CropSpeed? speed,
    CropRetouchSettings? retouch,
    CropFilterSelection? colorFilter,
    CutoutSettings? cutout,
    String? backgroundPath,
    String? magicEffectId,
    CropAnimationSettings? animations,
    List<TiniAppliedEffect>? videoEffects,
    int? rotationQuarterTurns,
    bool? isMuted,
    String? replacementPath,
    Duration? replacementStartTime,
    Duration? replacementSourceDuration,
  }) {
    return CropClip(
      id: id ?? this.id,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      startFraction: startFraction ?? this.startFraction,
      endFraction: endFraction ?? this.endFraction,
      speed: speed ?? this.speed,
      retouch: retouch ?? this.retouch,
      colorFilter: colorFilter ?? this.colorFilter,
      cutout: cutout ?? this.cutout,
      backgroundPath: backgroundPath ?? this.backgroundPath,
      magicEffectId: magicEffectId ?? this.magicEffectId,
      animations: animations ?? this.animations,
      videoEffects: videoEffects ?? this.videoEffects,
      rotationQuarterTurns: (rotationQuarterTurns ?? this.rotationQuarterTurns) % 4,
      isMuted: isMuted ?? this.isMuted,
      replacementPath: replacementPath ?? this.replacementPath,
      replacementStartTime: replacementStartTime ?? this.replacementStartTime,
      replacementSourceDuration: replacementSourceDuration ?? this.replacementSourceDuration,
    );
  }

  /// Explicit nullable setters preserve undo and enable removing backgrounds.
  CropClip withBackground(String? value) => _withLayer(background: value);
  CropClip withCutout(CutoutSettings? value) => _withLayer(cutoutSettings: value);

  CropClip _withLayer({String? background, CutoutSettings? cutoutSettings}) => CropClip(
    id: id, startTime: startTime, endTime: endTime,
    startFraction: startFraction, endFraction: endFraction, speed: speed,
    retouch: retouch, colorFilter: colorFilter, magicEffectId: magicEffectId, animations: animations,
    videoEffects: videoEffects, rotationQuarterTurns: rotationQuarterTurns, isMuted: isMuted,
    replacementPath: replacementPath, replacementStartTime: replacementStartTime,
    replacementSourceDuration: replacementSourceDuration,
    cutout: cutoutSettings ?? cutout, backgroundPath: background ?? backgroundPath,
  );

  CropClip clearBackground() => CropClip(
    id: id, startTime: startTime, endTime: endTime,
    startFraction: startFraction, endFraction: endFraction, speed: speed,
    retouch: retouch, colorFilter: colorFilter, magicEffectId: magicEffectId, animations: animations,
    videoEffects: videoEffects, rotationQuarterTurns: rotationQuarterTurns, isMuted: isMuted,
    replacementPath: replacementPath, replacementStartTime: replacementStartTime,
    replacementSourceDuration: replacementSourceDuration,
    cutout: cutout, backgroundPath: null,
  );

  CropClip clearCutout() => CropClip(
    id: id, startTime: startTime, endTime: endTime,
    startFraction: startFraction, endFraction: endFraction, speed: speed,
    retouch: retouch, colorFilter: colorFilter, magicEffectId: magicEffectId, animations: animations,
    videoEffects: videoEffects, rotationQuarterTurns: rotationQuarterTurns, isMuted: isMuted,
    replacementPath: replacementPath, replacementStartTime: replacementStartTime,
    replacementSourceDuration: replacementSourceDuration,
    cutout: null, backgroundPath: backgroundPath,
  );

  /// Nullable Magic needs a dedicated setter: copyWith(null) keeps old values.
  CropClip withMagic(String? effectId) => CropClip(
    id: id, startTime: startTime, endTime: endTime,
    startFraction: startFraction, endFraction: endFraction,
    speed: speed, retouch: retouch, colorFilter: colorFilter, magicEffectId: effectId, animations: animations,
    videoEffects: videoEffects, rotationQuarterTurns: rotationQuarterTurns, isMuted: isMuted,
    cutout: cutout, backgroundPath: backgroundPath,
    replacementPath: replacementPath,
    replacementStartTime: replacementStartTime,
    replacementSourceDuration: replacementSourceDuration,
  );

  CropClip withAnimations(CropAnimationSettings value) =>
      copyWith(animations: value);

  CropClip rotatedCounterclockwise() =>
      copyWith(rotationQuarterTurns: (rotationQuarterTurns + 1) % 4);

  CropClip withVideoEffects(List<TiniAppliedEffect> value) =>
      copyWith(videoEffects: List.unmodifiable(value));

  Duration get duration => endTime - startTime;

  /// Duration shown on the timeline and produced by FFmpeg.
  Duration get playbackDuration => Duration(microseconds:
      (duration.inMicroseconds * speed.playbackFraction(1)).round());

  double projectOffsetForSource(Duration position) {
    if (duration.inMicroseconds <= 0) return 0;
    final fraction = (position - startTime).inMicroseconds / duration.inMicroseconds;
    return duration.inMicroseconds / 1000000.0 * speed.playbackFraction(fraction);
  }

  Duration sourceAtProjectOffset(double seconds) {
    if (duration.inMicroseconds <= 0) return startTime;
    final amount = duration.inMicroseconds / 1000000.0;
    final normalized = speed.sourceFractionAtPlayback(seconds / amount);
    return startTime + Duration(microseconds: (normalized * duration.inMicroseconds).round());
  }


  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CropClip &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
