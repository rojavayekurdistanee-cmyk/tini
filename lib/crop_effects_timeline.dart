import 'package:flutter/material.dart';
import 'crop_effects_model.dart';

/// Semi-transparent ranges inside the existing track, aligned to edited time.
/// IgnorePointer deliberately preserves timeline trimming/scrubbing gestures.
class TiniEffectsTimelineOverlay extends StatelessWidget {
  final List<TiniAppliedEffect> effects;
  final double clipSeconds;
  final double pixelsPerSecond;

  const TiniEffectsTimelineOverlay({super.key, required this.effects,
      required this.clipSeconds, required this.pixelsPerSecond});

  @override
  Widget build(BuildContext context) {
    if (effects.isEmpty || clipSeconds <= 0) return const SizedBox.shrink();
    return IgnorePointer(child: Stack(children: [
      for (final effect in effects)
        if (effect.endSeconds > effect.startSeconds && effect.descriptor != null)
          Positioned(
            left: (clipSeconds - effect.endSeconds.clamp(0.0, clipSeconds)) * pixelsPerSecond,
            width: (effect.endSeconds.clamp(0.0, clipSeconds) -
                effect.startSeconds.clamp(0.0, clipSeconds)) * pixelsPerSecond,
            top: 0, bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                color: effect.descriptor!.color.withValues(alpha: .31),
                border: Border.symmetric(vertical: BorderSide(
                    color: effect.descriptor!.color.withValues(alpha: .95), width: 2)),
              ),
              alignment: Alignment.bottomCenter,
              child: Text(effect.descriptor!.name, maxLines: 1,
                overflow: TextOverflow.clip, softWrap: false,
                style: const TextStyle(color: Colors.white, fontSize: 9)),
            ),
          ),
    ]));
  }
}
