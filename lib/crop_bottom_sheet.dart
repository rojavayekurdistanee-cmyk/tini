import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'crop_model.dart';
import 'crop_color_filters.dart';
import 'crop_filters_panel.dart';
import 'crop_timeline.dart';
import 'crop_speed_model.dart';
import 'crop_speed_panel.dart';
import 'crop_magic_panel.dart';
import 'crop_animation_model.dart';
import 'crop_animation_panel.dart';
import 'crop_effects_model.dart';
import 'crop_effects_panel.dart';

class CropBottomSheet extends StatefulWidget {
  final VideoPlayerController? videoController;
  final Duration videoDuration;
  final List<Uint8List> videoThumbnails;
  final List<CropClip> cropClips;
  final bool isTimelineEmpty;
  final VoidCallback? onDeleteUnsplit;
  final Map<String, List<Uint8List>> replacementThumbnails;
  final Future<void> Function()? onReplace;
  final Future<void> Function()? onBackground;
  final Future<void> Function()? onCutout;
  final Future<void> Function()? onOverlay;
  final Future<void> Function()? onRetouch;
  final CropFilterSelection selectedColorFilter;
  final ValueChanged<CropFilterSelection>? onColorFilterPreview;
  final void Function(bool save, CropFilterSelection value)? onColorFilterFinish;
  final ValueChanged<bool>? onColorFilterVisibilityChanged;
  final CropSpeed selectedSpeed;
  final String? selectedMagicEffectId;
  final double? magicLayoutHeight;
  final double? animationLayoutHeight;
  final CropAnimationSettings selectedAnimations;
  final List<TiniAppliedEffect> selectedVideoEffects;
  final ValueChanged<List<TiniAppliedEffect>>? onVideoEffectsPreview;
  final void Function(List<TiniAppliedEffect>, List<TiniAppliedEffect>)? onVideoEffectsConfirm;
  final ValueChanged<List<TiniAppliedEffect>>? onVideoEffectsCancel;
  final ValueChanged<bool>? onVideoEffectsPanelVisibilityChanged;
  final ValueChanged<CropAnimationSettings>? onAnimationPreview;
  final void Function(String clipId, CropAnimationTab tab, double seconds, bool finished)?
      onAnimationTimelineResize;
  final void Function(CropAnimationSettings, CropAnimationSettings)? onAnimationConfirm;
  final ValueChanged<CropAnimationSettings>? onAnimationCancel;
  final ValueChanged<bool>? onAnimationPanelVisibilityChanged;
  final String magicSourcePath;
  final Duration magicSourceStart;
  final Duration magicSourceEnd;
  final ValueChanged<String?>? onMagicPreview;
  final void Function(String? original, String? updated)? onMagicConfirm;
  final ValueChanged<String?>? onMagicCancel;
  final ValueChanged<bool>? onMagicPanelVisibilityChanged;
  final ValueChanged<CropSpeed>? onSpeedPreview;
  final void Function(CropSpeed original, CropSpeed updated)? onSpeedConfirm;
  final ValueChanged<CropSpeed>? onSpeedCancel;
  final ValueChanged<bool>? onSpeedPanelVisibilityChanged;
  final Function(double start, double end) onTrimChanged;
  final Function(CropClip clip) onCropApplied;
  final Function(String clipId) onClipDeleted;
  final VoidCallback onClose;
  final VoidCallback? onRotate;
  final String audioName;
  final String? selectedClipId;
  final AudioPlayer? musicPlayer;
  final bool hasMusic;
  final RangeValues audioRange;
  final ValueChanged<RangeValues>? onAudioRangeChanged;
  final ValueChanged<String>? onClipSelected;
  final RangeValues initialRange;

  final VoidCallback onFullScreen;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final bool canUndo;
  final bool canRedo;
  final ValueNotifier<Duration> videoPositionNotifier;
  final ValueNotifier<Duration> totalDurationNotifier;
  final ValueNotifier<bool> isFrameSelectedNotifier;
  final Function(double positionFraction) onSplit;
  final Function(String clipId, bool isMuted) onClipMuteChanged;

