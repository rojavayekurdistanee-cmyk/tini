import 'dart:math' as math;

/// Project-time layer, independent of source cuts, speed and colour filters.
/// Geometry is normalized to the actual video rectangle, not the screen.
class CropOverlay {
  final String id, path;
  final bool isVideo;
  final double aspectRatio, centerX, centerY, width;
  final int startMs, endMs, sourceStartMs, sourceDurationMs;
  const CropOverlay({
    required this.id,
    required this.path,
    required this.isVideo,
    required this.aspectRatio,
    required this.startMs,
    required this.endMs,
    this.centerX = .5,
    this.centerY = .5,
    this.width = .45,
    this.sourceStartMs = 0,
    this.sourceDurationMs = 0,
  });

  bool visible(int positionMs) => positionMs >= startMs && positionMs < endMs;
  double height(double canvasAspect) => width * canvasAspect / aspectRatio;
  int sourcePosition(int projectMs) => (sourceStartMs + projectMs - startMs)
      .clamp(0, math.max(0, sourceDurationMs - 1));
  CropOverlay copyWith({
    String? id,
    String? path,
    bool? isVideo,
    double? aspectRatio,
    double? centerX,
    double? centerY,
    double? width,
    int? startMs,
    int? endMs,
    int? sourceStartMs,
    int? sourceDurationMs,
  }) => CropOverlay(
    id: id ?? this.id,
    path: path ?? this.path,
    isVideo: isVideo ?? this.isVideo,
    aspectRatio: aspectRatio ?? this.aspectRatio,
    centerX: (centerX ?? this.centerX).clamp(-4.0, 5.0),
    centerY: (centerY ?? this.centerY).clamp(-4.0, 5.0),
    width: (width ?? this.width).clamp(.02, 8.0),
    startMs: startMs ?? this.startMs,
    endMs: endMs ?? this.endMs,
    sourceStartMs: sourceStartMs ?? this.sourceStartMs,
    sourceDurationMs: sourceDurationMs ?? this.sourceDurationMs,
  );

  CropOverlay? fit(int durationMs) {
    if (durationMs <= 0 ||
        startMs >= durationMs ||
        endMs <= 0 ||
        endMs <= startMs ||
        !aspectRatio.isFinite ||
        aspectRatio <= 0 ||
        !width.isFinite ||
        !centerX.isFinite ||
        !centerY.isFinite ||
        path.isEmpty) {
      return null;
    }
    return copyWith(
      startMs: startMs.clamp(0, durationMs),
      endMs: endMs.clamp(0, durationMs),
      sourceStartMs: math.max(0, sourceStartMs),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CropOverlay &&
      id == other.id &&
      path == other.path &&
      isVideo == other.isVideo &&
      aspectRatio == other.aspectRatio &&
      centerX == other.centerX &&
      centerY == other.centerY &&
      width == other.width &&
      startMs == other.startMs &&
      endMs == other.endMs &&
      sourceStartMs == other.sourceStartMs &&
      sourceDurationMs == other.sourceDurationMs;
  @override
  int get hashCode => Object.hash(
    id,
    path,
    isVideo,
    aspectRatio,
    centerX,
    centerY,
    width,
    startMs,
    endMs,
    sourceStartMs,
    sourceDurationMs,
  );

  List<CropOverlay> split(int positionMs, String newId) {
    if (positionMs <= startMs || positionMs >= endMs) return [this];
    return [
      copyWith(endMs: positionMs),
      copyWith(
        id: newId,
        startMs: positionMs,
        sourceStartMs: sourceStartMs + positionMs - startMs,
      ),
    ];
  }
}

/// Immutable snapshots make gestures one undo step and preserve cancellation.
class CropOverlayHistory {
  List<CropOverlay> _value;
  final _undo = <List<CropOverlay>>[], _redo = <List<CropOverlay>>[];
  CropOverlayHistory(List<CropOverlay> initial)
    : _value = List.unmodifiable(initial);
  List<CropOverlay> get value => _value;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  void commit(List<CropOverlay> next) {
    if (sameCropOverlays(_value, next)) return;
    _undo.add(_value);
    _redo.clear();
    _value = List.unmodifiable(next);
  }

  void undo() {
    if (canUndo) {
      _redo.add(_value);
      _value = _undo.removeLast();
    }
  }

  void redo() {
    if (canRedo) {
      _undo.add(_value);
      _value = _redo.removeLast();
    }
  }
}

bool sameCropOverlays(List<CropOverlay> a, List<CropOverlay> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Keep portrait/landscape proportions when the existing render engine caps
/// dimensions at 1920. H.264 requires even output dimensions.
class CropOverlayOutputSize {
  final int width, height;
  const CropOverlayOutputSize(this.width, this.height);
  factory CropOverlayOutputSize.fromSource(double width, double height) {
    if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
      return const CropOverlayOutputSize(720, 1280);
    }
    final scale = math.min(1.0, 1920 / math.max(width, height));
    return CropOverlayOutputSize(
      (width * scale).round().clamp(2, 1920) ~/ 2 * 2,
      (height * scale).round().clamp(2, 1920) ~/ 2 * 2,
    );
  }
}
