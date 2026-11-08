import 'crop_model.dart';
import 'crop_effects_model.dart';

class CropCutActions {
  static const double gapFraction = 0.005; // ثابت قديم للتوافق، لا يُستخدم لحذف زمن من الفيديو

  static List<CropClip> splitAt({
    required List<CropClip> clips,
    required double fraction,
    required int selectedIndex,
    required Duration videoDuration,
  }) {
    if (clips.isEmpty) return clips;

    final int safeIndex = selectedIndex.clamp(0, clips.length - 1);
    final clip = clips[safeIndex];

    // موضع التقسيم مرتبط بوقت المصدر الأصلي، وليس بمكان المقطع داخل التايم لاين.
    final durationMs = videoDuration.inMilliseconds;
    if (durationMs <= 0) return clips;
    final splitMs = (fraction.clamp(0.0, 1.0) * durationMs).round();
    // نسمح بالتقسيم إذا بقي 0.1 ثانية على الأقل في كل جزء.
    if (splitMs - clip.startTime.inMilliseconds < 100 ||
        clip.endTime.inMilliseconds - splitMs < 100) return clips;

    final splitFraction = (splitMs - clip.startTime.inMilliseconds) /
        clip.duration.inMilliseconds;
    // Clip effect windows belong to playback time, so account for speed curves.
    final splitSeconds = clip.duration.inMicroseconds / 1000000.0 *
        clip.speed.playbackFraction(splitFraction);
    final fullSeconds = clip.playbackDuration.inMicroseconds / 1000000.0;
    final firstEffects = <TiniAppliedEffect>[
      for (final e in clip.videoEffects)
        if (e.startSeconds < splitSeconds && e.endSeconds > 0)
          e.copyWith(startSeconds: e.startSeconds.clamp(0, splitSeconds).toDouble(),
            endSeconds: e.endSeconds.clamp(0, splitSeconds).toDouble()),
    ];
    final secondEffects = <TiniAppliedEffect>[
      for (final e in clip.videoEffects)
        if (e.endSeconds > splitSeconds && e.startSeconds < fullSeconds)
          e.copyWith(startSeconds: (e.startSeconds - splitSeconds)
                .clamp(0, fullSeconds - splitSeconds).toDouble(),
              endSeconds: (e.endSeconds - splitSeconds)
                .clamp(0, fullSeconds - splitSeconds).toDouble()),
    ];
    final first = clip.copyWith(
      videoEffects: firstEffects,
      speed: clip.speed.slice(0, splitFraction),
      animations: clip.animations.firstHalf,
      endFraction: splitMs / durationMs,
      endTime: Duration(milliseconds: splitMs),
      isMuted: clip.isMuted,
    );

    final second = CropClip(
      id: '${clip.id}_split_${DateTime.now().microsecondsSinceEpoch}',
      startFraction: splitMs / durationMs,
      endFraction: clip.endFraction,
      startTime: Duration(milliseconds: splitMs),
      endTime: clip.endTime,
      isMuted: clip.isMuted,
      rotationQuarterTurns: clip.rotationQuarterTurns,
      speed: clip.speed.slice(splitFraction, 1),
      magicEffectId: clip.magicEffectId,
      colorFilter: clip.colorFilter,
      retouch: clip.retouch,
      animations: clip.animations.secondHalf,
      videoEffects: secondEffects,
      cutout: clip.cutout,
      backgroundPath: clip.backgroundPath,
      replacementPath: clip.replacementPath,
      replacementStartTime: clip.replacementStartTime +
          Duration(milliseconds: splitMs - clip.startTime.inMilliseconds),
      replacementSourceDuration: clip.replacementSourceDuration,
    );

    final List<CropClip> newList = List.from(clips);
    newList.removeAt(safeIndex);
    newList.insert(safeIndex, second);
    newList.insert(safeIndex, first);
    return newList;
  }

  static List<CropClip> deleteClip({
  required List<CropClip> clips,
  required int selectedIndex,
  required Duration videoDuration,
}) {
  if (clips.isEmpty) return clips;
  if (clips.length == 1) return [];

  final int safeIndex = selectedIndex.clamp(0, clips.length - 1);
  final List<CropClip> newList = List.from(clips);
  newList.removeAt(safeIndex);

  // لا نغيّر إحداثيات المصدر بعد الحذف: التايم لاين يعرض المقاطع المتبقية
  // متجاورة اعتماداً على مددها، وليس بإعادة كتابة startFraction/endFraction.
  return newList;
}
}
