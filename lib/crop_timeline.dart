import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'crop_model.dart';
import 'crop_animation_model.dart';
import 'crop_animation_timeline.dart';
import 'crop_effects_timeline.dart';
import 'croup_transition.dart';

/// The playhead is fixed in the middle. All tracks use the same RTL time axis.
/// Crop fractions always refer to the original file, not the edited timeline.
class CropTimeline extends StatefulWidget {
  final Duration videoDuration;
  final List<Uint8List> thumbnails;
  final List<CropClip> cropClips;
  final bool isTimelineEmpty;
  final Map<String, List<Uint8List>> replacementThumbnails;
  final RangeValues currentRange;
  final Function(double start, double end) onRangeChanged;
  final Function(String clipId, double start, double end)? onClipRangeChanged;
  final Function(String clipId) onClipSelected;
  final String? selectedClipId;
  final void Function(String clipId, CropAnimationTab tab, double seconds, bool finished)?
      onAnimationDurationChanged;
  final String audioName;
  final double currentPosition;
  final Function(double fraction) onScrub;
  final bool isFrameSelected;
  final Function(bool) onFrameSelectedChanged;
  // The added music is an independent track. No music means no fake audio strip.
  final bool hasMusic;
  final RangeValues audioRange;
  final ValueChanged<RangeValues>? onAudioRangeChanged;
  final ValueChanged<bool>? onAudioSelected;

  const CropTimeline({
    super.key,
    required this.videoDuration,
    required this.thumbnails,
    required this.cropClips,
    this.isTimelineEmpty = false,
    this.replacementThumbnails = const {},
    required this.currentRange,
    required this.onRangeChanged,
    this.onClipRangeChanged,
    required this.onClipSelected,
    this.selectedClipId,
    this.onAnimationDurationChanged,
    required this.audioName,
    this.currentPosition = 0.0,
    required this.onScrub,
    this.isFrameSelected = false,
    required this.onFrameSelectedChanged,
    this.hasMusic = false,
    this.audioRange = const RangeValues(0, 1),
    this.onAudioRangeChanged,
    this.onAudioSelected,
  });

  @override
  State<CropTimeline> createState() => _CropTimelineState();
}

class _CropTimelineState extends State<CropTimeline> with TickerProviderStateMixin {
  static const double _pixelsPerSecond = 50;
  static const double _minClipSeconds = 0.1;

  bool _scrubbing = false;
  bool _audioSelected = false;
  double _scrubSeconds = 0;
  double _fixedOppositeEdge = 0;
  bool _draggingRightEdge = false;
  // During handle dragging, keep the playhead separate from the source frame
  // used for trim previews. This prevents every seek from jumping the strip.
  double? _dragViewportSeconds;
  double _dragClipOffsetSeconds = 0;
  // Track the entire finger movement from touch-down. Using the changing
  // clip length as a new origin would trim the opposite side on reverse swipes.
  double _dragInitialHandleX = 0;
  double _dragTravelDx = 0;
  RangeValues _dragStartingRange = const RangeValues(0, 1);
  String? _dragVideoClipId;
  bool _dragIsAudio = false;
  bool _edgeDidMove = false;
  double _dragInitialSpanSeconds = 0;
  CropClip? _dragActiveClip;
  // Continue trimming only after a deliberate swipe and a brief stationary
  // hold. Manual finger movement and automatic trimming never run together.
  double _heldTrimDirection = 0;
  double _pendingDirectionTravel = 0;
  final Stopwatch _fingerIdleWatch = Stopwatch();
  late final Ticker _autoTrimTicker;
  Duration? _lastAutoTrimTick;
  static const double _directionThresholdPx = 6.0;
  static const int _holdDelayMs = 200;
  // Keep the active range locally: pointer updates can arrive before Flutter
  // rebuilds the parent with its newly committed crop/audio range.
  RangeValues? _dragHandleRange;
  double _trimmedEdgeProjectSeconds = 0;
  double _trimmedEdgeSourceFraction = 0;

  // After the finger is lifted, the trimmed edge eases back to the playhead.
  // The trim values themselves never change during this recenter animation.
  late final AnimationController _recenterController;
  double _recenterFrom = 0;
  double _recenterTo = 0;
  double? _recenterSeekFraction;

