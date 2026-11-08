import 'dart:math' as math;

/// Non-destructive face retouch. Zero amounts are an exact identity operation.
class CropRetouchSettings {
  final double smooth, teeth;
  final bool automatic;
  const CropRetouchSettings({
    this.smooth = 0,
    this.teeth = 0,
    this.automatic = false,
  });
  static const auto = CropRetouchSettings(
    smooth: .55,
    teeth: .4,
    automatic: true,
  );
  bool get enabled => smooth > 0 || teeth > 0;
  CropRetouchSettings copyWith({
    double? smooth,
    double? teeth,
    bool? automatic,
  }) {
    double amount(double value) => value.isFinite ? value.clamp(0.0, 1.0) : 0;
    return CropRetouchSettings(
      smooth: amount(smooth ?? this.smooth),
      teeth: amount(teeth ?? this.teeth),
      automatic: automatic ?? this.automatic,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CropRetouchSettings &&
      smooth == other.smooth &&
      teeth == other.teeth &&
      automatic == other.automatic;
  @override
  int get hashCode => Object.hash(smooth, teeth, automatic);
}

class CropRetouchSegment {
  final String id;
  final int startMs, endMs;
  final CropRetouchSettings settings;
  const CropRetouchSegment({
    required this.id,
    required this.startMs,
    required this.endMs,
    required this.settings,
  });
  CropRetouchSegment withSettings(CropRetouchSettings value) =>
      CropRetouchSegment(
        id: id,
        startMs: startMs,
        endMs: endMs,
        settings: value,
      );
}

/// Serializable geometry from actual detector output, in decoded-frame pixels.
/// Teeth are processed only when the two inner-lip contours enclose an opening.
class CropRetouchFace {
  final double left, top, width, height;
  final List<math.Point<double>> outline, leftEye, rightEye, mouth;
  const CropRetouchFace({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.outline = const [],
    this.leftEye = const [],
    this.rightEye = const [],
    this.mouth = const [],
  });
  Map<String, Object> toMap() => {
    'left': left,
    'top': top,
    'width': width,
    'height': height,
    'outline': [
      for (final p in outline) [p.x, p.y],
    ],
    'leftEye': [
      for (final p in leftEye) [p.x, p.y],
    ],
    'rightEye': [
      for (final p in rightEye) [p.x, p.y],
    ],
    'mouth': [
      for (final p in mouth) [p.x, p.y],
    ],
  };
  factory CropRetouchFace.fromMap(Map<dynamic, dynamic> map) {
    List<math.Point<double>> points(String key) => [
      for (final p in (map[key] as List? ?? []))
        math.Point((p[0] as num).toDouble(), (p[1] as num).toDouble()),
    ];
    return CropRetouchFace(
      left: (map['left'] as num).toDouble(),
      top: (map['top'] as num).toDouble(),
      width: (map['width'] as num).toDouble(),
      height: (map['height'] as num).toDouble(),
      outline: points('outline'),
      leftEye: points('leftEye'),
      rightEye: points('rightEye'),
      mouth: points('mouth'),
    );
  }
}