  const CropBottomSheet({
    super.key,
    this.videoController,
    required this.videoDuration,
    required this.videoThumbnails,
    required this.cropClips,
    this.isTimelineEmpty = false,
    this.onDeleteUnsplit,
    this.replacementThumbnails = const {},
    this.onReplace,
    this.onBackground,
    this.onCutout,
    this.onOverlay,
    this.onRetouch,
    this.selectedColorFilter = const CropFilterSelection(),
    this.onColorFilterPreview,
    this.onColorFilterFinish,
    this.onColorFilterVisibilityChanged,
    this.selectedSpeed = const CropSpeed.normal(),
    this.selectedMagicEffectId,
    this.magicLayoutHeight,
    this.animationLayoutHeight,
    this.selectedAnimations = const CropAnimationSettings(),
    this.selectedVideoEffects = const [],
    this.onVideoEffectsPreview,
    this.onVideoEffectsConfirm,
    this.onVideoEffectsCancel,
    this.onVideoEffectsPanelVisibilityChanged,
    this.onAnimationPreview,
    this.onAnimationTimelineResize,
    this.onAnimationConfirm,
    this.onAnimationCancel,
    this.onAnimationPanelVisibilityChanged,
    this.magicSourcePath = '',
    this.magicSourceStart = Duration.zero,
    this.magicSourceEnd = Duration.zero,
    this.onMagicPreview,
    this.onMagicConfirm,
    this.onMagicCancel,
    this.onMagicPanelVisibilityChanged,
    this.onSpeedPreview,
    this.onSpeedConfirm,
    this.onSpeedCancel,
    this.onSpeedPanelVisibilityChanged,
    required this.onTrimChanged,
    required this.onCropApplied,
    required this.onClipDeleted,
    required this.onClose,
    this.onRotate,
    this.audioName = 'Last Grip',
    this.selectedClipId,
    this.musicPlayer,
    this.hasMusic = false,
    this.audioRange = const RangeValues(0, 1),
    this.onAudioRangeChanged,
    this.onClipSelected,
    this.initialRange = const RangeValues(0, 1),
    required this.onFullScreen,
    required this.onUndo,
    required this.onRedo,
    required this.canUndo,
    required this.canRedo,
    required this.videoPositionNotifier,
    required this.totalDurationNotifier,
    required this.isFrameSelectedNotifier,
    required this.onSplit,
    required this.onClipMuteChanged,
  });

  @override
  State<CropBottomSheet> createState() => _CropBottomSheetState();
}

class _CropBottomSheetState extends State<CropBottomSheet> {
  RangeValues _currentRange = const RangeValues(0.0, 1.0);
  String? _selectedClipId;
  bool _isCutMode = false;
  bool _isColorFilterMode = false;
  bool _isSpeedMode = false;
  bool _isMagicMode = false;
  bool _isAnimationMode = false;
  bool _isVideoEffectsMode = false;
  List<TiniAppliedEffect>? _videoEffectsAtOpen;
  CropAnimationSettings? _animationsAtOpen;
  String? _magicAtOpen;
  CropSpeed? _speedAtOpen;
  bool _isMuted = false;
  bool _musicInsideRange = false;

