import 'package:flutter/material.dart';

/// Coordinates are normalized to the *actual* video image, not the screen.
@immutable
class CutoutStroke {
  final bool erase;
  final bool quick;
  final double radius;
  final List<Offset> points;

  const CutoutStroke({
    required this.erase,
    required this.quick,
    required this.radius,
    required this.points,
  });

  Map<String, Object> toNative() => {
    'erase': erase,
    'radius': radius,
    'points': points.map((p) => [p.dx, p.dy]).toList(),
  };
}

/// One confirmed chroma pass. Every pass adds transparency; none restores it.
@immutable
class ChromaKeyPass {
  final int color;
  final double similarity;
  final double blend;

  const ChromaKeyPass({required this.color, required this.similarity,
    required this.blend});
}

/// TikTok-style effects follow the subject's alpha mask, never the video frame.
enum CutoutEdgeStyle { none, cyan, glow, doubleLine, paper, pink, dashed, sparkle }

/// File-backed cutout masks are cached locally; they are never server uploads.
@immutable
class CutoutSettings {
  final String maskDirectory;
  final Duration sourceStart;
  final double framesPerSecond;
  final int frameCount;
  final List<CutoutStroke> strokes;
  final bool manualMask;
  // Optional chroma-key settings; a chroma cutout does not require ML masks.
  final bool chromaEnabled;
  final int chromaColor;
  final double chromaSimilarity;
  final double chromaBlend;
  // Confirmed chroma passes, independent of the editable current pass.
  final List<ChromaKeyPass> chromaPasses;
  final bool chromaDraftEnabled;
  final double edgeFeather;
  // Decorative outlines are independent of chroma-key and brush undo history.
  final CutoutEdgeStyle edgeStyle;
  final int edgeColor;
  final double edgeSize;
  final double edgeDistance;
  final double edgeOpacity;
  bool get hasMask => maskDirectory.isNotEmpty && frameCount > 0 && framesPerSecond > 0;

  const CutoutSettings({
    required this.maskDirectory,
    required this.sourceStart,
    required this.framesPerSecond,
    required this.frameCount,
    this.strokes = const [],
    this.manualMask = false,
    this.chromaEnabled = false,
    this.chromaColor = 0x00FF00,
    this.chromaSimilarity = .20,
    this.chromaBlend = .08,
    this.chromaPasses = const [],
    this.chromaDraftEnabled = true,
    this.edgeFeather = .75,
    this.edgeStyle = CutoutEdgeStyle.none,
    this.edgeColor = 0x36E6EE,
    this.edgeSize = .45,
    this.edgeDistance = .12,
    this.edgeOpacity = .95,
  });

  CutoutSettings withStrokes(List<CutoutStroke> value) => CutoutSettings(
    maskDirectory: maskDirectory,
    sourceStart: sourceStart,
    framesPerSecond: framesPerSecond,
    frameCount: frameCount,
    strokes: List.unmodifiable(value),
    manualMask: manualMask,
    chromaEnabled: chromaEnabled,
    chromaColor: chromaColor,
    chromaSimilarity: chromaSimilarity,
    chromaBlend: chromaBlend,
    chromaPasses: chromaPasses,
    chromaDraftEnabled: chromaDraftEnabled,
    edgeFeather: edgeFeather,
    edgeStyle: edgeStyle,
    edgeColor: edgeColor,
    edgeSize: edgeSize,
    edgeDistance: edgeDistance,
    edgeOpacity: edgeOpacity,
  );
}

// Immutable options preserve the undo/redo data held by CropClip.
extension CutoutOptions on CutoutSettings {
  CutoutSettings withOptions({bool? chromaEnabled, int? chromaColor,
      double? chromaSimilarity, double? chromaBlend, double? edgeFeather,
      List<ChromaKeyPass>? chromaPasses, bool? chromaDraftEnabled,
      CutoutEdgeStyle? edgeStyle, int? edgeColor, double? edgeSize,
      double? edgeDistance, double? edgeOpacity}) =>
      CutoutSettings(maskDirectory: maskDirectory, sourceStart: sourceStart,
        framesPerSecond: framesPerSecond, frameCount: frameCount, strokes: strokes,
        manualMask: manualMask,
        chromaEnabled: chromaEnabled ?? this.chromaEnabled,
        chromaColor: chromaColor ?? this.chromaColor,
        chromaSimilarity: chromaSimilarity ?? this.chromaSimilarity,
        chromaBlend: chromaBlend ?? this.chromaBlend,
        chromaPasses: chromaPasses == null ? this.chromaPasses
            : List<ChromaKeyPass>.unmodifiable(chromaPasses),
        chromaDraftEnabled: chromaDraftEnabled ?? this.chromaDraftEnabled,
        edgeFeather: edgeFeather ?? this.edgeFeather,
        edgeStyle: edgeStyle ?? this.edgeStyle,
        edgeColor: edgeColor ?? this.edgeColor,
        edgeSize: edgeSize ?? this.edgeSize,
        edgeDistance: edgeDistance ?? this.edgeDistance,
        edgeOpacity: edgeOpacity ?? this.edgeOpacity);
}