  @override
  void initState() {
    super.initState();
    _autoTrimTicker = createTicker(_onAutoTrimTick);
    _recenterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 190),
    )
      ..addListener(_advanceRecenter)
      ..addStatusListener(_onRecenterStatus);
  }

  @override
  void dispose() {
    _fingerIdleWatch.stop();
    _autoTrimTicker.dispose();
    _recenterController.dispose();
    super.dispose();
  }

  void _advanceRecenter() {
    if (!mounted) return;
    final progress = Curves.easeOutCubic.transform(_recenterController.value);
    setState(() {
      _dragViewportSeconds = _recenterFrom +
          (_recenterTo - _recenterFrom) * progress;
    });
  }

  void _onRecenterStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    final seekFraction = _recenterSeekFraction;
    if (seekFraction != null) widget.onScrub(seekFraction);
    setState(() {
      _dragViewportSeconds = null;
      _recenterSeekFraction = null;
    });
  }

  // Both time and positions are kept as doubles; Duration.inSeconds truncates.
  double get _sourceSeconds => math.max(0.001, widget.videoDuration.inMilliseconds / 1000);

  List<CropClip> get _visibleClips {
    // Render the dragged boundary immediately, even before a parent rebuild.
    // Do not change either source boundary on any other clip.
    final activeRange = _dragIsAudio ? null : _dragHandleRange;
    if (widget.cropClips.isNotEmpty) {
      if (activeRange == null || _dragVideoClipId == null) return widget.cropClips;
      return [
        for (final clip in widget.cropClips)
          if (clip.id == _dragVideoClipId)
            clip.copyWith(
              startFraction: activeRange.start,
              endFraction: activeRange.end,
              startTime: Duration(milliseconds:
                  (activeRange.start * widget.videoDuration.inMilliseconds).round()),
              endTime: Duration(milliseconds:
                  (activeRange.end * widget.videoDuration.inMilliseconds).round()),
            )
          else
            clip,
      ];
    }
    final range = activeRange ?? widget.currentRange;
    final start = range.start.clamp(0.0, 1.0);
    final end = range.end.clamp(start, 1.0);
    return [CropClip(
      id: '__preview_clip__',
      startTime: Duration(milliseconds: (start * widget.videoDuration.inMilliseconds).round()),
      endTime: Duration(milliseconds: (end * widget.videoDuration.inMilliseconds).round()),
      startFraction: start,
      endFraction: end,
    )];
  }

  double _durationOf(CropClip clip) => math.max(0.0, clip.playbackDuration.inMicroseconds / 1000000);
  double get _projectSeconds => _visibleClips.fold(0.0, (double value, clip) => value + _durationOf(clip));

  // Convert original-source time to the compact edited sequence time.
  double _projectFromSource(double sourceSeconds) {
    double elapsed = 0;
    for (final clip in _visibleClips) {
      final start = clip.startTime.inMilliseconds / 1000;
      final end = clip.endTime.inMilliseconds / 1000;
      if (sourceSeconds >= start && sourceSeconds <= end) {
        return elapsed + clip.projectOffsetForSource(
            Duration(microseconds: (sourceSeconds * 1000000).round()));
      }
      elapsed += _durationOf(clip);
      if (sourceSeconds < end) return elapsed;
    }
    return sourceSeconds <= _visibleClips.first.startTime.inMilliseconds / 1000
        ? 0 : _projectSeconds;
  }

  // Convert compact-project time back to the original video for the player.
  double _sourceFromProject(double projectSeconds) {
    double remaining = projectSeconds.clamp(0.0, _projectSeconds);
    for (final clip in _visibleClips) {
      final seconds = _durationOf(clip);
      if (remaining <= seconds) {
        return (clip.sourceAtProjectOffset(remaining).inMicroseconds / 1000000)
            .clamp(0.0, _sourceSeconds);
      }
      remaining -= seconds;
    }
    return _visibleClips.last.endTime.inMilliseconds / 1000;
  }

  double get _currentProjectSeconds {
    if (_scrubbing) return _scrubSeconds;
    if (_dragViewportSeconds != null) {
      // Temporary overscroll is intentional: a handle at the center must be
      // free to move past it with the finger before snapping back on release.
      return _dragViewportSeconds!;
    }
    return _projectFromSource(widget.currentPosition.clamp(0.0, 1.0) * _sourceSeconds);
  }

  void _scrubTo(double seconds) {
    _scrubSeconds = seconds.clamp(0.0, _projectSeconds);
    setState(() {});
    widget.onScrub((_sourceFromProject(_scrubSeconds) / _sourceSeconds).clamp(0.0, 1.0));
  }

  void _beginScrub(DragStartDetails details) {
    _stopAutoTrim();
    _fingerIdleWatch.stop();
    _scrubSeconds = _currentProjectSeconds.clamp(0.0, _projectSeconds);
    _recenterController.stop();
    _recenterSeekFraction = null;
    _dragViewportSeconds = null;
    _scrubbing = true;
    setState(() {});
  }

  void _moveScrub(DragUpdateDetails details) => _scrubTo(_scrubSeconds + details.delta.dx / _pixelsPerSecond);

  void _endScrub(DragEndDetails details) {
    setState(() => _scrubbing = false);
  }

  void _cancelScrub() {
    setState(() => _scrubbing = false);
  }

  // A short swipe sets the trim direction. The frame ticker keeps trimming
  // while the handle remains pressed, regardless of finger position or screen
  // edge. Reversing the swipe changes direction on the same handle immediately.
  void _stopAutoTrim() {
    if (_autoTrimTicker.isActive) _autoTrimTicker.stop();
    _lastAutoTrimTick = null;
  }

  void _syncAutoTrim() {
    final range = _dragHandleRange;
    if (range == null || !_edgeDidMove || _heldTrimDirection == 0) {
      _stopAutoTrim();
      return;
    }
    final timeBase = _dragIsAudio
        ? math.max(_projectSeconds, 0.001)
        : _sourceSeconds;
    final minFraction = math.min(_minClipSeconds / timeBase,
        _dragStartingRange.end - _dragStartingRange.start);
    final shortening = _draggingRightEdge
        ? _heldTrimDirection < 0
        : _heldTrimDirection > 0;
    final canContinue = shortening
        ? range.end - range.start > minFraction + 1e-7
        : (_draggingRightEdge
            ? range.start > 1e-7
            : range.end < 1.0 - 1e-7);
    if (!canContinue) {
      _stopAutoTrim();
    } else if (!_autoTrimTicker.isActive) {
      _lastAutoTrimTick = null;
      _autoTrimTicker.start();
    }
  }

  void _onAutoTrimTick(Duration elapsed) {
    if (!mounted || _dragHandleRange == null || _heldTrimDirection == 0) {
      _stopAutoTrim();
      return;
    }
    final previous = _lastAutoTrimTick;
    _lastAutoTrimTick = elapsed;
    if (previous == null) return;
    final seconds = ((elapsed - previous).inMicroseconds / 1e6)
        .clamp(0.0, 0.06);
    if (seconds <= 0) return;
    // Moderate continuous trim speed: predictable on long clips while
    // keeping short clips easy to control. Reversing the finger changes
    // direction on the same handle; holding does not depend on screen edges.
    final idleMs = _fingerIdleWatch.elapsedMilliseconds;
    if (!_fingerIdleWatch.isRunning || idleMs < _holdDelayMs) return;
    final rate = (_dragInitialSpanSeconds * 0.45).clamp(2.5, 6.0);
    final ramp = ((idleMs - _holdDelayMs) / 350.0).clamp(0.0, 1.0);
    final gentleRate = rate * (0.45 + 0.55 * ramp);
    final dx = _heldTrimDirection * gentleRate * seconds * _pixelsPerSecond;
    if (_dragIsAudio) {
      _changeAudioEdge(_draggingRightEdge, dx);
    } else if (_dragActiveClip != null) {
      _changeVideoEdge(_dragActiveClip!, _draggingRightEdge, dx);
    }
    _syncAutoTrim();
  }

  // A handle follows the finger freely until it reaches the safe screen
  // margin. After that, the timeline pans beneath it while the same source
  // boundary keeps changing. Reversing the swipe naturally reverses the pan.
  // Neither the playhead nor the opposite source boundary becomes the trim.
  double get _rightDragLimit => math.min(
      _dragInitialHandleX, math.min(80.0, _viewportCenterX * 0.48));
  double get _leftDragLimit => math.max(
      _dragInitialHandleX,
      _viewportCenterX * 2 - math.min(80.0, _viewportCenterX * 0.48));

  void _followTrimmedVideoEdge(double width) {
    if (_draggingRightEdge) {
      final naturalRight = _fixedOppositeEdge + width;
      final visibleRight = math.max(naturalRight, _rightDragLimit);
      _dragViewportSeconds = _dragClipOffsetSeconds +
          (visibleRight - _viewportCenterX) / _pixelsPerSecond;
    } else {
      final naturalLeft = _fixedOppositeEdge - width;
      final visibleLeft = math.min(naturalLeft, _leftDragLimit);
      _dragViewportSeconds = _dragClipOffsetSeconds +
          (visibleLeft + width - _viewportCenterX) / _pixelsPerSecond;
    }
  }

  // Only read on screen layout; never alter the user's chosen playhead location.
  double _viewportCenterX = 0;
  double _dragInitialViewportSeconds = 0;

  void _changeVideoEdge(CropClip clip, bool leadingRight, double dx) {
    _dragTravelDx += dx;
    // The visible width is playback time, not source time. Keep the
    // existing handle feel when a clip has been sped up or slowed down.
    final speedScale = math.max(.00001, clip.speed.playbackFraction(1));
    final deltaFraction = -_dragTravelDx /
        (_pixelsPerSecond * _sourceSeconds * speedScale);
    final initial = _dragStartingRange;
    final minFraction = math.min(
        _minClipSeconds / _sourceSeconds, initial.end - initial.start);
    final newStart = leadingRight
        ? (initial.start + deltaFraction).clamp(0.0, initial.end - minFraction)
        : initial.start;
    final newEnd = leadingRight
        ? initial.end
        : (initial.end + deltaFraction).clamp(initial.start + minFraction, 1.0);
    // At the hard limit do not accrue invisible overdrag: the user's first
    // reverse movement must immediately extend the same side again.
    if (leadingRight && newStart >= initial.end - minFraction - 1e-12) {
      _dragTravelDx = -(newStart - initial.start) *
          _pixelsPerSecond * _sourceSeconds * speedScale;
    } else if (!leadingRight &&
        newEnd <= initial.start + minFraction + 1e-12) {
      _dragTravelDx = (initial.end - newEnd) *
          _pixelsPerSecond * _sourceSeconds * speedScale;
    } else if (leadingRight && newStart <= 1e-12) {
      _dragTravelDx = -(newStart - initial.start) *
          _pixelsPerSecond * _sourceSeconds * speedScale;
    } else if (!leadingRight && newEnd >= 1.0 - 1e-12) {
      _dragTravelDx = (initial.end - newEnd) *
          _pixelsPerSecond * _sourceSeconds * speedScale;
    }
    final previous = _dragHandleRange ?? initial;
    if (newStart >= newEnd ||
        (newStart == previous.start && newEnd == previous.end)) return;
    _dragHandleRange = RangeValues(newStart, newEnd);
    _edgeDidMove = true;
    final editedClip = clip.copyWith(
      startTime: Duration(milliseconds: (newStart * widget.videoDuration.inMilliseconds).round()),
      endTime: Duration(milliseconds: (newEnd * widget.videoDuration.inMilliseconds).round()),
    );
    final nextWidth = _durationOf(editedClip) * _pixelsPerSecond;
    _followTrimmedVideoEdge(nextWidth);
    // Seek after release to the source frame at the edited boundary.
    _trimmedEdgeSourceFraction = leadingRight ? newStart : newEnd;
    _trimmedEdgeProjectSeconds = _dragClipOffsetSeconds +
        (leadingRight ? 0.0 : nextWidth / _pixelsPerSecond);
    if (widget.cropClips.isNotEmpty && widget.onClipRangeChanged != null) {
      widget.onClipRangeChanged!(clip.id, newStart, newEnd);
    } else {
      widget.onRangeChanged(newStart, newEnd);
    }
    setState(() {});
  }

  void _changeAudioEdge(bool leadingRight, double dx) {
    _dragTravelDx += dx;
    final duration = math.max(_projectSeconds, 0.001);
    final delta = -_dragTravelDx / (_pixelsPerSecond * duration);
    final initial = _dragStartingRange;
    final minFraction = math.min(
        _minClipSeconds / duration, initial.end - initial.start);
    final next = leadingRight
        ? RangeValues(
            (initial.start + delta).clamp(0.0, initial.end - minFraction),
            initial.end)
        : RangeValues(initial.start,
            (initial.end + delta).clamp(initial.start + minFraction, 1.0));
    if (leadingRight && next.start >= initial.end - minFraction - 1e-12) {
      _dragTravelDx = -(next.start - initial.start) *
          _pixelsPerSecond * duration;
    } else if (!leadingRight &&
        next.end <= initial.start + minFraction + 1e-12) {
      _dragTravelDx = (initial.end - next.end) *
          _pixelsPerSecond * duration;
    } else if (leadingRight && next.start <= 1e-12) {
      _dragTravelDx = -(next.start - initial.start) *
          _pixelsPerSecond * duration;
    } else if (!leadingRight && next.end >= 1.0 - 1e-12) {
      _dragTravelDx = (initial.end - next.end) *
          _pixelsPerSecond * duration;
    }
    final previous = _dragHandleRange ?? initial;
    if (next.start == previous.start && next.end == previous.end) return;
    _dragHandleRange = next;
    _edgeDidMove = true;
    widget.onAudioRangeChanged?.call(next);
    final edgeTime = (leadingRight ? next.start : next.end) * duration;
    // At the initial viewport the other audio edge is stationary. Once the
    // moving handle reaches the margin, pan both tracks by the same amount.
    final naturalX = _viewportCenterX +
        (_dragInitialViewportSeconds - edgeTime) * _pixelsPerSecond;
    final visibleX = leadingRight
        ? math.max(naturalX, _rightDragLimit)
        : math.min(naturalX, _leftDragLimit);
    _dragViewportSeconds = _dragInitialViewportSeconds +
        (visibleX - naturalX) / _pixelsPerSecond;
    _trimmedEdgeProjectSeconds = edgeTime;
    _trimmedEdgeSourceFraction =
        (_sourceFromProject(edgeTime) / _sourceSeconds).clamp(0.0, 1.0);
    setState(() {});
  }

  void _finishEdgeDrag() {
    _stopAutoTrim();
    _fingerIdleWatch.stop();
    _pendingDirectionTravel = 0;
    _heldTrimDirection = 0;
    _dragActiveClip = null;
    _dragHandleRange = null;
    if (!_edgeDidMove || _dragViewportSeconds == null) {
      setState(() => _dragViewportSeconds = null);
      return;
    }
    // The source range is already committed by the trim callback. Only
    // animate the viewport until the *same* edited edge meets the playhead.
    _recenterFrom = _dragViewportSeconds!;
    _recenterTo = _trimmedEdgeProjectSeconds.clamp(0.0, _projectSeconds);
    _recenterSeekFraction = _trimmedEdgeSourceFraction.clamp(0.0, 1.0);
    if ((_recenterFrom - _recenterTo).abs() < 0.002) {
      final fraction = _recenterSeekFraction!;
      widget.onScrub(fraction);
      setState(() {
        _dragViewportSeconds = null;
        _recenterSeekFraction = null;
      });
    } else {
      _recenterController.forward(from: 0);
    }
  }

  Widget _handle({
    required double x,
    required double y,
    required double height,
    required bool right,
    required String handleId,
    required double oppositeEdge,
    required double clipOffsetSeconds,
    required RangeValues initialRange,
    String? clipId,
    CropClip? clip,
    bool isAudio = false,
    bool separateHitRegion = false,
    required void Function(double) onDrag,
  }) {
    return Positioned(
      key: ValueKey(handleId),
      // Near the minimum length, give each handle a distinct hit area.
      left: separateHitRegion ? (right ? x : x - 34) : x - 17,
      top: y,
      width: 34,
      height: height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) {
          _stopAutoTrim();
          _recenterController.stop();
          _recenterSeekFraction = null;
          _draggingRightEdge = right;
          _fixedOppositeEdge = oppositeEdge;
          _dragClipOffsetSeconds = clipOffsetSeconds;
          _dragInitialViewportSeconds = _currentProjectSeconds;
          _dragViewportSeconds = _dragInitialViewportSeconds;
          _dragInitialHandleX = x;
          _dragTravelDx = 0;
          _dragStartingRange = initialRange;
          _dragVideoClipId = clipId;
          _dragIsAudio = isAudio;
          _heldTrimDirection = 0;
          _pendingDirectionTravel = 0;
          _fingerIdleWatch..reset()..stop();
          _dragActiveClip = clip;
          _dragInitialSpanSeconds = (initialRange.end - initialRange.start) *
              (isAudio ? math.max(_projectSeconds, 0.001) : _sourceSeconds);
          _edgeDidMove = false;
          _dragHandleRange = initialRange;
          setState(() {});
        },
        onHorizontalDragUpdate: (details) {
          final dx = details.delta.dx;
          // Finger movement directly controls the boundary (1:1). While the
          // finger is moving, reset the stationary-hold delay so no automatic
          // movement is added on top. Small involuntary tremors must not flip
          // the held direction.
          if (dx.abs() > 0.25) {
            _fingerIdleWatch..reset()..start();
            final direction = dx.isNegative ? -1.0 : 1.0;
            if (_heldTrimDirection == 0) {
              _pendingDirectionTravel += dx;
              if (_pendingDirectionTravel.abs() >= _directionThresholdPx) {
                _heldTrimDirection = _pendingDirectionTravel.sign;
                _pendingDirectionTravel = 0;
              }
            } else if (direction == _heldTrimDirection) {
              _pendingDirectionTravel = 0;
            } else {
              _pendingDirectionTravel += dx;
              if (_pendingDirectionTravel.abs() >= _directionThresholdPx) {
                _heldTrimDirection = direction;
                _pendingDirectionTravel = 0;
              }
            }
          }
          onDrag(dx);
          _syncAutoTrim();
        },
        onHorizontalDragEnd: (_) => _finishEdgeDrag(),
        onHorizontalDragCancel: _finishEdgeDrag,
        child: Align(
          alignment: separateHitRegion
              ? (right ? Alignment.centerLeft : Alignment.centerRight)
              : (right ? Alignment.centerRight : Alignment.centerLeft),
          child: Container(
            width: 18,
            height: height,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.horizontal(
                left: Radius.circular(right ? 3 : 8),
                right: Radius.circular(right ? 8 : 3),
              ),
            ),
            child: Icon(
              right ? Icons.chevron_right : Icons.chevron_left,
              size: 18,
              color: const Color(0xFF343434),
            ),
          ),
        ),
      ),
    );
  }

  Widget _videoFrames(CropClip clip, double width, double screenLeft, double viewportWidth) {
    final replacementFrames = clip.replacementPath == null
        ? null : widget.replacementThumbnails[clip.replacementPath!];
    final frames = replacementFrames == null || replacementFrames.isEmpty
        ? widget.thumbnails : replacementFrames;
    if (frames.isEmpty) return Container(color: const Color(0xFF1A222C));
    const tileWidth = 38.0;
    final count = math.max(1, (width / tileWidth).ceil());
    final visibleFirst = math.max(0, (-screenLeft / tileWidth).floor() - 1);
    final visibleLast = math.min(count - 1, ((viewportWidth - screenLeft) / tileWidth).ceil() + 1);
    final safeDuration = math.max(1,
        replacementFrames == null || replacementFrames.isEmpty
            ? widget.videoDuration.inMilliseconds
            : (clip.replacementSourceDuration?.inMilliseconds ?? clip.duration.inMilliseconds));
    return Stack(children: [
      for (int index = visibleFirst; index <= visibleLast; index++)
        Positioned(
          left: index * tileWidth,
          width: math.min(tileWidth, width - index * tileWidth),
          top: 0,
          bottom: 0,
          child: Image.memory(
            frames[(((replacementFrames == null || replacementFrames.isEmpty
                    ? clip.startTime.inMilliseconds
                    : clip.replacementStartTime.inMilliseconds) +
                (clip.sourceAtProjectOffset(
                    _durationOf(clip) * ((index + 0.5) / count)) - clip.startTime)
                    .inMilliseconds) /
                safeDuration * frames.length).floor().clamp(0, frames.length - 1)],
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isTimelineEmpty) {
      return const ColoredBox(
        color: Color(0xFF0E161B),
        child: Center(child: Text('لا توجد مقاطع',
            style: TextStyle(color: Colors.white70))),
      );
    }
    return LayoutBuilder(builder: (context, constraints) {
      final viewportWidth = constraints.maxWidth;
      final centerX = viewportWidth / 2;
      _viewportCenterX = centerX;
      // Compact layouts keep both tracks visible on shorter devices.
      final compact = constraints.maxHeight < 145;
      final videoTop = compact ? 19.0 : 24.0;
      final videoHeight = compact ? 46.0 : 64.0;
      final audioTop = compact ? 71.0 : 96.0;
      final audioHeight = compact ? 32.0 : 40.0;
      final current = _currentProjectSeconds;
      double timeOffset = 0;
      final items = <Widget>[];
      final borderItems = <Widget>[];
      final handleItems = <Widget>[];
      final clips = _visibleClips;

      for (int i = 0; i < clips.length; i++) {
        final clip = clips[i];
        final width = math.max(0.0, _durationOf(clip) * _pixelsPerSecond);
        // RTL: time 0 is on the right, later frames on the left.
        final rightX = centerX + (current - timeOffset) * _pixelsPerSecond;
        final leftX = rightX - width;
        // The viewport tracks the handle only when appropriate; coordinates
        // remain consistent for the clip, ruler, waveform and white playhead.
        final visibleLeft = leftX;
        final visibleRight = rightX;
        final selected = !_audioSelected && widget.isFrameSelected &&
            (widget.selectedClipId == null || widget.selectedClipId == clip.id);
        if (width > 0) {
          items.add(Positioned(
            left: visibleLeft,
            top: videoTop,
            width: width,
            height: videoHeight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // The video strip is above the background scrub detector in the
              // Stack. Give it the same drag handlers so a swipe on thumbnails
              // actually moves the timeline underneath the fixed playhead.
              onHorizontalDragStart: _beginScrub,
              onHorizontalDragUpdate: _moveScrub,
              onHorizontalDragEnd: _endScrub,
              onHorizontalDragCancel: _cancelScrub,
              onTap: () {
                setState(() => _audioSelected = false);
                widget.onAudioSelected?.call(false);
                if (widget.cropClips.isNotEmpty) widget.onClipSelected(clip.id);
                widget.onFrameSelectedChanged(true);
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Stack(fit: StackFit.expand, children: [
                  _videoFrames(clip, width, visibleLeft, viewportWidth),
                  if (clip.videoEffects.isNotEmpty)
                    TiniEffectsTimelineOverlay(
                      effects: clip.videoEffects,
                      clipSeconds: _durationOf(clip),
                      pixelsPerSecond: _pixelsPerSecond,
                    ),
                  if (clip.animations.hasEffects)
                    CropAnimationTimelineOverlay(
                      settings: clip.animations,
                      clipSeconds: _durationOf(clip),
                      pixelsPerSecond: _pixelsPerSecond,
                      editable: widget.onAnimationDurationChanged != null &&
                          (widget.selectedClipId == null || widget.selectedClipId == clip.id),
                      onResize: (tab, value, finished) =>
                          widget.onAnimationDurationChanged?.call(clip.id, tab, value, finished),
                    ),
                ]),
              ),
            ),
          ));
        }
        if (selected && width > 0) {
          borderItems.add(Positioned(
            left: visibleLeft,
            top: videoTop,
            width: width,
            height: videoHeight,
            child: IgnorePointer(
              child: DecoratedBox(decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(5),
              )),
            ),
          ));
          if (width > 46) {
            borderItems.add(Positioned(
              left: visibleLeft + 20,
              top: videoTop + 5,
              child: IgnorePointer(child: Text(
                '${_durationOf(clip).toStringAsFixed(1)}s',
                style: const TextStyle(color: Colors.white, fontSize: 11, shadows: [Shadow(color: Colors.black, blurRadius: 3)]),
              )),
            ));
          }
          handleItems.add(_handle(
            x: visibleRight, y: videoTop, height: videoHeight, right: true,
            handleId: 'video-${clip.id}-right', oppositeEdge: visibleLeft,
            clipOffsetSeconds: timeOffset, clipId: clip.id, clip: clip,
            separateHitRegion: width < 35,
            initialRange: RangeValues(clip.startFraction, clip.endFraction),
            onDrag: (dx) => _changeVideoEdge(clip, true, dx),
          ));
          handleItems.add(_handle(
            x: visibleLeft, y: videoTop, height: videoHeight, right: false,
            handleId: 'video-${clip.id}-left', oppositeEdge: visibleRight,
            clipOffsetSeconds: timeOffset, clipId: clip.id, clip: clip,
            separateHitRegion: width < 35,
            initialRange: RangeValues(clip.startFraction, clip.endFraction),
            onDrag: (dx) => _changeVideoEdge(clip, false, dx),
          ));
        }
        if (i < clips.length - 1 && width > 20) {
          // Retain the existing transition marker and its original action.
          items.add(Positioned(
            left: leftX - 10,
            top: videoTop + 20,
            child: CroupTransitionWidget(onTap: () {
              debugPrint('فتح انتقال بين ${clips[i].id} و ${clips[i + 1].id}');
            }),
          ));
        }
        timeOffset += _durationOf(clip);
      }

      if (widget.hasMusic && _projectSeconds > 0) {
        final range = _dragIsAudio ? (_dragHandleRange ?? widget.audioRange)
            : widget.audioRange;
        final audioStart = range.start * _projectSeconds;
        final audioEnd = range.end * _projectSeconds;
        final audioRight = centerX + (current - audioStart) * _pixelsPerSecond;
        final audioLeft = centerX + (current - audioEnd) * _pixelsPerSecond;
        final width = math.max(0.0, audioRight - audioLeft);
        final shownAudioLeft = audioLeft;
        final shownAudioRight = audioRight;
        if (width > 0) {
          items.add(Positioned(
            left: shownAudioLeft, top: audioTop, width: width, height: audioHeight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // The audio track must scroll on the exact same timeline scale.
              onHorizontalDragStart: _beginScrub,
              onHorizontalDragUpdate: _moveScrub,
              onHorizontalDragEnd: _endScrub,
              onHorizontalDragCancel: _cancelScrub,
              onTap: () {
                setState(() => _audioSelected = true);
                widget.onAudioSelected?.call(true);
                widget.onFrameSelectedChanged(false);
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(children: [
                  const Positioned.fill(child: ColoredBox(color: Color(0xFF858BEE))),
                  Positioned.fill(child: CustomPaint(painter: _AudioTrackPainter(
                    visibleStart: math.max(0.0, -shownAudioLeft),
                    visibleEnd: math.min(width, viewportWidth - shownAudioLeft),
                  ))),
                  Positioned.fill(child: Row(children: [
                    const SizedBox(width: 8),
                    const Icon(Icons.music_note, color: Color(0xFF283584), size: 16),
                    const SizedBox(width: 5),
                    Expanded(child: Text(widget.audioName,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF273574), fontSize: 12, fontWeight: FontWeight.w500))),
                  ])),
                ]),
              ),
            ),
          ));
          if (_audioSelected) {
            borderItems.add(Positioned(
              left: shownAudioLeft, top: audioTop, width: width, height: audioHeight,
              child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(6),
              ))),
            ));
            handleItems.add(_handle(x: shownAudioRight, y: audioTop, height: audioHeight,
              right: true, handleId: 'audio-right', oppositeEdge: shownAudioLeft,
              clipOffsetSeconds: 0, isAudio: true,
              separateHitRegion: width < 35,
              initialRange: widget.audioRange,
              onDrag: (dx) => _changeAudioEdge(true, dx)));
            handleItems.add(_handle(x: shownAudioLeft, y: audioTop, height: audioHeight,
              right: false, handleId: 'audio-left', oppositeEdge: shownAudioRight,
              clipOffsetSeconds: 0, isAudio: true,
              separateHitRegion: width < 35,
              initialRange: widget.audioRange,
              onDrag: (dx) => _changeAudioEdge(false, dx)));
          }
        }
      }

      return Container(
        color: const Color(0xFF0E161B),
        child: ClipRect(
          child: Stack(children: [
            // Time ruler, video and audio share identical coordinates.
            Positioned.fill(child: CustomPaint(painter: _RtlRulerPainter(
              currentSeconds: current,
              totalSeconds: _projectSeconds,
              pixelsPerSecond: _pixelsPerSecond,
            ))),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: _beginScrub,
              onHorizontalDragUpdate: _moveScrub,
              onHorizontalDragEnd: _endScrub,
              onHorizontalDragCancel: _cancelScrub,
              onTapDown: (details) {
                // A background tap moves the playhead without changing the selected clip.
                if (details.localPosition.dy < videoTop) {
                  _scrubTo(current + (centerX - details.localPosition.dx) / _pixelsPerSecond);
                }
              },
              child: const SizedBox.expand(),
            ),
            ...items,
            ...borderItems,
            ...handleItems,
            // Fixed, centered playhead: drawn above both tracks, not dragged itself.
            Positioned(left: centerX - 1, top: 15, bottom: 0,
              child: IgnorePointer(child: Container(width: 2, color: Colors.white))),
          ]),
        ),
      );
    });
  }
}