  @override
  void initState() {
    super.initState();
    widget.videoPositionNotifier.addListener(_syncMusicBoundary);
    _selectedClipId = widget.selectedClipId ?? widget.cropClips.firstOrNull?.id;
    _currentRange = widget.initialRange;
    if (widget.cropClips.isNotEmpty) {
      final clip = widget.cropClips.firstWhere(
        (c) => c.id == _selectedClipId,
        orElse: () => widget.cropClips.first,
      );
      _currentRange = RangeValues(clip.startFraction, clip.endFraction);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final start = widget.cropClips.isEmpty
          ? Duration(milliseconds: (widget.videoDuration.inMilliseconds * _currentRange.start).round())
          : widget.cropClips.first.startTime;
      widget.videoController?.pause();
      widget.musicPlayer?.pause();
      widget.videoController?.seekTo(start);
      widget.videoPositionNotifier.value = start;
    });
  }

  @override
  void didUpdateWidget(CropBottomSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoPositionNotifier != widget.videoPositionNotifier) {
      oldWidget.videoPositionNotifier.removeListener(_syncMusicBoundary);
      widget.videoPositionNotifier.addListener(_syncMusicBoundary);
    }
    if (oldWidget.initialRange != widget.initialRange && widget.cropClips.isEmpty) {
      _currentRange = widget.initialRange;
    }
    final missingSelection = _selectedClipId != null &&
        !widget.cropClips.any((clip) => clip.id == _selectedClipId);
    if (widget.cropClips.isEmpty) {
      // Undo لأول تقسيم يعيد المقطع المقصوص الواحد، لا حدود الفيديو الكامل.
      _selectedClipId = null;
      _currentRange = widget.initialRange;
    } else {
      if (widget.selectedClipId != oldWidget.selectedClipId || missingSelection) {
        _selectedClipId = widget.selectedClipId ?? widget.cropClips.first.id;
      }
      final clip = widget.cropClips.firstWhere(
        (c) => c.id == _selectedClipId,
        orElse: () => widget.cropClips.first,
      );
      _currentRange = RangeValues(clip.startFraction, clip.endFraction);
    }
  }

  void _openColorFilters() {
    if (widget.isTimelineEmpty || widget.onColorFilterPreview == null) return;
    widget.videoController?.pause();
    widget.musicPlayer?.pause();
    final selected = widget.cropClips
        .where((clip) => clip.id == _selectedClipId).firstOrNull;
    final start = selected?.startTime ?? Duration(milliseconds:
        (widget.videoDuration.inMilliseconds * _currentRange.start).round());
    widget.videoController?.seekTo(start);
    widget.videoPositionNotifier.value = start;
    widget.onColorFilterVisibilityChanged?.call(true);
    setState(() => _isColorFilterMode = true);
  }

  void _closeColorFilters(bool save, CropFilterSelection value) {
    widget.onColorFilterFinish?.call(save, value);
    widget.onColorFilterVisibilityChanged?.call(false);
    setState(() => _isColorFilterMode = false);
  }

  void _openSpeed() {
    if (widget.isTimelineEmpty || widget.onSpeedPreview == null) return;
    _speedAtOpen = widget.selectedSpeed;
    widget.onSpeedPanelVisibilityChanged?.call(true);
    widget.videoController?.pause();
    widget.musicPlayer?.pause();
    setState(() => _isSpeedMode = true);
  }

  void _closeSpeed(CropSpeed? updated) {
    final original = _speedAtOpen ?? widget.selectedSpeed;
    if (updated == null) {
      widget.onSpeedCancel?.call(original);
    } else {
      widget.onSpeedConfirm?.call(original, updated);
    }
    widget.onSpeedPanelVisibilityChanged?.call(false);
    setState(() { _isSpeedMode = false; _speedAtOpen = null; });
  }

  void _openMagic() {
    if (widget.isTimelineEmpty || widget.onMagicPreview == null) return;
    if (widget.magicSourcePath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('السحر متاح لمقاطع الفيديو فقط')));
      return;
    }
    _magicAtOpen = widget.selectedMagicEffectId;
    widget.videoController?.pause();
    widget.musicPlayer?.pause();
    final selected = widget.cropClips
        .where((clip) => clip.id == _selectedClipId).firstOrNull;
    final sourcePosition = selected?.startTime ?? Duration(milliseconds:
        (widget.videoDuration.inMilliseconds * _currentRange.start).round());
    widget.videoController?.seekTo(sourcePosition);
    widget.videoPositionNotifier.value = sourcePosition;
    widget.onMagicPanelVisibilityChanged?.call(true);
    setState(() => _isMagicMode = true);
  }

  void _closeMagic(String? updated, {required bool save}) {
    final original = _magicAtOpen;
    if (save) {
      widget.onMagicConfirm?.call(original, updated);
    } else {
      widget.onMagicCancel?.call(original);
    }
    widget.onMagicPanelVisibilityChanged?.call(false);
    setState(() { _isMagicMode = false; _magicAtOpen = null; });
  }

  void _openAnimations() {
    if (widget.isTimelineEmpty || widget.onAnimationPreview == null) return;
    _animationsAtOpen = widget.selectedAnimations;
    widget.videoController?.pause();
    widget.musicPlayer?.pause();
    widget.onAnimationPanelVisibilityChanged?.call(true);
    setState(() => _isAnimationMode = true);
  }

  void _closeAnimations(CropAnimationSettings? updated) {
    final original = _animationsAtOpen ?? widget.selectedAnimations;
    if (updated == null) {
      widget.onAnimationCancel?.call(original);
    } else {
      widget.onAnimationConfirm?.call(original, updated);
    }
    widget.onAnimationPanelVisibilityChanged?.call(false);
    setState(() { _isAnimationMode = false; _animationsAtOpen = null; });
  }

  void _openVideoEffects() {
    if (widget.isTimelineEmpty || widget.onVideoEffectsPreview == null) return;
    _videoEffectsAtOpen = List.of(widget.selectedVideoEffects);
    widget.videoController?.pause();
    widget.musicPlayer?.pause();
    widget.onVideoEffectsPanelVisibilityChanged?.call(true);
    setState(() => _isVideoEffectsMode = true);
  }

  void _closeVideoEffects(List<TiniAppliedEffect>? result) {
    final original = _videoEffectsAtOpen ?? widget.selectedVideoEffects;
    if (result == null) {
      widget.onVideoEffectsCancel?.call(original);
    } else {
      widget.onVideoEffectsConfirm?.call(original, result);
    }
    widget.onVideoEffectsPanelVisibilityChanged?.call(false);
    setState(() { _isVideoEffectsMode = false; _videoEffectsAtOpen = null; });
  }

  @override
  void dispose() {
    widget.videoPositionNotifier.removeListener(_syncMusicBoundary);
    super.dispose();
  }

  void _handleRangeChanged(double start, double end) {
    setState(() {
      _currentRange = RangeValues(start, end);
    });
    widget.onTrimChanged(start, end);
    widget.videoController?.pause();
    widget.musicPlayer?.pause();
    _musicInsideRange = false;
  }

  void _handleScrub(double fraction) {
    widget.videoController?.pause();
    widget.musicPlayer?.pause();
    _musicInsideRange = false;
    final safeFraction = fraction.clamp(0.0, 1.0);
    final newPosition = Duration(
      milliseconds: (widget.videoDuration.inMilliseconds * safeFraction).round(),
    );
    widget.videoController?.seekTo(newPosition);
    widget.videoPositionNotifier.value = newPosition;
    // Only added music is seekable: original video audio belongs to its video player.
    if (widget.hasMusic && widget.musicPlayer != null) {
      final projectLengthMs = widget.totalDurationNotifier.value.inMilliseconds;
      if (projectLengthMs > 0) {
        final timelineMs = _projectTimeFromSource(newPosition);
        final startMs = (widget.audioRange.start * projectLengthMs).round();
        final endMs = (widget.audioRange.end * projectLengthMs).round();
        if (timelineMs >= startMs && timelineMs <= endMs) {
          widget.musicPlayer!.seek(Duration(milliseconds: timelineMs));
        }
      }
    }
  }

  int _projectTimeFromSource(Duration sourcePosition) {
    if (widget.cropClips.isEmpty) {
      return (sourcePosition.inMilliseconds -
          (widget.videoDuration.inMilliseconds * _currentRange.start).round()).clamp(0,
          ((widget.videoDuration.inMilliseconds * (_currentRange.end - _currentRange.start)).round())).toInt();
    }
    int accumulated = 0;
    for (final clip in widget.cropClips) {
      if (sourcePosition >= clip.startTime && sourcePosition <= clip.endTime) {
        return accumulated + (clip.projectOffsetForSource(sourcePosition) * 1000).round();
      }
      accumulated += clip.playbackDuration.inMilliseconds;
    }
    return sourcePosition < widget.cropClips.first.startTime ? 0 : accumulated;
  }

  void _handleMuteToggle() {
    if (widget.cropClips.isEmpty) {
      setState(() => _isMuted =!_isMuted);
      widget.videoController?.setVolume(_isMuted? 0 : 1);
    } else {
      if (_selectedClipId == null) return;
      final selectedClip = widget.cropClips.firstWhere(
        (c) => c.id == _selectedClipId,
        orElse: () => widget.cropClips.first,
      );
      final newMuteState =!selectedClip.isMuted;
      widget.onClipMuteChanged(selectedClip.id, newMuteState);
    }
  }

  void _syncMusicBoundary() {
    if (!widget.hasMusic || widget.musicPlayer == null) return;
    final totalMs = widget.totalDurationNotifier.value.inMilliseconds;
    if (totalMs <= 0) return;
    final now = _projectTimeFromSource(widget.videoPositionNotifier.value);
    final begin = (widget.audioRange.start * totalMs).round();
    final end = (widget.audioRange.end * totalMs).round();
    final inRange = now >= begin && now < end;
    if (!inRange || widget.videoController?.value.isPlaying != true) {
      _musicInsideRange = false;
      if (widget.musicPlayer!.state == PlayerState.playing) {
        widget.musicPlayer!.pause();
      }
    } else if (!_musicInsideRange) {
      _startMusicIfInRange();
    }
  }

  void _startMusicIfInRange() {
    if (!widget.hasMusic || widget.musicPlayer == null) return;
    final now = _projectTimeFromSource(widget.videoPositionNotifier.value);
    final totalMs = widget.totalDurationNotifier.value.inMilliseconds;
    if (totalMs <= 0) return;
    final begin = (widget.audioRange.start * totalMs).round();
    final end = (widget.audioRange.end * totalMs).round();
    if (now < begin || now >= end) return;
    _musicInsideRange = true;
    widget.musicPlayer!.seek(Duration(milliseconds: now)).then((_) {
      if (mounted && _musicInsideRange && widget.videoController?.value.isPlaying == true) {
        widget.musicPlayer?.resume();
      }
    });
  }

  bool get _currentClipIsMuted {
    if (widget.cropClips.isEmpty) return _isMuted;
    if (_selectedClipId == null) return false;
    final selectedClip = widget.cropClips.firstWhere(
      (c) => c.id == _selectedClipId,
      orElse: () => widget.cropClips.first,
    );
    return selectedClip.isMuted;
  }

  void _recalculateTotalDuration() {
    int totalMs = 0;
    for (var c in widget.cropClips) {
      totalMs += c.playbackDuration.inMilliseconds;
    }
    if (widget.cropClips.isEmpty && !widget.isTimelineEmpty) {
      totalMs = (widget.videoDuration.inMilliseconds *
          (_currentRange.end - _currentRange.start)).round();
    }
    widget.totalDurationNotifier.value = Duration(milliseconds: totalMs);
  }

  @override
  Widget build(BuildContext context) {
    final double sheetHeight = _isAnimationMode && widget.animationLayoutHeight != null
        ? widget.animationLayoutHeight!
        : _isMagicMode && widget.magicLayoutHeight != null
        ? widget.magicLayoutHeight!
        : MediaQuery.of(context).size.height * (_isColorFilterMode || _isSpeedMode || _isMagicMode || _isAnimationMode || _isVideoEffectsMode ? 0.68 : 0.485);

    return Container(
      height: sheetHeight,
      decoration: const BoxDecoration(
        color: Color(0xFF0E161B),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),

          if (widget.videoController!= null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.fullscreen, color: Colors.white, size: 22),
                    onPressed: widget.onFullScreen,
                  ),
                  IconButton(
                    icon: Icon(Icons.undo,
                        color: widget.canUndo? Colors.white : Colors.white38, size: 22),
                    onPressed: !_isColorFilterMode && widget.canUndo? widget.onUndo : null,
                  ),
                  IconButton(
                    icon: Icon(Icons.redo,
                        color: widget.canRedo? Colors.white : Colors.white38, size: 22),
                    onPressed: !_isColorFilterMode && widget.canRedo? widget.onRedo : null,
                  ),
                  ValueListenableBuilder<Duration>(
                    valueListenable: widget.videoPositionNotifier,
                    builder: (context, _, __) {
                      return IconButton(
                        icon: Icon(
                          widget.videoController!.value.isPlaying
                            ? Icons.pause_circle_filled
                              : Icons.play_circle_filled,
                          color: Colors.white,
                          size: 40,
                        ),
                        onPressed: widget.isTimelineEmpty ? null : () {
                          final c = widget.videoController!;
                          if (c.value.isPlaying) {
                            c.pause();
                            widget.musicPlayer?.pause();
                            _musicInsideRange = false;
                          } else {
                            final endMs = (widget.videoDuration.inMilliseconds * _currentRange.end).round();
                            final startMs = (widget.videoDuration.inMilliseconds * _currentRange.start).round();

                            if (c.value.position.inMilliseconds >= endMs - 100) {
                              c.seekTo(Duration(milliseconds: startMs)).then((_) {
                                c.play();
                                _startMusicIfInRange();
                              });
                            } else {
                              c.play();
                              _startMusicIfInRange();
                            }
                          }
                          setState(() {});
                        },
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ValueListenableBuilder<Duration>(
                      valueListenable: widget.videoPositionNotifier,
                      builder: (context, position, _) {
                        return ValueListenableBuilder<Duration>(
                          valueListenable: widget.totalDurationNotifier,
                          builder: (context, totalDur, _) {
                            String two(int n) => n.toString().padLeft(2, '0');
                            final localPosition = Duration(milliseconds: _projectTimeFromSource(position));
                            final pos = '${two(localPosition.inMinutes)}:${two(localPosition.inSeconds % 60)}';
                            final effectiveTotal = totalDur.inMilliseconds == 0? widget.videoDuration : totalDur;
                            final dur = '${two(effectiveTotal.inMinutes)}:${two(effectiveTotal.inSeconds % 60)}';
                            return Text(
                              '$pos / $dur',
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _currentClipIsMuted? Icons.volume_off : Icons.volume_up,
                      color: Colors.white,
                      size: 22,
                    ),
                    onPressed: _handleMuteToggle,
                  ),
                ],
              ),
            ),

          Expanded(
            child: Container(
              color: const Color(0xFF0E161B),
              child: Align(
                alignment: Alignment.topCenter,
                child: ValueListenableBuilder<Duration>(
                  valueListenable: widget.videoPositionNotifier,
                  builder: (context, position, _) {
                    final fraction = widget.videoDuration.inMilliseconds == 0
                      ? 0.0
                        : position.inMilliseconds / widget.videoDuration.inMilliseconds;

                    return ValueListenableBuilder<bool>(
                      valueListenable: widget.isFrameSelectedNotifier,
                      builder: (context, isFrameSelected, _) {
                        return IgnorePointer(ignoring: _isColorFilterMode, child: CropTimeline(
                          isTimelineEmpty: widget.isTimelineEmpty,
                          videoDuration: widget.videoDuration,
                          thumbnails: widget.videoThumbnails,
                          cropClips: widget.cropClips,
                          onAnimationDurationChanged: widget.onAnimationTimelineResize,
                          replacementThumbnails: widget.replacementThumbnails,
                          currentRange: _currentRange,
                          onRangeChanged: _handleRangeChanged,
                          onClipRangeChanged: (clipId, start, end) {
                            _selectedClipId = clipId;
                            _handleRangeChanged(start, end);
                          },
                          onClipSelected: (id) {
                            setState(() {
                              _selectedClipId = id;
                              final selected = widget.cropClips.firstWhere((clip) => clip.id == id);
                              _currentRange = RangeValues(selected.startFraction, selected.endFraction);
                            });
                            widget.onClipSelected?.call(id);
                          },
                          selectedClipId: _selectedClipId,
                          audioName: widget.audioName,
                          hasMusic: widget.hasMusic,
                          audioRange: widget.audioRange,
                          onAudioRangeChanged: (range) {
                            widget.musicPlayer?.pause();
                            widget.onAudioRangeChanged?.call(range);
                          },
                          currentPosition: fraction,
                          onScrub: _handleScrub,
                          isFrameSelected: isFrameSelected,
                          onFrameSelectedChanged: (val) {
                            widget.isFrameSelectedNotifier.value = val;
                          },
                        ));
                      },
                    );
                  },
                ),
              ),
            ),
          ),

          if (_isColorFilterMode)
            Flexible(flex: 3, fit: FlexFit.loose,
              child: SingleChildScrollView(child: CropFiltersPanel(
                initial: widget.selectedColorFilter,
                thumbnails: widget.replacementThumbnails[widget.magicSourcePath]
                    ?? widget.videoThumbnails,
                onPreview: (value) => widget.onColorFilterPreview?.call(value),
                onConfirm: (value) => _closeColorFilters(true, value),
                onCancel: () => _closeColorFilters(false, widget.selectedColorFilter),
              )))
          else if (_isVideoEffectsMode)
            Flexible(flex: 3, fit: FlexFit.loose,
              child: TiniEffectsPanel(
                initial: widget.selectedVideoEffects,
                clipDuration: widget.cropClips
                    .where((c) => c.id == _selectedClipId).firstOrNull?.playbackDuration
                    ?? Duration(milliseconds: (widget.videoDuration.inMilliseconds *
                       (_currentRange.end - _currentRange.start)).round()),
                playheadSeconds: _selectedClipId != null && widget.cropClips.isNotEmpty
                    ? widget.cropClips.firstWhere((c) => c.id == _selectedClipId,
                        orElse: () => widget.cropClips.first)
                        .projectOffsetForSource(widget.videoPositionNotifier.value)
                    : (widget.videoPositionNotifier.value.inMilliseconds -
                        widget.videoDuration.inMilliseconds * _currentRange.start) / 1000.0,
                thumbnails: widget.replacementThumbnails[widget.magicSourcePath]
                    ?? widget.videoThumbnails,
                onPreview: (v) => widget.onVideoEffectsPreview?.call(v),
                onConfirm: (v) => _closeVideoEffects(v),
                onCancel: () => _closeVideoEffects(null),
              ),
            )
          else if (_isAnimationMode)
            Flexible(
              flex: 3,
              fit: FlexFit.loose,
              child: CropAnimationPanel(
                initial: widget.selectedAnimations,
                clipDuration: widget.cropClips
                    .where((clip) => clip.id == _selectedClipId)
                    .firstOrNull?.playbackDuration ?? Duration(milliseconds:
                    (widget.videoDuration.inMilliseconds *
                     (_currentRange.end - _currentRange.start)).round()),
                previewFrames: widget.replacementThumbnails[widget.magicSourcePath]
                    ?? widget.videoThumbnails,
                onPreview: (value) => widget.onAnimationPreview?.call(value),
                onConfirm: (value) => _closeAnimations(value),
                onCancel: () => _closeAnimations(null),
              ),
            )
          else if (_isMagicMode)
            Flexible(
              flex: 3,
              fit: FlexFit.loose,
              child: SingleChildScrollView(
                child: CropMagicPanel(
              sourcePath: widget.magicSourcePath,
              sourceStart: widget.magicSourceStart,
              sourceEnd: widget.magicSourceEnd,
              sourceDuration: widget.cropClips
                  .where((clip) => clip.id == _selectedClipId)
                  .firstOrNull?.replacementSourceDuration ?? widget.videoDuration,
              previewFrames: widget.replacementThumbnails[widget.magicSourcePath]
                  ?? widget.videoThumbnails,
              initialEffect: _magicAtOpen,
              onPreview: (id) => widget.onMagicPreview?.call(id),
              onConfirm: (id) => _closeMagic(id, save: true),
              onCancel: () => _closeMagic(null, save: false),
                ),
              ),
            )
          else if (_isSpeedMode)
            CropSpeedPanel(
              key: ValueKey(_speedAtOpen),
              initial: _speedAtOpen ?? widget.selectedSpeed,
              onPreview: (speed) => widget.onSpeedPreview?.call(speed),
              onConfirm: (speed) => _closeSpeed(speed),
              onCancel: () => _closeSpeed(null),
            )
          else Container(
            color: const Color(0xFF0E161B),
            padding: EdgeInsets.only(
              top: 12,
              bottom: MediaQuery.of(context).padding.bottom + 12,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Row(
                  children: _isCutMode? _buildCutModeButtons() : _buildMainButtons(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMainButtons() {
    return [
      _buildToolButton(
          icon: Icons.content_cut,
          label: 'قص',
          onTap: () {
            setState(() => _isCutMode = true);
            widget.isFrameSelectedNotifier.value = true;
            final startPos = Duration(
              milliseconds: (widget.videoDuration.inMilliseconds * _currentRange.start).round(),
            );
            widget.videoController?.seekTo(startPos);
            widget.videoController?.pause();
            widget.videoPositionNotifier.value = startPos;
          }),
      _buildToolButton(icon: Icons.music_note_outlined, label: 'صوت', onTap: () {}),
      _buildToolButton(icon: Icons.text_fields, label: 'نص', onTap: () {}),
      _buildToolButton(icon: Icons.auto_awesome_outlined, label: 'المؤثرات', onTap: _openVideoEffects),
      _buildToolButton(icon: Icons.auto_fix_high_outlined, label: 'سحر', onTap: _openMagic),
      _buildToolButton(icon: Icons.view_quilt_outlined, label: 'شرح', onTap: () {}),
      _buildToolButton(icon: Icons.layers_outlined, label: 'تراكب', onTap: widget.onOverlay == null ? null : () { widget.onOverlay!(); }),
      _buildToolButton(icon: Icons.emoji_emotions_outlined, label: 'ملصقات', onTap: () {}),
      _buildToolButton(icon: Icons.filter_vintage_outlined, label: 'الفلاتر', onTap: widget.onColorFilterPreview == null ? null : _openColorFilters),
      _buildToolButton(icon: Icons.tune, label: 'تعديل', onTap: () {}),
    ];
  }

  List<Widget> _buildCutModeButtons() {
    return [
      _buildToolButton(icon: Icons.keyboard_arrow_down, label: '', onTap: () {
        setState(() => _isCutMode = false);
        widget.isFrameSelectedNotifier.value = false;
      }),
      _buildToolButton(icon: Icons.cut, label: 'الانقسام', onTap: () {
        if (widget.isTimelineEmpty || widget.videoDuration.inMilliseconds <= 0) return;
        final fraction = widget.videoPositionNotifier.value.inMilliseconds / widget.videoDuration.inMilliseconds;
        widget.onSplit(fraction);
      }),
      _buildToolButton(icon: Icons.sync, label: 'استبدال',
          onTap: widget.onReplace == null ? null : () { widget.onReplace!(); }),
      _buildToolButton(
          icon: Icons.delete_outline,
          label: 'حذف',
          onTap: () {
            if (widget.isTimelineEmpty) return;
            // Before the first split, the video has no clip ID yet.
            if (widget.cropClips.isEmpty) {
              widget.onDeleteUnsplit?.call();
              return;
            }
            final selected = widget.cropClips.firstWhere(
              (clip) => clip.id == _selectedClipId,
              orElse: () => widget.cropClips.first,
            );
            // The parent owns selection, duration, player and Undo/Redo state.
            widget.onClipDeleted(selected.id);
          }),
      _buildToolButton(icon: Icons.speed, label: 'السرعة', onTap: _openSpeed),
      _buildToolButton(icon: Icons.auto_fix_high, label: 'سحر', onTap: _openMagic),
      _buildToolButton(icon: Icons.wallpaper, label: 'الخلفية',
          onTap: widget.onBackground == null ? null : () { widget.onBackground!(); }),
      _buildToolButton(icon: Icons.person_off_outlined, label: 'قص الخلفية',
          onTap: widget.onCutout == null ? null : () { widget.onCutout!(); }),
      _buildToolButton(icon: Icons.auto_awesome, label: 'المؤثرات', onTap: _openVideoEffects),
      _buildToolButton(icon: Icons.animation, label: 'رسوم متحركة',
          onTap: widget.onAnimationPreview == null ? null : _openAnimations),
      _buildToolButton(icon: Icons.filter, label: 'الفلاتر', onTap: widget.onColorFilterPreview == null ? null : _openColorFilters),
      _buildToolButton(icon: Icons.face_retouching_natural, label: 'التنميق', onTap: widget.onRetouch == null ? null : () { widget.onRetouch!(); }),
      _buildToolButton(icon: Icons.rotate_90_degrees_ccw, label: 'تدوير', onTap: widget.isTimelineEmpty ? null : widget.onRotate),
      _buildToolButton(icon: Icons.graphic_eq, label: 'تقليل الضوضاء', onTap: () {}),
      _buildToolButton(icon: Icons.volume_up_outlined, label: 'مستوى الصوت', onTap: () {}),
      _buildToolButton(icon: Icons.masks_outlined, label: 'القناع', onTap: () {}),
      _buildToolButton(icon: Icons.browse_gallery_outlined, label: 'تجميد الحركة', onTap: () {}),
      _buildToolButton(icon: Icons.replay_circle_filled_outlined, label: 'عكس', onTap: () {}),
      _buildToolButton(icon: Icons.layers, label: 'تراكب', onTap: widget.onOverlay == null ? null : () { widget.onOverlay!(); }),
      _buildToolButton(icon: Icons.tune, label: 'تعديل', onTap: () {}),
      _buildToolButton(icon: Icons.mic_none, label: 'مؤثر صوتي', onTap: () {}),
      _buildToolButton(icon: Icons.opacity_outlined, label: 'تعتيم', onTap: () {}),
    ];
  }

  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    Color? color,
  }) {
    final bool isEnabled = onTap!= null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isEnabled? (color?? Colors.white) : Colors.white24,
              size: 24,
            ),
            if (label.isNotEmpty)...[
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: isEnabled? Colors.white70 : Colors.white24,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
