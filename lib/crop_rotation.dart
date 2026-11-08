import 'package:flutter/material.dart';
import 'crop_model.dart';

/// The same fixed canvas and counterclockwise quarter turns in preview/export.
/// Independent overlay tracks are composed after this base-picture transform.
abstract final class CropRotation {
  static CropClip? clipAt(List<CropClip> clips, Duration position) {
    for (final clip in clips) {
      if (position >= clip.startTime && position < clip.endTime) return clip;
    }
    // A paused player can report the exact end while still showing its last frame.
    if (clips.isNotEmpty && position == clips.last.endTime) return clips.last;
    return null;
  }

  static Widget preview(Widget picture, int quarterTurns) {
    final turns = quarterTurns % 4;
    if (turns == 0) return picture;
    return LayoutBuilder(
      builder: (context, constraints) => ClipRect(
        child: ColoredBox(
          color: Colors.black,
          child: SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.contain,
              child: RotatedBox(
                quarterTurns: -turns,
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: picture,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String ffmpeg(int quarterTurns, int width, int height) {
    final rotation = switch (quarterTurns % 4) {
      1 => 'transpose=cclock',
      2 => 'hflip,vflip',
      3 => 'transpose=clock',
      _ => 'null',
    };
    return '$rotation,scale=$width:$height:force_original_aspect_ratio=decrease,'
        'pad=$width:$height:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1';
  }
}