class _RtlRulerPainter extends CustomPainter {
  final double currentSeconds;
  final double totalSeconds;
  final double pixelsPerSecond;
  _RtlRulerPainter({required this.currentSeconds, required this.totalSeconds, required this.pixelsPerSecond});

  @override
  void paint(Canvas canvas, Size size) {
    final style = const TextStyle(color: Colors.white54, fontSize: 10);
    final start = math.max(0, (currentSeconds - size.width / (2 * pixelsPerSecond)).floor() - 1);
    final end = math.min(totalSeconds.ceil(), (currentSeconds + size.width / (2 * pixelsPerSecond)).ceil() + 1);
    for (int second = start; second <= end; second++) {
      final x = size.width / 2 + (currentSeconds - second) * pixelsPerSecond;
      final mm = (second ~/ 60).toString().padLeft(2, '0');
      final ss = (second % 60).toString().padLeft(2, '0');
      final label = TextPainter(text: TextSpan(text: '$mm:$ss', style: style),
          textDirection: TextDirection.ltr)..layout();
      label.paint(canvas, Offset(x - label.width / 2, 0));
      canvas.drawLine(Offset(x, 16), Offset(x, 20),
          Paint()..color = Colors.white38..strokeWidth = 1);
    }
  }

  @override
  bool shouldRepaint(covariant _RtlRulerPainter oldDelegate) =>
      currentSeconds != oldDelegate.currentSeconds || totalSeconds != oldDelegate.totalSeconds;
}

/// A visual rhythm pattern, not a decoded representation of the remote audio.
class _AudioTrackPainter extends CustomPainter {
  final double visibleStart;
  final double visibleEnd;
  _AudioTrackPainter({required this.visibleStart, required this.visibleEnd});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF5D69D8)..strokeWidth = 2;
    // Paint only the visible waveform samples; long tracks stay responsive.
    final begin = math.max(0.0, (visibleStart / 4).floor() * 4.0);
    final end = math.min(size.width, visibleEnd);
    for (double x = begin; x < end; x += 4) {
      final height = 2 + (math.sin(x * .12).abs() * 7) + (math.sin(x * .71).abs() * 3);
      canvas.drawLine(Offset(x, size.height / 2 - height / 2),
          Offset(x, size.height / 2 + height / 2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AudioTrackPainter oldDelegate) =>
      visibleStart != oldDelegate.visibleStart || visibleEnd != oldDelegate.visibleEnd;
}
