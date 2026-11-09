// [Tini] ملف media_preview_screen.dart - نسخة "استلام الهوية وتمرير البيانات" + Audio Mixer
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:video_player/video_player.dart';
import 'media_picker_screen.dart';
import 'grid_layout_sheet.dart';
import 'post_publish_screen.dart';
import 'package:path_provider/path_provider.dart'; // هذا لـ getTemporaryDirectory
import 'package:dio/dio.dart'; // هذا لـ Dio
import 'video_processor.dart';
import 'tini_edit_warmup.dart';
import 'tini_edit_cache.dart';
import 'media_sync_controller.dart';
import 'package:image/image.dart' show decodeImage, encodeJpg, copyResize;
import 'package:audio_session/audio_session.dart';
import 'music_library_sheet.dart';
import 'package:provider/provider.dart';
import 'story_provider.dart';
import 'text_editor_overlay.dart';
import 'text_layer.dart';
import 'sticker_layer.dart';
import 'sticker_widget.dart';
import 'sticker_picker_sheet.dart';
import 'filter_model.dart';
import 'filter_bottom_sheet.dart';
import 'filters_repository.dart';
import 'crop_model.dart';
import 'crop_rotation.dart';
import 'crop_color_filters.dart';
import 'crop_overlay_model.dart';
import 'crop_overlay_editor.dart';
import 'crop_overlay_export.dart';
import 'crop_overlay_preview.dart';
import 'crop_retouch_model.dart';
import 'crop_retouch_editor.dart';
import 'crop_retouch_gpu.dart';
import 'crop_cut_actions.dart';
import 'crop_bottom_sheet.dart';
import 'crop_speed_model.dart';
import 'crop_replace_picker.dart';
import 'crop_magic_live_preview.dart';
import 'crop_animation_model.dart';
import 'crop_animation_preview.dart';
import 'crop_effects_model.dart';
import 'crop_effects_preview.dart';
import 'crop_body_fx_engine.dart';
import 'dart:async' as tini_async;
import 'crop_background_model.dart';
import 'crop_background_engine.dart';
import 'crop_background_picker.dart';
import 'crop_cutout_panel.dart';
import 'package:flutter/services.dart'; // ← ضيف هاد
import 'auth_provider.dart' as custom;
import 'package:audioplayers/audioplayers.dart'
    hide AVAudioSessionCategory, AVAudioSessionCategoryOptions;

class MediaPreviewScreen extends StatefulWidget {
  final List<AssetEntity>? selectedMedia;
  final File? videoFile;
  final bool isDuet;
  final String? duetVideoUrl;
  final DuetLayout? duetLayout;
  final Duration? duetVideoDuration;

  // --- بداية الإضافات الجديدة (المستقبلات) ---
  final String? fullName;
  final String? username;
  final String? profileImg;
  final String? uid;
  final String? originalAuthorName;
  final String? originalUsername;
  final String? originalOwnerId; // <-- جديد
  final DuetLayout selectedLayout; // <--- أضف هذا السطر هنا
  // --- نهاية الإضافات الجديدة ---

  const MediaPreviewScreen({
    super.key,
    this.selectedMedia,
    this.videoFile,
    this.isDuet = false,
    this.duetVideoUrl,
    this.duetLayout,
    this.duetVideoDuration,
    // إضافة المتغيرات في الباني لاستقبالها من الشاشة السابقة
    this.fullName,
    this.username,
    this.profileImg,
    this.uid,
    this.originalAuthorName,
    this.originalUsername,
    this.originalOwnerId, // <-- جديد
    required this.selectedLayout, // <--- وأضفه هنا في الكونستركتور
  });

  @override
  State<MediaPreviewScreen> createState() => _MediaPreviewScreenState();
}

class _MediaPreviewScreenState extends State<MediaPreviewScreen> {
  final _editWarmup = TiniEditWarmup();
  // A committed visual revision has its own identity and exact parent.
  // Undo restores the saved identity; branching creates a fresh revision.
  final String _editSessionId =
      DateTime.now().microsecondsSinceEpoch.toString();
  int _editRevisionCounter = 0;
  String? _editorRevision, _parentEditorRevision, _editorRevisionState;

  static const platform = MethodChannel(
    'titi_star/thumbnails',
  ); // ← ضيف هاد السطر
  final GlobalKey<ScaffoldState> _scaffoldKey =
      GlobalKey<ScaffoldState>(); // ← هاد بس
  late PageController _pageController;
  late ScrollController _thumbnailScrollController;
  int _currentIndex = 0;
  bool _isPinned = false;
  bool _isAutoScrolling = true;
  bool _isProcessing = false;
  bool _isStoryUploading = false;
  List<TextLayer> _textLayers = []; // النصوص اللي بتنرسم فوق الفيديو
  List<StickerLayer> _stickerLayers = []; // كل الستيكرات اللي فوق الفيديو
  FilterModel _selectedFilter =
      FiltersRepository.allFilters.first; // الفلتر المختار
  bool _isFilterMode = false; // هل وضع الفلاتر شغال
  List<FilterClip> _filterClips = []; // ← ضيف هاد السطر
  List<CropOverlay> _cropOverlays = [];
  bool _overlayBusy = false;
  bool? _warmupPlaying;
  bool _retouchBusy = false;
  VideoPlayerController? _retouchPlayer;
  String? _retouchPath, _retouchKey, _retouchRequestedKey;
  bool _retouchRendering = false;
  int _retouchGeneration = 0;
  tini_async.Timer? _retouchDebounce;
  bool _isCropMode = false; // هل وضع القص شغال
  final ValueNotifier<bool> _isSeekingCropNotifier = ValueNotifier(false);
  // Publish's provisional preview shares only these stable UI flags.
  final ValueNotifier<bool> _publishFrameSelected = ValueNotifier(false);
  final ValueNotifier<bool> _publishSeeking = ValueNotifier(false);
  final ValueNotifier<bool> _isFrameSelectedNotifier = ValueNotifier<bool>(
    false,
  );
  List<CropClip> _cropClips = [];
  bool _cropAllDeleted =
      false; // An empty edited timeline is not the original video.
  // Replaced media is isolated to the crop editor; all other screen features
  // continue using their existing controllers and media selection.
  File? _fullReplacementFile;
  int? _fullReplacementIndex;
  final Map<String, VideoPlayerController> _replacementPlayers = {};
  final Map<String, List<Uint8List>> _replacementThumbnails = {};
  String? _currentlyPlayingReplacement;
  bool _replacingClip = false;
  bool _speedPanelExpanded = false;
  bool _magicPanelExpanded = false;
  bool _animationPanelExpanded = false;
  bool _videoEffectsPanelExpanded = false;
  tini_async.Timer? _bodyLiveTimer;
  bool _bodyLivePolling = false;
  int _lastBodyLiveTimeMs = -1;
  String? _lastBodyLiveClipId;
  int _bodyPreviewRequest = 0;
  final Set<String> _bodyPreviewClipIds = <String>{};

  bool _backgroundBusy = false;
  VideoPlayerController? _backgroundPreviewPlayer;
  String? _backgroundPreviewClipId;
  String? _backgroundPreviewKey;
  String? _backgroundPreviewPath;
  double _backgroundPreviewSpeed = -1.0;

  _CropEditState? _magicEditBeforeState;
  _CropEditState? _animationEditBeforeState;
  _CropEditState? _videoEffectsBeforeState;
  _CropEditState? _colorFilterBeforeState;
  _CropEditState? _animationTimelineBeforeDrag;
  _CropEditState? _speedEditBeforeState;
  int? _speedInitialProjectMs;
  RangeValues? _speedInitialMusicRange;
  double _lastAppliedVideoSpeed = -1.0;
  double _lastAppliedReplacementSpeed = -1.0;
  StateSetter? _refreshCropSheet;
  // UI range for the separate added-audio track in the crop sheet.
  RangeValues _cropMusicRange = const RangeValues(0, 1);
  List<_CropEditState> _cropUndoStack = [];
  List<_CropEditState> _cropRedoStack = [];
  int? _selectedCropIndex;
  RangeValues _currentTrimRange = const RangeValues(0.0, 1.0);
  Duration _realVideoStart = Duration.zero; // البداية الحقيقية بعد القص
  Duration _realVideoEnd = Duration.zero; // النهاية الحقيقية بعد القص
  List<List<FilterClip>> _undoStack = []; // ← حط هاد
  List<List<FilterClip>> _redoStack = []; // ← وهاد
  int? _selectedClipIndex; // ← وهاد عشان نعرف أي كليب محدد
  List<Uint8List> _videoThumbnails = []; // ← الصق هاد
  ValueNotifier<Duration> _videoPositionNotifier = ValueNotifier(Duration.zero);
  ValueNotifier<Duration> _totalDurationNotifier = ValueNotifier(Duration.zero);
  MediaSyncController? _syncController;

  // --- بداية إضافات Audio Mixer ---
  double videoVolume = 0.2; // القيمة الافتراضية: صوت الفيديو هادئ
  double musicVolume = 1.0; // القيمة الافتراضية: الموسيقى واضحة
  final List<VideoPlayerController> _activeVideoControllers =
      []; // للتحكم بالديو بسلايدر واحد
  // --- نهاية إضافات Audio Mixer ---

  // إدارة الموسيقى
  final ValueNotifier<String> audioTitleNotifier = ValueNotifier<String>(
    "إضافة صوت",
  );
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _selectedAudioUrl;
  String? _selectedAudioTitle;
  String? _selectedAudioArtist;
  String _audioSource =
      'original'; // القيمة الافتراضية إذا لم يتم اختيار موسيقى
  String? _selectedAudioCover; // أضف هذا المتغير بجانب _selectedAudioUrl

  Uint8List? _gridSnapshot;
  bool get _hasGrid => _gridSnapshot != null;

  int get _totalCount {
    if (widget.videoFile != null || widget.isDuet) return 1;
    return (widget.selectedMedia?.length ?? 0) + (_hasGrid ? 1 : 0);
  }

  @override
  void initState() {
    super.initState();
    _initAudioSession();
    _generateVideoThumbnails(); // ← الصق هاد

    _pageController = PageController(initialPage: 0, keepPage: true);
    _thumbnailScrollController = ScrollController();
    _thumbnailScrollController.addListener(_syncPageViewWithScroll);

    if (widget.videoFile == null && !widget.isDuet) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) _startAutoScrollEffect();
        });
      });
    } else {
      _isAutoScrolling = false;
    }
  }

  void _updateSyncController() {
    _syncController?.dispose();
    _syncController = MediaSyncController(
      audio: _audioPlayer,
      videos: _activeVideoControllers,
    );
  }

  void _togglePlayPause() {
    final bool hasMusic = _selectedAudioUrl != null;
    final bool hasVideo = _activeVideoControllers.isNotEmpty;

    if (_cropAllDeleted && hasVideo) return;
    if (hasMusic && hasVideo) {
      if (_syncController == null) return;
      final isPlaying = _audioPlayer.state == PlayerState.playing;
      isPlaying ? _syncController!.pauseAll() : _syncController!.playAll();
    } else if (hasVideo) {
      final isPlaying = _activeVideoControllers.any((v) => v.value.isPlaying);
      for (var c in _activeVideoControllers) {
        // اذا مقصوص وبرا المنطقة، رجعه للبداية المقصوصة
        if (_realVideoStart != Duration.zero &&
            c.value.position < _realVideoStart) {
          c.seekTo(_realVideoStart);
        }
        isPlaying ? c.pause() : c.play();
      }
    } else if (hasMusic) {
      _audioPlayer.state == PlayerState.playing
          ? _audioPlayer.pause()
          : _audioPlayer.resume();
    }
    setState(() {});
  }

  Future<void> _initAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(
      const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.mixWithOthers,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType:
            AndroidAudioFocusGainType.gain, // ← الصح هو gain
        androidWillPauseWhenDucked: false,
      ),
    );
  }

  // --- بداية دوال Audio Mixer ---
  void _setVideoVolume(double value) {
    setState(() => videoVolume = value);
    // تطبيق على كل كونترولرز الفيديو: في الديو بيكونوا 2، في العادي 1
    for (var controller in _activeVideoControllers) {
      controller.setVolume(value);
    }
  }

  void _setMusicVolume(double value) {
    setState(() => musicVolume = value);
    _audioPlayer.setVolume(value);
  }

  void _registerVideoController(VideoPlayerController controller) {
    if (!_activeVideoControllers.contains(controller)) {
      _activeVideoControllers.add(controller);
      controller.setVolume(videoVolume);
      // The original full-video loop is disabled only while editing the crop.
      controller.setLooping(!_isCropMode && !_cropAllDeleted);
      if (_isCropMode) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _refreshCropSheet?.call(() {});
        });
      }

      controller.addListener(() async {
        if (!mounted || !controller.value.isInitialized) return;
        final pos = controller.value.position;
        if (_cropAllDeleted) {
          if (controller.value.isPlaying) controller.pause();
          return;
        }
        _applyCropPlaybackSpeed(controller, pos);
        _syncReplacementPlayback(controller);
        _syncBackgroundPlayback(controller);
        _syncRetouchPreview(controller);
        if (_warmupPlaying != controller.value.isPlaying) {
          _warmupPlaying = controller.value.isPlaying;
          _scheduleEditWarmup();
        }

        // A single trimmed video is stored in _currentTrimRange, not _cropClips.
        // Enforce its source start/end while playing, including natural completion.
        if (_isCropMode &&
            _cropClips.isEmpty &&
            !_isSeekingCropNotifier.value) {
          final sourceMs = controller.value.duration.inMilliseconds;
          if (sourceMs > 0) {
            final cropStart = Duration(
              milliseconds: (sourceMs * _currentTrimRange.start).round(),
            );
            final cropEnd = Duration(
              milliseconds: (sourceMs * _currentTrimRange.end).round(),
            );
            if ((controller.value.isPlaying || controller.value.isCompleted) &&
                (pos < cropStart || pos >= cropEnd)) {
              _isSeekingCropNotifier.value = true;
              try {
                await controller.seekTo(cropStart);
                if (mounted && _isCropMode) {
                  await controller.play();
                  _videoPositionNotifier.value = cropStart;
                }
              } finally {
                if (mounted) _isSeekingCropNotifier.value = false;
              }
              return;
            }
          }
        }

        if (_isCropMode && _cropClips.isNotEmpty) {
          // User scrubbing/trimming while paused must NOT trigger the playback loop.
          if (!controller.value.isPlaying && !controller.value.isCompleted) {
            _syncReplacementPlayback(controller);
            _syncBackgroundPlayback(controller);
            _syncRetouchPreview(controller);
            _videoPositionNotifier.value = pos;
            return;
          }
          if (_isSeekingCropNotifier.value) return;

          if (pos < _cropClips.first.startTime) {
            _isSeekingCropNotifier.value = true;
            await controller.seekTo(_cropClips.first.startTime);
            await controller.play();
            _isSeekingCropNotifier.value = false;
            _videoPositionNotifier.value = _cropClips.first.startTime;
            return;
          }

          if (pos >= _cropClips.last.endTime) {
            _isSeekingCropNotifier.value = true;
            await controller.seekTo(_cropClips.first.startTime);
            await controller.play();
            _isSeekingCropNotifier.value = false;
            _videoPositionNotifier.value = _cropClips.first.startTime;
            return;
          }

          final inAnyClip = _cropClips.any(
            (c) => pos >= c.startTime && pos < c.endTime,
          );
          if (!inAnyClip) {
            for (final clip in _cropClips) {
              if (pos < clip.startTime) {
                _isSeekingCropNotifier.value = true;
                await controller.seekTo(clip.startTime);
                await controller.play();
                _isSeekingCropNotifier.value = false;
                _videoPositionNotifier.value = clip.startTime;
                return;
              }
            }
            _isSeekingCropNotifier.value = true;
            await controller.seekTo(_cropClips.first.startTime);
            await controller.play();
            _isSeekingCropNotifier.value = false;
            _videoPositionNotifier.value = _cropClips.first.startTime;
            return;
          }
        }
        _videoPositionNotifier.value = pos;

        // الصوت
        if (_cropClips.isNotEmpty) {
          try {
            final activeClip = _cropClips.firstWhere(
              (c) => pos >= c.startTime && pos < c.endTime,
              orElse: () => _cropClips.first,
            );
            final overlayIsActive =
                _backgroundPreviewPlayer?.value.isInitialized == true &&
                activeClip.id == _backgroundPreviewClipId &&
                _backgroundKey(activeClip) == _backgroundPreviewKey &&
                (activeClip.backgroundPath != null ||
                    activeClip.cutout != null);
            controller.setVolume(
              activeClip.replacementPath != null ||
                      activeClip.isMuted ||
                      overlayIsActive
                  ? 0
                  : videoVolume,
            );
            _syncBackgroundPlayback(controller);
            _syncRetouchPreview(controller);
          } catch (_) {}
        }
      });

      _updateSyncController();

      if (_selectedAudioUrl != null) {
        _syncController?.playAll();
      } else {
        controller.play();
      }
    }
  }

  double _speedForClip(CropClip clip, Duration sourcePosition) {
    if (clip.duration.inMicroseconds <= 0) return 1.0;
    final t =
        (sourcePosition - clip.startTime).inMicroseconds /
        clip.duration.inMicroseconds;
    return clip.speed.speedAt(t).clamp(0.1, 10.0).toDouble();
  }

  void _applyCropPlaybackSpeed(
    VideoPlayerController controller,
    Duration position,
  ) {
    if (!_isCropMode || _cropAllDeleted) return;
    var wanted = 1.0;
    for (final clip in _cropClips) {
      if (position >= clip.startTime && position < clip.endTime) {
        wanted = _speedForClip(clip, position);
        break;
      }
    }
    if ((wanted - _lastAppliedVideoSpeed).abs() > 0.035) {
      _lastAppliedVideoSpeed = wanted;
      controller.setPlaybackSpeed(wanted).catchError((Object error) {
        debugPrint('Tini speed preview unavailable: $error');
      });
    }
  }

  void _resetCropPlaybackSpeeds() {
    _lastAppliedVideoSpeed = -1.0;
    _lastAppliedReplacementSpeed = -1.0;
    for (final controller in _activeVideoControllers) {
      controller.setPlaybackSpeed(1.0);
    }
    for (final controller in _replacementPlayers.values) {
      controller.setPlaybackSpeed(1.0);
    }
  }

  void _unregisterVideoController(VideoPlayerController controller) {
    _activeVideoControllers.remove(controller);
    _updateSyncController();
  }

  // Keep the original playback clock for the project. A replaced segment
  // has an independent source in-point and never rewrites the other clips.
  void _syncReplacementPlayback(VideoPlayerController base) {
    if (!_isCropMode || _replacementPlayers.isEmpty) return;
    final pos = base.value.position;
    CropClip? selected;
    for (final clip in _cropClips) {
      if (clip.replacementPath != null &&
          pos >= clip.startTime &&
          pos < clip.endTime) {
        selected = clip;
        break;
      }
    }
    final path = selected?.replacementPath;
    if (_currentlyPlayingReplacement != path) {
      for (final other in _replacementPlayers.values) {
        other.pause();
      }
      _currentlyPlayingReplacement = path;
      _lastAppliedReplacementSpeed = -1.0;
    }
    if (path == null || selected == null) return;
    final replacement = _replacementPlayers[path];
    if (replacement == null || !replacement.value.isInitialized) return;
    final target = selected.replacementStartTime + (pos - selected.startTime);
    final divergence = (replacement.value.position - target).inMilliseconds
        .abs();
    if (divergence > 220 || !base.value.isPlaying) replacement.seekTo(target);
    final wanted = _speedForClip(selected, pos);
    if ((wanted - _lastAppliedReplacementSpeed).abs() > 0.035) {
      _lastAppliedReplacementSpeed = wanted;
      replacement.setPlaybackSpeed(wanted).catchError((Object error) {
        debugPrint('Tini replacement speed preview unavailable: $error');
      });
    }
    replacement.setVolume(selected.isMuted ? 0 : videoVolume);
    if (base.value.isPlaying && !replacement.value.isPlaying)
      replacement.play();
    if (!base.value.isPlaying && replacement.value.isPlaying)
      replacement.pause();
  }

  String _backgroundKey(CropClip clip) =>
      '${clip.id}|${clip.backgroundPath}|'
      '${clip.cutout?.maskDirectory}|${identityHashCode(clip.cutout)}|'
      '${clip.startTime.inMicroseconds}|${clip.endTime.inMicroseconds}|'
      '${clip.replacementPath}|${clip.replacementStartTime.inMicroseconds}';

  void _syncBackgroundPlayback(VideoPlayerController base) {
    final player = _backgroundPreviewPlayer;
    // The already prepared cutout stays visible after closing the crop sheet.
    // Do not start a new FFmpeg render when navigating between editor pages.
    if (player == null || !player.value.isInitialized) return;
    CropClip? active;
    final position = base.value.position;
    for (final clip in _cropClips) {
      if (position >= clip.startTime &&
          position < clip.endTime &&
          (clip.backgroundPath != null || clip.cutout != null)) {
        active = clip;
        break;
      }
    }
    if (active == null ||
        active.id != _backgroundPreviewClipId ||
        _backgroundKey(active) != _backgroundPreviewKey) {
      if (player.value.isPlaying) player.pause();
      return;
    }
    final relative = position - active.startTime;
    if ((player.value.position - relative).inMilliseconds.abs() > 220 ||
        !base.value.isPlaying) {
      player.seekTo(relative);
    }
    final speed = _speedForClip(active, position);
    if ((speed - _backgroundPreviewSpeed).abs() > .035) {
      _backgroundPreviewSpeed = speed;
      player.setPlaybackSpeed(speed).catchError((Object _) {});
    }
    // The precomposited preview already contains the source audio.
    base.setVolume(0);
    player.setVolume(active.isMuted ? 0 : videoVolume);
    if (base.value.isPlaying && !player.value.isPlaying) player.play();
    if (!base.value.isPlaying && player.value.isPlaying) player.pause();
  }

  Future<void> _refreshBackgroundPreview(
    CropClip clip,
    String originalPath,
  ) async {
    if (clip.backgroundPath == null && clip.cutout == null) return;
    if (_backgroundBusy) return;
    setState(() => _backgroundBusy = true);
    String? rendered;
    try {
      final origin = clip.replacementPath ?? originalPath;
      final begin = clip.replacementPath == null
          ? clip.startTime
          : clip.replacementStartTime;
      rendered = await CropBackgroundEngine.composeClip(
        source: origin,
        sourceStart: begin,
        clip: clip,
        width: 360,
        height: 640,
        preview: true,
      );
      final player = VideoPlayerController.file(
        File(rendered),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      try {
        await player.initialize();
        await player.setLooping(false);
      } catch (_) {
        await player.dispose();
        rethrow;
      }
      if (!mounted) {
        await player.dispose();
        return;
      }
      final previous = _backgroundPreviewPlayer;
      final oldPath = _backgroundPreviewPath;
      setState(() {
        _backgroundPreviewPlayer = player;
        _backgroundPreviewClipId = clip.id;
        _backgroundPreviewKey = _backgroundKey(clip);
        _backgroundPreviewPath = rendered;
        _backgroundPreviewSpeed = -1.0;
      });
      await previous?.dispose();
      if (oldPath != null) {
        try {
          await File(oldPath).delete();
        } catch (_) {}
      }
      _activeVideoControllers.firstOrNull?.setVolume(0);
      if (_activeVideoControllers.isNotEmpty) {
        _syncBackgroundPlayback(_activeVideoControllers.first);
      }
    } catch (error) {
      if (rendered != null) {
        try {
          await File(rendered).delete();
        } catch (_) {}
      }
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('فشلت معاينة الخلفية: $error')));
    } finally {
      if (mounted) setState(() => _backgroundBusy = false);
    }
  }

  CropClip? _backgroundTargetClip() {
    if (_cropAllDeleted || _activeVideoControllers.isEmpty) return null;
    if (_cropClips.isNotEmpty) {
      return _cropClips[(_selectedCropIndex ?? 0).clamp(
        0,
        _cropClips.length - 1,
      )];
    }
    final duration = _activeVideoControllers.first.value.duration;
    if (duration.inMilliseconds <= 0) return null;
    return CropClip(
      id: 'background_base_clip',
      startTime: Duration(
        milliseconds: (duration.inMilliseconds * _currentTrimRange.start)
            .round(),
      ),
      endTime: Duration(
        milliseconds: (duration.inMilliseconds * _currentTrimRange.end).round(),
      ),
      startFraction: _currentTrimRange.start,
      endFraction: _currentTrimRange.end,
    );
  }

  Future<void> _editCropBackground() async {
    if (_backgroundBusy) return;
    final clip = _backgroundTargetClip();
    if (clip == null) return;
    _activeVideoControllers.first.pause();
    _audioPlayer.pause();
    final choice = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const CropBackgroundPicker()),
    );
    if (!mounted || choice == null || choice == clip.backgroundPath) return;
    final remove = choice == '__tini_remove_background__';
    if (remove && clip.backgroundPath == null) return;
    _saveCropStateForUndo();
    final next = remove ? clip.clearBackground() : clip.withBackground(choice);
    setState(() {
      if (_cropClips.isEmpty) {
        _cropClips = [next];
        _selectedCropIndex = 0;
      } else {
        _cropClips[(_selectedCropIndex ?? 0).clamp(0, _cropClips.length - 1)] =
            next;
      }
    });
    _refreshCropSheet?.call(() {});
    if (next.cutout != null || next.backgroundPath != null) {
      await _refreshBackgroundPreview(
        next,
        _activeVideoControllers.first.dataSource,
      );
    } else {
      final previous = _backgroundPreviewPlayer;
      final oldPath = _backgroundPreviewPath;
      setState(() {
        _backgroundPreviewPlayer = null;
        _backgroundPreviewClipId = null;
        _backgroundPreviewKey = null;
        _backgroundPreviewPath = null;
      });
      await previous?.dispose();
      if (oldPath != null) {
        try {
          await File(oldPath).delete();
        } catch (_) {}
      }
      _activeVideoControllers.first.setVolume(videoVolume);
    }
  }

  Future<void> _editCropCutout() async {
    if (_backgroundBusy) return;
    final clip = _backgroundTargetClip();
    if (clip == null) return;
    _activeVideoControllers.first.pause();
    _audioPlayer.pause();
    final source =
        clip.replacementPath ?? _activeVideoControllers.first.dataSource;
    final begin = clip.replacementPath == null
        ? clip.startTime
        : clip.replacementStartTime;
    final selection = await Navigator.of(context).push<CropCutoutResult>(
      MaterialPageRoute(
        builder: (_) =>
            CropCutoutPanel(sourcePath: source, sourceStart: begin, clip: clip),
      ),
    );
    if (!mounted || selection == null) return;
    _saveCropStateForUndo();
    final next = selection.settings == null
        ? clip.clearCutout()
        : clip.withCutout(selection.settings);
    setState(() {
      if (_cropClips.isEmpty) {
        _cropClips = [next];
        _selectedCropIndex = 0;
      } else {
        _cropClips[(_selectedCropIndex ?? 0).clamp(0, _cropClips.length - 1)] =
            next;
      }
    });
    _refreshCropSheet?.call(() {});
    if (next.cutout != null || next.backgroundPath != null) {
      await _refreshBackgroundPreview(
        next,
        _activeVideoControllers.first.dataSource,
      );
    } else {
      final previous = _backgroundPreviewPlayer;
      final oldPath = _backgroundPreviewPath;
      setState(() {
        _backgroundPreviewPlayer = null;
        _backgroundPreviewClipId = null;
        _backgroundPreviewKey = null;
        _backgroundPreviewPath = null;
      });
      await previous?.dispose();
      if (oldPath != null) {
        try {
          await File(oldPath).delete();
        } catch (_) {}
      }
      _activeVideoControllers.first.setVolume(videoVolume);
    }
  }

  void _previewMagicEffect(String? effectId) {
    if (_cropAllDeleted || _activeVideoControllers.isEmpty) return;
    final source = _activeVideoControllers.first;
    if (!source.value.isInitialized ||
        source.value.duration.inMilliseconds <= 0)
      return;
    _magicEditBeforeState ??= _captureCropState();
    setState(() {
      if (_cropClips.isEmpty && effectId != null) {
        final total = source.value.duration.inMilliseconds;
        _cropClips = [
          CropClip(
            id: 'magic_base_clip',
            startTime: Duration(
              milliseconds: (total * _currentTrimRange.start).round(),
            ),
            endTime: Duration(
              milliseconds: (total * _currentTrimRange.end).round(),
            ),
            startFraction: _currentTrimRange.start,
            endFraction: _currentTrimRange.end,
          ),
        ];
        _selectedCropIndex = 0;
      }
      if (_cropClips.isNotEmpty) {
        final index = (_selectedCropIndex ?? 0)
            .clamp(0, _cropClips.length - 1)
            .toInt();
        _selectedCropIndex = index;
        _cropClips[index] = _cropClips[index].withMagic(effectId);
      }
    });
    _refreshCropSheet?.call(() {});
  }

  void _finishMagicEffect({required bool save, String? updated}) {
    final previous = _magicEditBeforeState;
    _magicEditBeforeState = null;
    if (previous == null) return;
    final prevId =
        previous.selectedIndex != null &&
            previous.selectedIndex! < previous.clips.length
        ? previous.clips[previous.selectedIndex!].magicEffectId
        : null;
    if (!save || (prevId == updated)) {
      setState(() => _restoreCropState(previous));
    } else {
      _cropUndoStack.add(previous);
      _cropRedoStack.clear();
    }
  }

  // One-frame-at-a-time tracking while the video plays. This path is for
  // preview only; high-quality export still uses TiniBodyFxEngine.prepare().
  Future<void> _pollLiveBodyFrame() async {
    if (!mounted ||
        !_isCropMode ||
        _bodyLivePolling ||
        _cropAllDeleted ||
        _cropClips.isEmpty)
      return;
    final position = _videoPositionNotifier.value;
    CropClip? clip;
    for (final candidate in _cropClips) {
      if (position >= candidate.startTime && position < candidate.endTime) {
        clip = candidate;
        break;
      }
    }
    if (clip == null || !TiniBodyFxEngine.hasBodyEffects(clip.videoEffects)) {
      if (_lastBodyLiveClipId != null) {
        _lastBodyLiveClipId = null;
        _lastBodyLiveTimeMs = -1;
        TiniBodyFxEngine.clearLive();
      }
      return;
    }
    final outputSeconds = clip.projectOffsetForSource(position);
    if (!clip.videoEffects.any(
      (e) =>
          e.active(outputSeconds) &&
          e.descriptor?.category == TiniBodyFxEngine.category,
    ))
      return;
    final sourceTime = clip.sourceAtProjectOffset(outputSeconds);
    final sourceTimeMs = clip.replacementPath == null
        ? sourceTime.inMilliseconds
        : clip.replacementStartTime.inMilliseconds +
              (sourceTime - clip.startTime).inMilliseconds;
    if (_lastBodyLiveClipId == clip.id &&
        (sourceTimeMs - _lastBodyLiveTimeMs).abs() < 80)
      return;
    _bodyLivePolling = true;
    final request = _bodyPreviewRequest;
    _lastBodyLiveClipId = clip.id;
    _lastBodyLiveTimeMs = sourceTimeMs;
    try {
      String? source =
          clip.replacementPath ??
          _fullReplacementFile?.path ??
          widget.videoFile?.path;
      if (source == null &&
          widget.selectedMedia != null &&
          widget.selectedMedia!.isNotEmpty) {
        final media =
            widget.selectedMedia![_currentIndex.clamp(
              0,
              widget.selectedMedia!.length - 1,
            )];
        source = (await media.file)?.path;
      }
      if (source == null || !mounted || request != _bodyPreviewRequest) return;
      await TiniBodyFxEngine.captureLive(
        clip: clip,
        source: source,
        sourceTimeMs: sourceTimeMs,
        outputSeconds: outputSeconds,
      );
    } catch (error) {
      // Do not freeze playback or swallow the error during development.
      debugPrint('[Tini Body Live] $error');
      _lastBodyLiveTimeMs = -1; // retry even when paused on the same frame
    } finally {
      _bodyLivePolling = false;
    }
  }

  void _scheduleTrackedBodyPreview(CropClip clip) {
    _bodyPreviewClipIds.add(clip.id);
    ++_bodyPreviewRequest;
    _lastBodyLiveTimeMs = -1;
    _lastBodyLiveClipId = null;
    TiniBodyFxEngine.clearLive();
    if (!_cropClips.any(
      (c) => TiniBodyFxEngine.hasBodyEffects(c.videoEffects),
    )) {
      _bodyLiveTimer?.cancel();
      _bodyLiveTimer = null;
      return;
    }
    _bodyLiveTimer ??= tini_async.Timer.periodic(
      const Duration(milliseconds: 150),
      (_) {
        _pollLiveBodyFrame();
      },
    );
    _pollLiveBodyFrame();
  }

  // Track a *committed* editor state independently from its cache result.
  // Preview-panel slider values are temporary and never become an ancestor.
  void _syncEditorRevision() {
    if (_magicPanelExpanded || _animationPanelExpanded ||
        _videoEffectsPanelExpanded || _speedPanelExpanded ||
        _retouchBusy || _backgroundBusy || _overlayBusy ||
        _cropAllDeleted || _cropClips.isEmpty ||
        _activeVideoControllers.isEmpty) return;
    final controller = _activeVideoControllers.first;
    if (!controller.value.isInitialized) return;
    final size = CropOverlayOutputSize.fromSource(
      controller.value.size.width, controller.value.size.height,
    );
    final state = VideoProcessor.editCacheSignature(
      controller.dataSource, _cropClips, size.width, size.height,
    );
    if (state == _editorRevisionState) return;
    _parentEditorRevision = _editorRevision;
    _editorRevision = '${_editSessionId}_${++_editRevisionCounter}';
    _editorRevisionState = state;
  }

  void _scheduleEditWarmup() {
    _syncEditorRevision();
    if (_cropAllDeleted ||
        _retouchBusy ||
        _overlayBusy ||
        _backgroundBusy ||
        _magicPanelExpanded ||
        _animationPanelExpanded ||
        _videoEffectsPanelExpanded ||
        _speedPanelExpanded ||
        _cropClips.isEmpty ||
        _activeVideoControllers.isEmpty ||
        !_activeVideoControllers.first.value.isInitialized ||
        _activeVideoControllers.first.value.isPlaying) {
      _editWarmup.update(null, null);
      return;
    }
    final source = _activeVideoControllers.first;
    // A paused, settled edit produces the SAME immutable hardware checkpoint
    // requested by publishing. Live playback keeps priority over prefetch.
    // Keep running after leaving the crop sheet, while the project is saved.
    final clips = List<CropClip>.unmodifiable(_cropClips);
    final edited =
        clips.length > 1 ||
        _cropOverlays.isNotEmpty ||
        clips.any(
          (c) =>
              c.startFraction > 0 ||
              c.endFraction < 1 ||
              c.replacementPath != null ||
              !c.speed.isDefault ||
              c.isMuted ||
              c.cutout != null ||
              c.backgroundPath != null ||
              c.magicEffectId != null ||
              c.animations.hasEffects ||
              c.videoEffects.isNotEmpty ||
              c.colorFilter.enabled ||
              c.retouch.enabled ||
              c.rotationQuarterTurns % 4 != 0,
        );
    if (!edited) {
      _editWarmup.update(null, null);
      return;
    }
    final size = CropOverlayOutputSize.fromSource(
      source.value.size.width,
      source.value.size.height,
    );
    final path = source.dataSource;
    final revision = _editorRevision;
    final parentRevision = _parentEditorRevision;
    final signature = TiniEditCache.digest({
      'editorRevision': revision,
      'project': VideoProcessor.editCacheSignature(
        path,
        clips,
        size.width,
        size.height,
      ),
      // Overlay-only changes cannot invalidate the cached base-video pixels.
      // Their real composition still happens exclusively after Publish.
    });
    _editWarmup.update(signature, (stopped) async {
      String? base;
      try {
        // Cache only intermediate editor results. The final picture-layer
        // composition (overlays + music + upload) starts on Publish.
        base = await VideoProcessor.renderReplacementClips(
          originalPath: path,
          clips: clips,
          width: size.width,
          height: size.height,
          cancelled: stopped,
          cacheWarmup: true,
          editorRevision: revision,
          parentEditorRevision: parentRevision,
        );
        if (stopped()) return;
        // The overlay composite is final-output work, not an edit checkpoint.
        // It remains exclusively in prepareVideo(), invoked by Publish.
      } finally {
        for (final file in {base}.whereType<String>()) {
          try {
            await File(file).delete();
          } catch (_) {}
        }
      }
    });
  }

  String? _retouchSignature() {
    if (_cropAllDeleted ||
        _activeVideoControllers.isEmpty ||
        !_activeVideoControllers.first.value.isInitialized ||
        !_cropClips.any((c) => c.retouch.enabled)) {
      return null;
    }
    final source = _activeVideoControllers.first;
    final size = CropOverlayOutputSize.fromSource(
      source.value.size.width,
      source.value.size.height,
    );
    return TiniEditCache.digest({
      'settings': VideoProcessor.editCacheSignature(
        source.dataSource, _cropClips, size.width, size.height,
      ),
      'revision': _editorRevision,
    });
  }

  void _scheduleRetouchPreview() {
    _syncEditorRevision();
    // Live preview of an unconfirmed panel stays in the existing renderer;
    // never bake a transient slider value into a committed checkpoint.
    if (_retouchBusy || _magicPanelExpanded || _animationPanelExpanded ||
        _videoEffectsPanelExpanded || _speedPanelExpanded) return;
    final key = _retouchSignature();
    if (key == _retouchRequestedKey) return;
    _retouchRequestedKey = key;
    _retouchDebounce?.cancel();
    if (key == null) {
      _retouchPlayer?.pause();
      return;
    }
    if (key == _retouchKey && _retouchPlayer?.value.isInitialized == true)
      return;
    _retouchDebounce = tini_async.Timer(const Duration(milliseconds: 650), () {
      if (mounted) _refreshRetouchPreview(key);
    });
  }

  // Open the face editor from an owned local source immediately. Earlier
  // Magic/colour/video effects can require a full render, but that render must
  // never block the retouch tools or the editor navigation.
  Future<String> _retouchOpeningSource(VideoPlayerController source) async {
    final uri = Uri.tryParse(source.dataSource);
    final path = uri?.scheme == 'file'
        ? uri!.toFilePath()
        : source.dataSource;
    if (!await File(path).exists()) {
      throw FileSystemException('Retouch source is unavailable', path);
    }
    final cache = await getTemporaryDirectory();
    await cache.create(recursive: true);
    final suffix = path.split('/').last.contains('.')
        ? path.split('.').last
        : 'mp4';
    return (await File(path).copy(
      '${cache.path}/tini_gpu_base_'
      '${DateTime.now().microsecondsSinceEpoch}.$suffix',
    )).path;
  }

  bool _retouchBaselineIsPlain(
    VideoPlayerController source,
    List<CropClip> clips,
  ) => clips.length == 1 &&
      clips.first.startTime == Duration.zero &&
      (clips.first.endTime - source.value.duration).inMilliseconds.abs() <= 40 &&
      !clips.first.isMuted &&
      clips.first.speed.isDefault &&
      !clips.first.colorFilter.enabled &&
      clips.first.cutout == null &&
      clips.first.backgroundPath == null &&
      clips.first.magicEffectId == null &&
      !clips.first.animations.hasEffects &&
      clips.first.videoEffects.isEmpty &&
      clips.first.replacementPath == null &&
      clips.first.rotationQuarterTurns % 4 == 0;

  // Keep the exact existing composition for previously applied effects. It
  // now prepares in the background while the retouch editor stays usable.
  Future<String> _retouchBaseline(
    VideoPlayerController source,
    List<CropClip> clips,
    CropOverlayOutputSize size, {
    bool Function()? cancelled,
  }) async {
    if (Platform.isAndroid && _retouchBaselineIsPlain(source, clips)) {
      return _retouchOpeningSource(source);
    }
    return VideoProcessor.renderReplacementClips(
      originalPath: source.dataSource,
      clips: clips
          .map((c) => c.copyWith(retouch: const CropRetouchSettings()))
          .toList(),
      width: size.width,
      height: size.height,
      cancelled: cancelled,
    );
  }

  Future<void> _refreshRetouchPreview(String key) async {
    if (!mounted || _retouchRendering || key != _retouchSignature()) return;
    _retouchRendering = true;
    final generation = ++_retouchGeneration;
    final controller = _activeVideoControllers.first;
    final size = CropOverlayOutputSize.fromSource(
      controller.value.size.width,
      controller.value.size.height,
    );
    final clips = List<CropClip>.unmodifiable(_cropClips);
    final revision = _editorRevision;
    final parentRevision = _parentEditorRevision;
    String? rendered;
    VideoPlayerController? player;
    try {
      // The committed preview reads the very same content-addressed output
      // that publishing will use. All chronological operators and retouch
      // are already baked into this video: do NOT reapply live GPU retouch.
      // The separate retouch-slider editor continues to use _retouchBaseline.
      rendered = await VideoProcessor.renderReplacementClips(
        originalPath: controller.dataSource,
        clips: clips,
        width: size.width,
        height: size.height,
        editorRevision: revision,
        parentEditorRevision: parentRevision,
        cancelled: () =>
            !mounted ||
            generation != _retouchGeneration ||
            key != _retouchSignature(),
      );
      if (!mounted ||
          generation != _retouchGeneration ||
          key != _retouchSignature())
        return;
      player = VideoPlayerController.file(
        File(rendered),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await player.initialize();
      await player.setVolume(0);
      if (!mounted ||
          generation != _retouchGeneration ||
          key != _retouchSignature())
        return;
      final previous = _retouchPlayer, oldPath = _retouchPath;
      setState(() {
        _retouchPlayer = player;
        _retouchPath = rendered;
        _retouchKey = key;
      });
      player = null;
      rendered = null;
      await previous?.dispose();
      if (oldPath != null) {
        try {
          await File(oldPath).delete();
        } catch (_) {}
      }
      _syncRetouchPreview(controller);
    } catch (error) {
      if (mounted && key == _retouchSignature()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تعذر تحديث المعاينة؛ إعدادات التنميق محفوظة. $error',
            ),
          ),
        );
      }
    } finally {
      await player?.dispose();
      if (rendered != null) {
        try {
          await File(rendered).delete();
        } catch (_) {}
      }
      _retouchRendering = false;
      if (mounted) {
        if (key != _retouchSignature()) _retouchRequestedKey = null;
        setState(() {});
        _scheduleRetouchPreview();
      }
    }
  }

  void _syncRetouchPreview(VideoPlayerController base) {
    final player = _retouchPlayer;
    if (player == null || !player.value.isInitialized) return;
    if (_retouchKey != _retouchSignature()) {
      player.pause();
      return;
    }
    final position = base.value.position;
    final project = Duration(milliseconds: _overlayProjectMs(position));
    if ((player.value.position - project).inMilliseconds.abs() >
        (base.value.isPlaying ? 180 : 25)) {
      player.seekTo(project);
    }
    final active = _cropClips
        .where((c) => position >= c.startTime && position < c.endTime)
        .firstOrNull;
    final rate = active == null
        ? 1.0
        : (base.value.playbackSpeed / _speedForClip(active, position)).clamp(
            .1,
            10.0,
          );
    if ((player.value.playbackSpeed - rate).abs() > .04)
      player.setPlaybackSpeed(rate);
    if (base.value.isPlaying && !player.value.isPlaying) player.play();
    if (!base.value.isPlaying && player.value.isPlaying) player.pause();
  }

  Future<void> _editCropRetouch() async {
    if (_retouchBusy || _cropAllDeleted || _activeVideoControllers.isEmpty)
      return;
    final controller = _activeVideoControllers.first;
    if (!controller.value.isInitialized) return;
    final duration = controller.value.duration.inMilliseconds;
    final size = CropOverlayOutputSize.fromSource(
      controller.value.size.width,
      controller.value.size.height,
    );
    final clips = _cropClips.isNotEmpty
        ? List<CropClip>.of(_cropClips)
        : [
            CropClip(
              id: 'retouch_base',
              startFraction: _currentTrimRange.start,
              endFraction: _currentTrimRange.end,
              startTime: Duration(
                milliseconds: (duration * _currentTrimRange.start).round(),
              ),
              endTime: Duration(
                milliseconds: (duration * _currentTrimRange.end).round(),
              ),
            ),
          ];
    await controller.pause();
    await _audioPlayer.pause();
    if (!mounted) return;
    setState(() => _retouchBusy = true);
    _refreshCropSheet?.call(() {});
    // A background checkpoint must not compete with the user's foreground
    // retouch interaction. Also invalidate any stale full retouch preview.
    _editWarmup.update(null, null);
    _retouchDebounce?.cancel();
    ++_retouchGeneration;
    _retouchRequestedKey = null;
    String? preview;
    Future<String>? preparedBase;
    var preparationCancelled = false;
    try {
      // A fast owned copy is sufficient to initialize the GPU face controls.
      // No effect is discarded: the complete effect baseline is composed in
      // parallel, then handed to the editor without resetting slider values.
      preview = await _retouchOpeningSource(controller);
      if (!mounted) return;
      if (!_retouchBaselineIsPlain(controller, clips)) {
        preparedBase = _retouchBaseline(
          controller, clips, size,
          cancelled: () => preparationCancelled || !mounted,
        );
      }
      var offset = 0;
      final segments = <CropRetouchSegment>[];
      for (final clip in clips) {
        final end = offset + clip.playbackDuration.inMilliseconds;
        segments.add(
          CropRetouchSegment(
            id: clip.id,
            startMs: offset,
            endMs: end,
            settings: clip.retouch,
          ),
        );
        offset = end;
      }
      final selected = (_selectedCropIndex ?? 0).clamp(0, clips.length - 1);
      final result = await Navigator.of(context)
          .push<List<CropRetouchSettings>>(
            MaterialPageRoute(
              builder: (_) => CropRetouchEditor(
                basePath: preview!,
                preparedBase: preparedBase,
                segments: segments,
                selectedIndex: selected,
                overlays: List.of(_cropOverlays),
              ),
            ),
          );
      if (!mounted || result == null || result.length != clips.length) return;
      if (List.generate(
        clips.length,
        (i) => clips[i].retouch == result[i],
      ).every((same) => same))
        return;
      _saveCropStateForUndo();
      setState(() {
        _cropClips = [
          for (var i = 0; i < clips.length; i++)
            clips[i].copyWith(retouch: result[i]),
        ];
        _selectedCropIndex = selected;
      });
      _refreshCropSheet?.call(() {});
      _scheduleRetouchPreview();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر فتح التنميق: $error')));
      }
    } finally {
      preparationCancelled = true;
      // A cancelled render may still finish its FFmpeg cleanup asynchronously.
      // Reclaim its owned result when it resolves, never the gallery source.
      final pendingBase = preparedBase;
      if (pendingBase != null) {
        final sourceUri = Uri.tryParse(controller.dataSource);
        final originalPath = sourceUri?.scheme == 'file'
            ? sourceUri!.toFilePath()
            : controller.dataSource;
        tini_async.unawaited(pendingBase.then((path) async {
          // A renderer is allowed to return its source unchanged. Never
          // delete the gallery input when cleaning an asynchronous lease.
          if (path != preview && path != controller.dataSource &&
              File(path).absolute.path != File(originalPath).absolute.path) {
            try {
              await File(path).delete();
            } on FileSystemException {
              /* The temporary baseline was already cleaned. */
            }
          }
        }).catchError((Object error) {
          debugPrint('[Tini Retouch] Baseline cleanup: $error');
        }));
      }
      if (preview != null) {
        try {
          await File(preview).delete();
        } catch (_) {}
      }
      if (mounted) {
        setState(() => _retouchBusy = false);
        _refreshCropSheet?.call(() {});
        _scheduleRetouchPreview();
      }
    }
  }

  Widget _withCropOverlays(
    Widget picture,
    Duration position,
    VideoPlayerController controller,
  ) {
    // Retouch checkpoints already contain the final structural transform.
    if (!identical(controller, _retouchPlayer)) {
      final clip = CropRotation.clipAt(_cropClips, position);
      picture = CropRotation.preview(picture, clip?.rotationQuarterTurns ?? 0);
    }
    if (_cropOverlays.isEmpty) return picture;
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: picture,
          ),
        ),
        IgnorePointer(
          child: CropOverlayCanvas(
            overlays: _cropOverlays,
            positionMs: _overlayProjectMs(position),
            playing:
                _activeVideoControllers.firstOrNull?.value.isPlaying ?? false,
          ),
        ),
      ],
    );
  }

  int _overlayProjectMs(Duration source) {
    if (_cropClips.isEmpty) {
      final duration =
          _activeVideoControllers.firstOrNull?.value.duration.inMilliseconds ??
          0;
      return (source.inMilliseconds -
              (duration * _currentTrimRange.start).round())
          .clamp(
            0,
            (duration * (_currentTrimRange.end - _currentTrimRange.start))
                .round(),
          );
    }
    var elapsed = 0;
    for (final clip in _cropClips) {
      if (source >= clip.startTime && source < clip.endTime) {
        return elapsed + (clip.projectOffsetForSource(source) * 1000).round();
      }
      elapsed += clip.playbackDuration.inMilliseconds;
    }
    return source < _cropClips.first.startTime ? 0 : elapsed;
  }

  Future<void> _editCropOverlays() async {
    if (_overlayBusy || _cropAllDeleted || _activeVideoControllers.isEmpty)
      return;
    final controller = _activeVideoControllers.first;
    if (!controller.value.isInitialized) return;
    // file() controllers expose a file URI; the overlay editor needs a disk path.
    final sourceUri = Uri.tryParse(controller.dataSource);
    final source = sourceUri?.scheme == 'file'
        ? sourceUri!.toFilePath()
        : controller.dataSource;
    final duration = controller.value.duration.inMilliseconds;
    final sequence = (_cropClips.isNotEmpty
        ? List<CropClip>.of(_cropClips)
        : [
            CropClip(
              id: 'overlay_preview_base',
              startTime: Duration(
                milliseconds: (duration * _currentTrimRange.start).round(),
              ),
              endTime: Duration(
                milliseconds: (duration * _currentTrimRange.end).round(),
              ),
              startFraction: _currentTrimRange.start,
              endFraction: _currentTrimRange.end,
            ),
          ]).where((clip) => clip.playbackDuration.inMilliseconds > 0).toList();
    if (sequence.isEmpty) return;
    await controller.pause();
    await _audioPlayer.pause();
    await _retouchPlayer?.pause();
    if (!mounted) return;
    setState(() => _overlayBusy = true);
    _editWarmup.update(null, null);
    _refreshCropSheet?.call(() {});
    try {
      // An immutable project snapshot opens immediately. No intermediate video
      // export is needed for the previous cuts, speed, effects or retouch.
      // The separate player maps project time back to each source clip.
      final backgroundClip = sequence.where(
        (clip) => clip.id == _backgroundPreviewClipId &&
            _backgroundKey(clip) == _backgroundPreviewKey,
      ).firstOrNull;
      final result = await Navigator.of(context).push<List<CropOverlay>>(
        MaterialPageRoute(
          builder: (_) => CropOverlayEditor(
            basePath: source,
            projectClips: List<CropClip>.unmodifiable(sequence),
            projectSize: controller.value.size,
            filterClips: List<FilterClip>.unmodifiable(_filterClips),
            backgroundPreviewPath:
                backgroundClip == null ? null : _backgroundPreviewPath,
            backgroundPreviewClipId: backgroundClip?.id,
            initial: List<CropOverlay>.of(_cropOverlays),
          ),
        ),
      );
      if (!mounted || result == null || sameCropOverlays(_cropOverlays, result))
        return;
      _saveCropStateForUndo();
      setState(() => _cropOverlays = List<CropOverlay>.unmodifiable(result));
      _refreshCropSheet?.call(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر فتح محرر التراكب: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _overlayBusy = false);
        _refreshCropSheet?.call(() {});
      }
    }
  }

  void _previewColorFilter(CropFilterSelection value) {
    final target = _backgroundTargetClip();
    if (target == null) return;
    _colorFilterBeforeState ??= _captureCropState();
    setState(() {
      if (_cropClips.isEmpty) {
        _cropClips = [target];
        _selectedCropIndex = 0;
      }
      final index = (_selectedCropIndex ?? 0).clamp(0, _cropClips.length - 1);
      _selectedCropIndex = index;
      _cropClips[index] = _cropClips[index].copyWith(colorFilter: value);
    });
    _refreshCropSheet?.call(() {});
  }

  void _finishColorFilter(bool save, CropFilterSelection value) {
    final previous = _colorFilterBeforeState;
    _colorFilterBeforeState = null;
    if (previous == null) return;
    final index = previous.selectedIndex ?? 0;
    final original = previous.clips.isEmpty
        ? const CropFilterSelection()
        : previous.clips[index.clamp(0, previous.clips.length - 1)].colorFilter;
    if (!save || original == value || (!original.enabled && !value.enabled)) {
      setState(() => _restoreCropState(previous));
    } else {
      _cropUndoStack.add(previous);
      _cropRedoStack.clear();
    }
    _refreshCropSheet?.call(() {});
  }

  void _previewTiniEffects(List<TiniAppliedEffect> effects) {
    if (_cropAllDeleted || _activeVideoControllers.isEmpty) return;
    final controller = _activeVideoControllers.first;
    if (!controller.value.isInitialized ||
        controller.value.duration.inMilliseconds <= 0)
      return;
    _videoEffectsBeforeState ??= _captureCropState();
    final previousEffects = _cropClips.isNotEmpty
        ? _cropClips[(_selectedCropIndex ?? 0).clamp(0, _cropClips.length - 1)]
              .videoEffects
        : <TiniAppliedEffect>[];
    final newEffect =
        effects.isNotEmpty && effects.length > previousEffects.length;
    setState(() {
      if (_cropClips.isEmpty && effects.isNotEmpty) {
        final total = controller.value.duration.inMilliseconds;
        _cropClips = [
          CropClip(
            id: 'effects_base_clip',
            startTime: Duration(
              milliseconds: (total * _currentTrimRange.start).round(),
            ),
            endTime: Duration(
              milliseconds: (total * _currentTrimRange.end).round(),
            ),
            startFraction: _currentTrimRange.start,
            endFraction: _currentTrimRange.end,
          ),
        ];
        _selectedCropIndex = 0;
      }
      if (_cropClips.isNotEmpty) {
        final index = (_selectedCropIndex ?? 0)
            .clamp(0, _cropClips.length - 1)
            .toInt();
        _selectedCropIndex = index;
        _cropClips[index] = _cropClips[index].withVideoEffects(effects);
      }
    });
    _refreshCropSheet?.call(() {});
    if (_cropClips.isNotEmpty) {
      final clip =
          _cropClips[(_selectedCropIndex ?? 0).clamp(0, _cropClips.length - 1)];
      _scheduleTrackedBodyPreview(clip);
    }
    if (newEffect && _cropClips.isNotEmpty) {
      final selected =
          _cropClips[(_selectedCropIndex ?? 0).clamp(0, _cropClips.length - 1)];
      final sourcePosition = selected.sourceAtProjectOffset(
        effects.last.startSeconds,
      );
      controller.seekTo(sourcePosition).then((_) {
        if (mounted && _videoEffectsPanelExpanded) controller.play();
      });
    }
  }

  void _finishTiniEffects({
    required bool save,
    List<TiniAppliedEffect>? updated,
  }) {
    final previous = _videoEffectsBeforeState;
    _videoEffectsBeforeState = null;
    if (previous == null) return;
    final oldEffects =
        previous.selectedIndex != null &&
            previous.selectedIndex! >= 0 &&
            previous.selectedIndex! < previous.clips.length
        ? previous.clips[previous.selectedIndex!].videoEffects
        : <TiniAppliedEffect>[];
    if (!save || updated == null || sameTiniEffects(oldEffects, updated)) {
      setState(() => _restoreCropState(previous));
    } else {
      _cropUndoStack.add(previous);
      _cropRedoStack.clear();
    }
    // Cancellation/undo can restore a different body-effect selection.
    // Rebuild only the affected preview rather than showing cached overlays
    // associated with the abandoned slider state.
    if (_cropClips.isNotEmpty) {
      final index = (_selectedCropIndex ?? 0)
          .clamp(0, _cropClips.length - 1)
          .toInt();
      _scheduleTrackedBodyPreview(_cropClips[index]);
    }
  }

  void _previewClipAnimations(CropAnimationSettings value) {
    if (_cropAllDeleted || _activeVideoControllers.isEmpty) return;
    final controller = _activeVideoControllers.first;
    if (!controller.value.isInitialized ||
        controller.value.duration.inMilliseconds <= 0)
      return;
    _animationEditBeforeState ??= _captureCropState();
    bool hasChangedEffect = false;
    Duration startAt = Duration.zero;
    setState(() {
      if (_cropClips.isEmpty && value.hasEffects) {
        final total = controller.value.duration.inMilliseconds;
        _cropClips = [
          CropClip(
            id: 'animation_base_clip',
            startTime: Duration(
              milliseconds: (total * _currentTrimRange.start).round(),
            ),
            endTime: Duration(
              milliseconds: (total * _currentTrimRange.end).round(),
            ),
            startFraction: _currentTrimRange.start,
            endFraction: _currentTrimRange.end,
          ),
        ];
        _selectedCropIndex = 0;
      }
      if (_cropClips.isNotEmpty) {
        final index = (_selectedCropIndex ?? 0)
            .clamp(0, _cropClips.length - 1)
            .toInt();
        final old = _cropClips[index].animations;
        hasChangedEffect =
            old.start != value.start ||
            old.end != value.end ||
            old.group != value.group;
        _selectedCropIndex = index;
        final edited = _cropClips[index].withAnimations(value);
        _cropClips[index] = edited;
        // When choosing an exit animation, preview the actual exit instead
        // of waiting for the entire clip to finish playing.
        final exitWasChanged = old.end != value.end;
        final startSeconds = exitWasChanged && value.end != null
            ? (edited.playbackDuration.inMicroseconds / 1000000.0 -
                      value.endSeconds)
                  .clamp(0.0, double.infinity)
                  .toDouble()
            : 0.0;
        startAt = edited.sourceAtProjectOffset(startSeconds);
      }
    });
    if (hasChangedEffect) {
      controller.seekTo(startAt).then((_) {
        if (mounted) controller.play();
      });
    }
    _refreshCropSheet?.call(() {});
  }

  void _resizeTimelineAnimation(
    String clipId,
    CropAnimationTab tab,
    double seconds,
    bool finished,
  ) {
    final index = _cropClips.indexWhere((clip) => clip.id == clipId);
    if (index < 0) return;
    if (!finished) {
      // A continuous resize gesture is a single Undo action, not one per frame.
      if (!_animationPanelExpanded) {
        _animationTimelineBeforeDrag ??= _captureCropState();
      } else {
        _animationEditBeforeState ??= _captureCropState();
      }
      final clip = _cropClips[index];
      final maxSeconds = clip.playbackDuration.inMicroseconds / 1000000.0;
      if (maxSeconds <= 0) return;
      final lower = tab == CropAnimationTab.group ? .2 : .1;
      final duration = seconds
          .clamp(lower, maxSeconds > lower ? maxSeconds : lower)
          .toDouble();
      final edited = clip.animations.withSeconds(tab, duration);
      if (edited != clip.animations) {
        setState(() => _cropClips[index] = clip.withAnimations(edited));
        _refreshCropSheet?.call(() {});
      }
    } else {
      final previous = _animationTimelineBeforeDrag;
      _animationTimelineBeforeDrag = null;
      if (previous != null) {
        final old = previous.clips
            .firstWhere(
              (clip) => clip.id == clipId,
              orElse: () => _cropClips[index],
            )
            .animations;
        if (old != _cropClips[index].animations) {
          _cropUndoStack.add(previous);
          _cropRedoStack.clear();
        }
      }
    }
  }

  void _finishClipAnimations({
    required bool save,
    CropAnimationSettings? updated,
  }) {
    final previous = _animationEditBeforeState;
    _animationEditBeforeState = null;
    if (previous == null) return;
    final oldValue =
        previous.selectedIndex != null &&
            previous.selectedIndex! < previous.clips.length
        ? previous.clips[previous.selectedIndex!].animations
        : const CropAnimationSettings();
    if (!save || oldValue == updated) {
      setState(() => _restoreCropState(previous));
    } else {
      _cropUndoStack.add(previous);
      _cropRedoStack.clear();
    }
  }

  Future<void> _prepareReplacementPlayer(String path) async {
    if (_replacementPlayers.containsKey(path)) return;
    final player = VideoPlayerController.file(
      File(path),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    try {
      await player.initialize();
      await player.setLooping(false);
      _replacementPlayers[path] = player;
    } catch (_) {
      await player.dispose();
      rethrow;
    }
  }

  Future<void> _loadReplacementThumbnails(
    String path,
    Duration sourceDuration,
  ) async {
    if (_replacementThumbnails.containsKey(path)) return;
    try {
      final count = (sourceDuration.inMilliseconds / 1000).ceil().clamp(8, 60);
      final frames = await platform.invokeMethod<List<dynamic>>('getFrames', {
        'path': path,
        'count': count,
        'thumbHeight': 100,
      });
      if (mounted && frames != null) {
        setState(
          () => _replacementThumbnails[path] = frames
              .whereType<Uint8List>()
              .toList(),
        );
      }
    } catch (error) {
      debugPrint('Tini replace thumbnails unavailable: $error');
    }
  }

  Future<void> _replaceSelectedCropClip() async {
    if (_replacingClip || _activeVideoControllers.isEmpty) return;
    final sourceDuration = _activeVideoControllers.first.value.duration;
    final selected =
        _selectedCropIndex != null &&
            _selectedCropIndex! >= 0 &&
            _selectedCropIndex! < _cropClips.length
        ? _cropClips[_selectedCropIndex!]
        : null;
    final full =
        selected == null &&
        _currentTrimRange.start <= 0.00001 &&
        _currentTrimRange.end >= 0.99999;
    final targetDuration =
        selected?.duration ??
        Duration(
          milliseconds:
              (sourceDuration.inMilliseconds *
                      (_currentTrimRange.end - _currentTrimRange.start))
                  .round(),
        );
    if (targetDuration.inMilliseconds <= 0) return;
    setState(() => _replacingClip = true);
    try {
      _activeVideoControllers.first.pause();
      _audioPlayer.pause();
      final choice = await Navigator.push<CropReplacementSelection>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              CropReplacePicker(targetDuration: full ? null : targetDuration),
        ),
      );
      if (!mounted || choice == null) return;
      if (full) {
        // A full replacement becomes the new source for this preview page.
        _fullReplacementFile = choice.file;
        _fullReplacementIndex = _currentIndex;
        _cropClips = [];
        _cropAllDeleted = false;
        _selectedCropIndex = null;
        _currentTrimRange = const RangeValues(0, 1);
        _cropUndoStack.clear();
        _cropRedoStack.clear();
        _replacementThumbnails.clear();
        _totalDurationNotifier.value = choice.duration;
        _videoPositionNotifier.value = Duration.zero;
        _videoThumbnails = [];
        setState(() {});
        await _generateVideoThumbnails();
      } else {
        await _prepareReplacementPlayer(choice.file.path);
        if (!mounted) return;
        _saveCropStateForUndo();
        final List<CropClip> sourceClips = _cropClips.isNotEmpty
            ? List.of(_cropClips)
            : [
                CropClip(
                  id: 'base_clip',
                  startFraction: _currentTrimRange.start,
                  endFraction: _currentTrimRange.end,
                  startTime: Duration(
                    milliseconds:
                        (sourceDuration.inMilliseconds *
                                _currentTrimRange.start)
                            .round(),
                  ),
                  endTime: Duration(
                    milliseconds:
                        (sourceDuration.inMilliseconds * _currentTrimRange.end)
                            .round(),
                  ),
                ),
              ];
        final index = selected == null ? 0 : _selectedCropIndex!;
        // Cutout masks belong to the old source and must never be applied
        // to the replacement video's frames. Background selection survives.
        sourceClips[index] = sourceClips[index].clearCutout().copyWith(
          replacementPath: choice.file.path,
          replacementStartTime: choice.start,
          replacementSourceDuration: choice.sourceDuration,
        );
        setState(() {
          _cropClips = sourceClips;
          _selectedCropIndex = index;
          _isFrameSelectedNotifier.value = true;
          _currentTrimRange = RangeValues(
            sourceClips[index].startFraction,
            sourceClips[index].endFraction,
          );
          _totalDurationNotifier.value = Duration(
            milliseconds: _cropClips.fold<int>(
              0,
              (sum, clip) => sum + clip.playbackDuration.inMilliseconds,
            ),
          );
        });
        _activeVideoControllers.first.seekTo(sourceClips[index].startTime);
        _videoPositionNotifier.value = sourceClips[index].startTime;
        await _loadReplacementThumbnails(
          choice.file.path,
          choice.sourceDuration,
        );
      }
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر استبدال الفيديو: $error')));
    } finally {
      if (mounted) {
        setState(() => _replacingClip = false);
        _refreshCropSheet?.call(() {});
      }
    }
  }

  Future<void> _generateVideoThumbnails() async {
    String? videoPath = _fullReplacementFile?.path ?? widget.videoFile?.path;
    int videoDurationSeconds = 0;
    if (_fullReplacementFile != null) {
      final replacementController = VideoPlayerController.file(
        _fullReplacementFile!,
      );
      try {
        await replacementController.initialize();
        videoDurationSeconds = replacementController.value.duration.inSeconds;
      } finally {
        await replacementController.dispose();
      }
    }

    // 1. اذا فيديو من المعرض
    if (videoPath == null &&
        widget.selectedMedia != null &&
        widget.selectedMedia!.isNotEmpty) {
      final asset = widget.selectedMedia!.firstWhere(
        (e) => e.type == AssetType.video,
        orElse: () => widget.selectedMedia!.first,
      );
      if (asset.type != AssetType.video) return;
      final file = await asset.file;
      videoPath = file?.path;
      videoDurationSeconds = asset.duration; // المدة من AssetEntity
    }
    // 2. اذا فيديو ديو او مباشر
    else if (widget.duetVideoDuration != null) {
      videoDurationSeconds = widget.duetVideoDuration!.inSeconds;
    }
    // 3. اذا في كونترولر شغال جيب المدة منه
    else if (_activeVideoControllers.isNotEmpty) {
      videoDurationSeconds =
          _activeVideoControllers.first.value.duration.inSeconds;
    }

    if (videoPath == null || videoDurationSeconds == 0) return;

    try {
      // احسب العدد: 1.06 صورة لكل ثانية
      int count = (videoDurationSeconds * 1.06).round();

      // اقل شي 8، اكثر شي 60 عشان يجيب 17 واكتر
      count = count.clamp(1, 60);

      print(
        'TitiStar: generating $count thumbnails for ${videoDurationSeconds}s',
      );

      final List<dynamic> result = await platform.invokeMethod('getFrames', {
        'path': videoPath,
        'count': count,
        'thumbHeight': 100,
      });

      if (mounted) {
        setState(() {
          _videoThumbnails = result.map((e) => e as Uint8List).toList();
        });
      }
    } catch (e) {
      print('Native thumbnail error: $e');
    }
  }

  // --- بداية دوال الستيكرات ---
  void _addStickerLayer(StickerLayer sticker) {
    setState(() {
      // الغي تحديد كل الستيكرات القديمة
      for (var s in _stickerLayers) {
        s.isSelected = false;
      }
      // ضيف الستيكر الجديد بالنص ومحدد
      _stickerLayers.add(sticker.copyWith(x: 0.5, y: 0.5, isSelected: true));
    });
  }

  void _updateStickerLayer(StickerLayer updatedSticker) {
    final index = _stickerLayers.indexWhere((s) => s.id == updatedSticker.id);
    if (index != -1) {
      setState(() {
        _stickerLayers[index] = updatedSticker;
      });
    }
  }

  void _deleteStickerLayer(String id) {
    setState(() {
      _stickerLayers.removeWhere((s) => s.id == id);
    });
  }

  void _selectStickerLayer(String id) {
    setState(() {
      for (var s in _stickerLayers) {
        s.isSelected = s.id == id;
      }
    });
  }

  void _deselectAllStickers() {
    setState(() {
      for (var s in _stickerLayers) {
        s.isSelected = false;
      }
    });
  }
  // --- نهاية دوال الستيكرات ---

  // --- بداية دوال Undo/Redo للفلاتر ---
  void _saveStateForUndo() {
    _undoStack.add(List.from(_filterClips));
    _redoStack.clear(); // لما تعمل شي جديد، امسح الـ Redo
  }

  _CropEditState _captureCropState() {
    _syncEditorRevision();
    return _CropEditState(
      clips: List<CropClip>.from(_cropClips),
      range: _currentTrimRange,
      selectedIndex: _selectedCropIndex,
      frameSelected: _isFrameSelectedNotifier.value,
      allDeleted: _cropAllDeleted,
      audioRange: _cropMusicRange,
      overlays: List<CropOverlay>.unmodifiable(_cropOverlays),
      editorRevision: _editorRevision,
      parentEditorRevision: _parentEditorRevision,
      editorRevisionState: _editorRevisionState,
    );
  }

  void _saveCropStateForUndo() {
    _cropUndoStack.add(_captureCropState());
    _cropRedoStack.clear();
  }

  void _restoreCropState(_CropEditState state) {
    _editorRevision = state.editorRevision;
    _parentEditorRevision = state.parentEditorRevision;
    _editorRevisionState = state.editorRevisionState;
    _cropClips = List<CropClip>.from(state.clips);
    _cropOverlays = List<CropOverlay>.unmodifiable(state.overlays);
    _cropAllDeleted = state.allDeleted;
    _cropMusicRange = state.audioRange;
    final sourceDuration = _activeVideoControllers.isNotEmpty
        ? _activeVideoControllers.first.value.duration
        : Duration.zero;
    final sourceMs = sourceDuration.inMilliseconds;
    if (_cropClips.isEmpty) {
      _selectedCropIndex = null;
      _currentTrimRange = state.range;
      _realVideoStart = Duration(
        milliseconds: (sourceMs * state.range.start).round(),
      );
      _realVideoEnd = Duration(
        milliseconds: (sourceMs * state.range.end).round(),
      );
      _totalDurationNotifier.value = _cropAllDeleted
          ? Duration.zero
          : _realVideoEnd - _realVideoStart;
    } else {
      _selectedCropIndex = (state.selectedIndex ?? 0)
          .clamp(0, _cropClips.length - 1)
          .toInt();
      final selectedClip = _cropClips[_selectedCropIndex!];
      _currentTrimRange = RangeValues(
        selectedClip.startFraction,
        selectedClip.endFraction,
      );
      _totalDurationNotifier.value = Duration(
        milliseconds: _cropClips.fold<int>(
          0,
          (total, clip) => total + clip.playbackDuration.inMilliseconds,
        ),
      );
    }
    _isFrameSelectedNotifier.value = state.frameSelected;
    final seekPosition = _cropAllDeleted
        ? Duration.zero
        : _cropClips.isEmpty
        ? _realVideoStart
        : _cropClips[_selectedCropIndex!].startTime;
    if (_activeVideoControllers.isNotEmpty) {
      _activeVideoControllers.first.pause();
      _activeVideoControllers.first.setLooping(
        !_isCropMode && !_cropAllDeleted,
      );
      if (!_cropAllDeleted) _activeVideoControllers.first.seekTo(seekPosition);
    }
    _audioPlayer.pause();
    _videoPositionNotifier.value = seekPosition;
    // Undo/redo may restore a different cutout or background selection.
    if (_activeVideoControllers.isNotEmpty && _cropClips.isNotEmpty) {
      final clip =
          _cropClips[(_selectedCropIndex ?? 0).clamp(0, _cropClips.length - 1)];
      if (clip.cutout != null || clip.backgroundPath != null) {
        final source = _activeVideoControllers.first.dataSource;
        Future.microtask(() => _refreshBackgroundPreview(clip, source));
      } else {
        _backgroundPreviewPlayer?.pause();
        _activeVideoControllers.first.setVolume(videoVolume);
      }
    }
  }

  // Ripple the music selection through a removed interval in project time.
  // This preserves absolute timing outside the deleted interval instead of
  // reusing stale percentages against a shorter total duration.
  RangeValues _musicRangeAfterDelete(
    int oldTotalMs,
    int removedStartMs,
    int removedDurationMs,
  ) {
    if (oldTotalMs <= 0) return const RangeValues(0, 1);
    final newTotalMs = oldTotalMs - removedDurationMs;
    if (newTotalMs <= 0) return const RangeValues(0, 1);
    final deletedEnd = removedStartMs + removedDurationMs;
    int ripple(int milliseconds) {
      if (milliseconds <= removedStartMs) return milliseconds;
      if (milliseconds >= deletedEnd) return milliseconds - removedDurationMs;
      return removedStartMs;
    }

    final startMs = ripple(
      (_cropMusicRange.start * oldTotalMs).round(),
    ).clamp(0, newTotalMs);
    final endMs = ripple(
      (_cropMusicRange.end * oldTotalMs).round(),
    ).clamp(startMs, newTotalMs);
    return RangeValues(startMs / newTotalMs, endMs / newTotalMs);
  }

  void _rotateSelectedCropClip() {
    if (widget.isDuet) return;
    final target = _backgroundTargetClip();
    if (target == null || target.duration <= Duration.zero) return;
    final controller = _activeVideoControllers.first;
    if (!controller.value.isInitialized) return;
    _saveCropStateForUndo();
    setState(() {
      final rotated = target.rotatedCounterclockwise();
      if (_cropClips.isEmpty) {
        _cropClips = [rotated];
        _selectedCropIndex = 0;
      } else {
        final index = _cropClips.indexWhere((c) => c.id == target.id);
        _cropClips[index] = rotated;
      }
    });
    controller.pause();
    _audioPlayer.pause();
    // Rotating the displayed clip keeps the playhead at the current frame.
    final position = _videoPositionNotifier.value;
    final displayed = CropRotation.clipAt(_cropClips, position);
    if (displayed?.id != target.id) {
      controller.seekTo(target.startTime);
      _videoPositionNotifier.value = target.startTime;
    }
    _scheduleEditWarmup();
    _scheduleRetouchPreview();
  }

  void _handleClipMuteChanged(String clipId, bool isMuted) {
    _saveCropStateForUndo();
    setState(() {
      final index = _cropClips.indexWhere((c) => c.id == clipId);
      if (index != -1) {
        _cropClips[index] = _cropClips[index].copyWith(isMuted: isMuted);
        // اذا المؤشر واقف على نفس التقسيمة طبق الصوت مباشرة
        final currentPos = _videoPositionNotifier.value;
        if (currentPos >= _cropClips[index].startTime &&
            currentPos <= _cropClips[index].endTime) {
          if (_activeVideoControllers.isNotEmpty) {
            _activeVideoControllers.first.setVolume(isMuted ? 0 : videoVolume);
          }
        }
      }
    });
  }

  void _undoFilter() {
    if (_undoStack.isEmpty) return;
    setState(() {
      _redoStack.add(List.from(_filterClips));
      _filterClips = _undoStack.removeLast();
    });
  }

  void _redoFilter() {
    if (_redoStack.isEmpty) return;
    setState(() {
      _undoStack.add(List.from(_filterClips));
      _filterClips = _redoStack.removeLast();
    });
  }

  void _deleteSelectedClip() {
    if (_selectedClipIndex == null) return;
    _saveStateForUndo();
    setState(() {
      _filterClips.removeAt(_selectedClipIndex!);
      _selectedClipIndex = null;
    });
  }
  // --- نهاية دوال Undo/Redo ---

  void _openAudioMixerSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A222C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "التحكم بالأصوات",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 25),

                  // سلايدر الصوت الأصلي - يظهر دائماً إلا لو صورة بدون فيديو
                  if (widget.videoFile != null ||
                      widget.isDuet ||
                      (widget.selectedMedia?.any(
                            (e) => e.type == AssetType.video,
                          ) ??
                          false))
                    _buildVolumeSlider(
                      label: "الصوت الأصلي",
                      icon: Icons.mic,
                      value: videoVolume,
                      onChanged: (val) {
                        _setVideoVolume(val);
                        setModalState(() {});
                      },
                      onMuteToggle: () {
                        final newValue = videoVolume > 0 ? 0.0 : 0.2;
                        _setVideoVolume(newValue);
                        setModalState(() {});
                      },
                    ),

                  const SizedBox(height: 15),

                  // سلايدر الموسيقى - يظهر فقط لو في موسيقى مختارة
                  if (_selectedAudioUrl != null)
                    _buildVolumeSlider(
                      label: "الموسيقى",
                      icon: Icons.music_note,
                      value: musicVolume,
                      onChanged: (val) {
                        _setMusicVolume(val);
                        setModalState(() {});
                      },
                      onMuteToggle: () {
                        final newValue = musicVolume > 0 ? 0.0 : 1.0;
                        _setMusicVolume(newValue);
                        setModalState(() {});
                      },
                    ),

                  const SizedBox(height: 25),

                  // زر إعادة الضبط
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        _setVideoVolume(0.2);
                        _setMusicVolume(1.0);
                        setModalState(() {});
                      },
                      icon: const Icon(Icons.restart_alt, color: Colors.teal),
                      label: const Text(
                        "إعادة الضبط للافتراضي",
                        style: TextStyle(color: Colors.teal),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.teal),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildVolumeSlider({
    required String label,
    required IconData icon,
    required double value,
    required Function(double) onChanged,
    required VoidCallback onMuteToggle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.white70, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
            GestureDetector(
              onTap: onMuteToggle,
              child: Icon(
                value > 0 ? Icons.volume_up : Icons.volume_off,
                color: value > 0 ? Colors.teal : Colors.redAccent,
                size: 22,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.teal,
            inactiveTrackColor: Colors.white24,
            thumbColor: Colors.teal,
            overlayColor: Colors.teal.withValues(alpha: 0.2),
            trackHeight: 3,
          ),
          child: Slider(
            value: value,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            label: "${(value * 100).round()}%",
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
  // --- نهاية دوال Audio Mixer ---

  void _syncPageViewWithScroll() {
    if (_isAutoScrolling && _thumbnailScrollController.hasClients) {
      double maxScroll = _thumbnailScrollController.position.maxScrollExtent;
      if (maxScroll > 0) {
        double relativePosition = _thumbnailScrollController.offset / maxScroll;
        int targetIndex = (relativePosition * (_totalCount - 1)).round();

        if (targetIndex != _currentIndex && targetIndex < _totalCount) {
          _currentIndex = targetIndex;
          _pageController.animateToPage(
            targetIndex,
            duration: const Duration(milliseconds: 1200),
            curve: Curves.easeInOutCubic,
          );
          if (mounted) setState(() {});
        }
      }
    }
  }

  void _startAutoScrollEffect() async {
    if (_thumbnailScrollController.hasClients &&
        _totalCount > 1 &&
        _isAutoScrolling) {
      await Future.delayed(const Duration(milliseconds: 1000));
      for (int i = 1; i <= _totalCount; i++) {
        if (!_isAutoScrolling ||
            !mounted ||
            !_thumbnailScrollController.hasClients)
          break;
        double targetOffset =
            (i / _totalCount) *
            _thumbnailScrollController.position.maxScrollExtent;
        await _thumbnailScrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 1500),
          curve: Curves.easeInOutCubic,
        );
        await Future.delayed(const Duration(milliseconds: 1200));
      }

      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 400));

      for (int i = _totalCount - 1; i >= 0; i--) {
        if (!_isAutoScrolling ||
            !mounted ||
            !_thumbnailScrollController.hasClients)
          break;
        double targetOffset =
            (i / _totalCount) *
            _thumbnailScrollController.position.maxScrollExtent;
        await _thumbnailScrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 1500),
          curve: Curves.easeInOutCubic,
        );
        await Future.delayed(const Duration(milliseconds: 1000));
      }
      if (mounted) setState(() => _isAutoScrolling = false);
    }
  }

  Future<void> _addNewMedia() async {
    if (_isProcessing || widget.videoFile != null || widget.isDuet) return;
    setState(() => _isProcessing = true);

    final List<AssetEntity>? result = await Navigator.push<List<AssetEntity>>(
      context,
      MaterialPageRoute(
        builder: (context) => const MediaPickerScreen(isAddingMore: true),
      ),
    );

    if (mounted) setState(() => _isProcessing = false);

    if (result != null && result.isNotEmpty) {
      setState(() {
        for (var item in result) {
          if (!(widget.selectedMedia?.contains(item) ?? false)) {
            widget.selectedMedia?.add(item);
          }
        }
      });
      _isAutoScrolling = true;
      _startAutoScrollEffect();
    }
  }

  void _removeMedia(int index) {
    if (widget.videoFile != null || widget.isDuet) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      if (_hasGrid && index == (widget.selectedMedia?.length ?? 0)) {
        _gridSnapshot = null;
      } else {
        widget.selectedMedia?.removeAt(index);
      }

      if (_totalCount == 0) {
        Navigator.pop(context);
      } else {
        if (_currentIndex >= _totalCount) {
          _currentIndex = _totalCount - 1;
        }
      }
    });
  }

  @override
  void dispose() {
    _editWarmup.dispose();
    ++_retouchGeneration;
    _retouchDebounce?.cancel();
    final retouchPlayer = _retouchPlayer, retouchPath = _retouchPath;
    Future<void>(() async {
      await retouchPlayer?.dispose();
      if (retouchPath != null) {
        try {
          await File(retouchPath).delete();
        } catch (_) {}
      }
    });
    _thumbnailScrollController.removeListener(_syncPageViewWithScroll);
    _pageController.dispose();
    _thumbnailScrollController.dispose();
    _audioPlayer.dispose();
    audioTitleNotifier.dispose();
    _activeVideoControllers.clear();
    for (final player in _replacementPlayers.values) {
      player.dispose();
    }
    _replacementPlayers.clear();
    _bodyPreviewRequest++;
    _bodyLiveTimer?.cancel();
    TiniBodyFxEngine.clearLive();
    for (final clipId in _bodyPreviewClipIds) {
      TiniBodyFxEngine.replacePreview(clipId, const [], null);
    }
    _backgroundPreviewPlayer?.dispose();
    if (_backgroundPreviewPath != null) {
      File(_backgroundPreviewPath!).delete().catchError((Object _) => File(''));
    }

    _syncController?.dispose();
    _videoPositionNotifier.dispose();
    _totalDurationNotifier.dispose();
    _isFrameSelectedNotifier.dispose();
    _isSeekingCropNotifier.dispose();
    _publishFrameSelected.dispose();
    _publishSeeking.dispose();
    super.dispose();
  }

  // Reserve room for the front camera without shifting the preview far down.
  // The Magic sheet and preview must share the same height calculation.
  double _cropSheetHeight(BuildContext context) {
    final media = MediaQuery.of(context);
    final height = media.size.height;
    // Reference animation panel keeps the video/timeline in view; Magic keeps
    // its existing taller layout and is not affected by this new tool.
    if (_animationPanelExpanded) return height * 0.52;
    if (_videoEffectsPanelExpanded) return height * 0.68;
    if (!_magicPanelExpanded) {
      return height * (_speedPanelExpanded ? 0.70 : 0.50);
    }
    final headerAndPreview = media.padding.top + 8.0 + 120.0;
    final maximum = (height - headerAndPreview - media.padding.bottom)
        .clamp(0.0, height)
        .toDouble();
    final preferred = height * 0.58;
    final minimum = 408.0 + media.padding.bottom;
    return (preferred > minimum ? preferred : minimum)
        .clamp(0.0, maximum)
        .toDouble();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleEditWarmup();
    _scheduleRetouchPreview();
    final media = MediaQuery.of(context);
    final double screenHeight = media.size.height;
    final double topBarHeight = screenHeight * 0.032;
    final double bottomBarHeight = screenHeight * 0.139;
    final double previewTopInset = media.padding.top + 8.0;
    final double cropPreviewHeight =
        (screenHeight - _cropSheetHeight(context) - media.padding.bottom)
            .clamp(0.0, screenHeight)
            .toDouble();

    return Scaffold(
      key: _scaffoldKey, // ← هاد السطر الجديد
      backgroundColor: const Color(0xFF0F1720),
      body: Column(
        children: [
          // 1. الفيديو/الصورة - بياخد نص الشاشة لما الفلاتر مفتوحة
          AnimatedContainer(
            duration: _isCropMode
                ? Duration.zero
                : const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            height: _isCropMode
                ? cropPreviewHeight // Always ends before the crop/Magic sheet begins.
                : _isFilterMode
                ? screenHeight *
                      0.5 // ← للفلاتر 50%
                : screenHeight, // ← للوضع العادي 100%
            child: Stack(
              children: [
                Padding(
                  padding: EdgeInsets.only(top: previewTopInset),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (_isCropMode) {
                        // بوضع القص: بس طفي/شغل البوردر
                        _isFrameSelectedNotifier.value =
                            !_isFrameSelectedNotifier.value;
                      } else {
                        // بالوضع العادي: حدد الفريم
                        _isFrameSelectedNotifier.value = true;
                        setState(() {
                          _deselectAllStickers();
                        });
                      }
                    },
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            color: _isFilterMode || _isCropMode
                                ? const Color(0xFF0F1720)
                                : Colors.transparent,
                            padding: EdgeInsets.zero,
                            child: Container(
                              decoration: BoxDecoration(border: null),
                              child: PageView.builder(
                                controller: _pageController,
                                itemCount: _totalCount,
                                allowImplicitScrolling: false,
                                physics: _isAutoScrolling
                                    ? const NeverScrollableScrollPhysics()
                                    : const BouncingScrollPhysics(),
                                onPageChanged: (index) {
                                  if (!_isAutoScrolling) {
                                    setState(() => _currentIndex = index);
                                  }
                                },
                                itemBuilder: (context, index) {
                                  if (widget.isDuet) {
                                    return DuetPreviewItem(
                                      key: const ValueKey('duet_player'),
                                      userVideoFile: widget.videoFile!,
                                      duetVideoUrl: widget.duetVideoUrl!,
                                      layout: widget.selectedLayout,
                                      topHeight: topBarHeight,
                                      bottomHeight: _isFilterMode || _isCropMode
                                          ? 0
                                          : bottomBarHeight,
                                      duetVideoDuration:
                                          widget.duetVideoDuration,
                                      filterClips: _filterClips,
                                      videoPositionNotifier:
                                          _videoPositionNotifier,
                                      isFrameSelectedNotifier:
                                          _isFrameSelectedNotifier,
                                      isSeekingNotifier: _isSeekingCropNotifier,
                                      onControllersReady: (controllers) {
                                        _activeVideoControllers.clear();
                                        _activeVideoControllers.addAll(
                                          controllers,
                                        );
                                        for (var c in controllers)
                                          c.setVolume(videoVolume);
                                        _updateSyncController();
                                      },
                                      onTap: () {
                                        if (_isCropMode) {
                                          _isFrameSelectedNotifier.value =
                                              !_isFrameSelectedNotifier.value;
                                          return;
                                        }
                                        _togglePlayPause();
                                      },
                                    );
                                  }

                                  if (widget.videoFile != null) {
                                    return VideoPreviewItem(
                                      key: ValueKey(
                                        'video_player_${_fullReplacementFile?.path ?? widget.videoFile!.path}',
                                      ),
                                      directFile:
                                          _fullReplacementFile ??
                                          widget.videoFile,
                                      filterClips: _filterClips,
                                      videoPositionNotifier:
                                          _videoPositionNotifier,
                                      isFrameSelectedNotifier:
                                          _isFrameSelectedNotifier,
                                      isSeekingNotifier: _isSeekingCropNotifier,
                                      cropOverlays: _cropOverlays,
                                      overlayPosition: _overlayProjectMs,
                                      magicClips: _cropClips,
                                      // Keep committed montage effects visible after closing the editor.
                                      magicEnabled:
                                          _isCropMode || _cropClips.isNotEmpty,
                                      onControllerReady:
                                          _registerVideoController,
                                      onControllerReleased:
                                          _unregisterVideoController,
                                      onTap: () {
                                        if (_isCropMode) {
                                          _isFrameSelectedNotifier.value =
                                              !_isFrameSelectedNotifier.value;
                                          return;
                                        }
                                        _togglePlayPause();
                                      },
                                    );
                                  }

                                  if (_hasGrid &&
                                      index == widget.selectedMedia!.length) {
                                    return Center(
                                      child: Image.memory(
                                        _gridSnapshot!,
                                        fit: BoxFit.contain,
                                      ),
                                    );
                                  }
                                  if (index < widget.selectedMedia!.length) {
                                    final asset = widget.selectedMedia![index];
                                    return asset.type == AssetType.video
                                        ? VideoPreviewItem(
                                            asset: asset,
                                            key: ValueKey(
                                              'vid_${asset.id}_${_fullReplacementIndex == index ? _fullReplacementFile?.path ?? '' : ''}',
                                            ),
                                            directFile:
                                                _fullReplacementIndex == index
                                                ? _fullReplacementFile
                                                : null,
                                            filterClips: _filterClips,
                                            videoPositionNotifier:
                                                _videoPositionNotifier,
                                            isFrameSelectedNotifier:
                                                _isFrameSelectedNotifier,
                                            isSeekingNotifier:
                                                _isSeekingCropNotifier,
                                            cropOverlays: _cropOverlays,
                                            overlayPosition: _overlayProjectMs,
                                            magicClips: _cropClips,
                                            magicEnabled:
                                                _isCropMode ||
                                                _cropClips.isNotEmpty,
                                            onControllerReady:
                                                _registerVideoController,
                                            onControllerReleased:
                                                _unregisterVideoController,
                                            onTap: () {
                                              if (_isCropMode) {
                                                _isFrameSelectedNotifier.value =
                                                    !_isFrameSelectedNotifier
                                                        .value;
                                                return;
                                              }
                                              _togglePlayPause();
                                            },
                                          )
                                        : ImagePreviewItem(
                                            asset: asset,
                                            key: ValueKey('img_${asset.id}'),
                                          );
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),
                            ),
                          ),
                        ),

                        // Never show source footage when the whole crop project was deleted.
                        if (_cropAllDeleted)
                          const Positioned.fill(
                            child: IgnorePointer(
                              child: ColoredBox(
                                color: Color(0xFF0F1720),
                                child: Center(
                                  child: Text(
                                    'لا توجد مقاطع فيديو',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                ),
                              ),
                            ),
                          ),

                        // Replaced segment is shown over the original player only while its
                        // position is inside that exact timeline segment.
                        if (_isCropMode && _replacementPlayers.isNotEmpty)
                          Positioned.fill(
                            child: ValueListenableBuilder<Duration>(
                              valueListenable: _videoPositionNotifier,
                              builder: (context, position, _) {
                                final current = CropRotation.clipAt(_cropClips, position);
                                final active = current?.replacementPath == null ? null : current;
                                final replacement = active == null
                                    ? null
                                    : _replacementPlayers[active
                                          .replacementPath];
                                if (active == null ||
                                    replacement == null ||
                                    !replacement.value.isInitialized)
                                  return const SizedBox.shrink();
                                return IgnorePointer(
                                  child: ColoredBox(
                                    color: const Color(0xFF0F1720),
                                    child: Center(
                                      child: AspectRatio(
                                        aspectRatio: _cropOverlays.isEmpty
                                            ? replacement.value.aspectRatio
                                            : (_activeVideoControllers
                                                      .firstOrNull
                                                      ?.value
                                                      .aspectRatio ??
                                                  replacement
                                                      .value
                                                      .aspectRatio),
                                        child: _withCropOverlays(
                                          TiniEffectsPreview(
                                            clipId: active.id,
                                            effects: active.videoEffects,
                                            colorFilter: active.colorFilter,
                                            elapsedSeconds: active
                                                .projectOffsetForSource(
                                                  position,
                                                ),
                                            sledSourceController: replacement,
                                            sledSourcePath:
                                                active.replacementPath,
                                            sledSourceTimeMs: replacement
                                                .value
                                                .position
                                                .inMilliseconds,
                                            child: CropAnimationPreview(
                                              settings: active.animations,
                                              elapsed: Duration(
                                                microseconds:
                                                    (active.projectOffsetForSource(
                                                              position,
                                                            ) *
                                                            1000000)
                                                        .round(),
                                              ),
                                              clipDuration:
                                                  active.playbackDuration,
                                              child: CropMagicLivePreview(
                                                effectId: active.magicEffectId,
                                                child: VideoPlayer(replacement),
                                              ),
                                            ),
                                          ),
                                          position,
                                          replacement,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),

                        // Show the same saved cutout/edges after leaving crop mode.
                        if (_backgroundPreviewPlayer != null)
                          Positioned.fill(
                            child: ValueListenableBuilder<Duration>(
                              valueListenable: _videoPositionNotifier,
                              builder: (context, position, _) {
                                final match = _cropClips
                                    .where(
                                      (c) =>
                                          c.id == _backgroundPreviewClipId &&
                                          c.id == CropRotation.clipAt(_cropClips, position)?.id &&
                                          _backgroundKey(c) ==
                                              _backgroundPreviewKey,
                                    )
                                    .firstOrNull;
                                final player = _backgroundPreviewPlayer;
                                if (match == null ||
                                    player == null ||
                                    !player.value.isInitialized) {
                                  return const SizedBox.shrink();
                                }
                                return IgnorePointer(
                                  child: ColoredBox(
                                    color: const Color(0xFF0F1720),
                                    child: Center(
                                      child: AspectRatio(
                                        aspectRatio: _cropOverlays.isEmpty
                                            ? player.value.aspectRatio
                                            : (_activeVideoControllers
                                                      .firstOrNull
                                                      ?.value
                                                      .aspectRatio ??
                                                  player.value.aspectRatio),
                                        child: _withCropOverlays(
                                          TiniEffectsPreview(
                                            clipId: match.id,
                                            effects: match.videoEffects,
                                            colorFilter: match.colorFilter,
                                            elapsedSeconds: match
                                                .projectOffsetForSource(
                                                  position,
                                                ),
                                            sledSourceController: player,
                                            sledSourcePath:
                                                _backgroundPreviewPath,
                                            sledSourceTimeMs: player
                                                .value
                                                .position
                                                .inMilliseconds,
                                            child: CropAnimationPreview(
                                              settings: match.animations,
                                              elapsed: Duration(
                                                microseconds:
                                                    (match.projectOffsetForSource(
                                                              position,
                                                            ) *
                                                            1000000)
                                                        .round(),
                                              ),
                                              clipDuration:
                                                  match.playbackDuration,
                                              child: CropMagicLivePreview(
                                                effectId: match.magicEffectId,
                                                child: VideoPlayer(player),
                                              ),
                                            ),
                                          ),
                                          position,
                                          player,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        if (_backgroundBusy && _isCropMode)
                          const Positioned(
                            top: 50,
                            left: 20,
                            right: 20,
                            child: IgnorePointer(
                              child: Center(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Color(0xCC1A222C),
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(12),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.all(10),
                                    child: Text(
                                      'جار تجهيز معاينة الخلفية…',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                        if (_retouchPlayer?.value.isInitialized == true &&
                            _retouchKey == _retouchSignature())
                          Positioned.fill(
                            child: IgnorePointer(
                              child: ValueListenableBuilder<Duration>(
                                valueListenable: _videoPositionNotifier,
                                builder: (context, position, _) => Center(
                                  child: AspectRatio(
                                    aspectRatio:
                                        _retouchPlayer!.value.aspectRatio,
                                    child: _withCropOverlays(
                                      cropRetouchVideo(_retouchPlayer!),
                                      position,
                                      _retouchPlayer!,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (_retouchRendering && _isCropMode)
                          const Positioned(
                            top: 50,
                            left: 20,
                            right: 20,
                            child: IgnorePointer(
                              child: Center(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Color(0xCC1C1C1E),
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Text(
                                      'جار تجهيز معاينة التنميق…',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                        // رسم النصوص اللي رجعت من المحرر فوق الفيديو
                        if (_textLayers.isNotEmpty)
                          ..._textLayers.map((layer) {
                            final hasBg =
                                layer.backgroundColor != null &&
                                layer.backgroundColor != Colors.transparent;
                            return Positioned(
                              left: layer.x,
                              top: layer.y,
                              child: FractionalTranslation(
                                translation: const Offset(-0.5, -0.5),
                                child: Transform.scale(
                                  scale: layer.scale,
                                  child: Transform.rotate(
                                    angle: layer.rotation,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: hasBg
                                            ? layer.backgroundColor!.withValues(
                                                alpha: layer.backgroundOpacity,
                                              )
                                            : Colors.transparent,
                                        borderRadius: hasBg
                                            ? BorderRadius.circular(12)
                                            : null,
                                      ),
                                      child: Text(
                                        layer.text,
                                        textAlign: layer.align,
                                        style: TextStyle(
                                          color: layer.color,
                                          fontFamily: layer.fontFamily,
                                          fontSize: 32,
                                          shadows: [
                                            Shadow(
                                              blurRadius: 2,
                                              color: Colors.black54,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        // --- بداية رسم الستيكرات ---
                        if (_stickerLayers.isNotEmpty)
                          ..._stickerLayers.map((sticker) {
                            return StickerWidget(
                              key: ValueKey(sticker.id),
                              sticker: sticker,
                              screenSize: MediaQuery.of(context).size,
                              onUpdate: _updateStickerLayer,
                              onDelete: _deleteStickerLayer,
                              onTap: _selectStickerLayer,
                            );
                          }),
                        // --- نهاية رسم الستيكرات ---
                      ],
                    ),
                  ), // End camera-safe preview inset.
                ),

                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: media.padding.top > topBarHeight
                      ? media.padding.top
                      : topBarHeight,
                  child: Container(color: Colors.teal),
                ),

                if (!_isFilterMode && !_isCropMode) // ← ضيف && !_isCropMode
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: bottomBarHeight,
                    child: Container(color: Colors.teal),
                  ),

                Positioned(
                  top: media.padding.top + topBarHeight + 8,
                  left: 15,
                  right: 15,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // يسار فوق - إلغاء أو رجوع
                      _isFilterMode || _isCropMode
                          ? GestureDetector(
                              onTap: () {
                                Navigator.pop(context); // بسكر الشيت
                                setState(() {
                                  _isFilterMode = false;
                                  _isCropMode = false;
                                });
                              },
                              child: const Text(
                                'إلغاء',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            )
                          : _topCircleButton(
                              Icons.arrow_back_ios_new,
                              () => Navigator.pop(context),
                            ),

                      // يمين فوق - حفظ أو تثبيت
                      _isFilterMode || _isCropMode
                          ? GestureDetector(
                              onTap: () {
                                // منطق الحفظ بعدين
                                Navigator.pop(context); // بسكر الشيت
                                setState(() {
                                  _isFilterMode = false;
                                  _isCropMode = false;
                                });
                              },
                              child: const Text(
                                'حفظ',
                                style: TextStyle(
                                  color: Colors.teal,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          : !widget.isDuet
                          ? _buildPinToggle()
                          : const SizedBox(), // ← هاد السطر حل المشكلة
                    ],
                  ),
                ),
                if (!_isFilterMode && !_isCropMode)
                  Positioned(
                    top: topBarHeight + 20,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: GestureDetector(
                        onTap: () {
                          showMusicSheet(
                            context: context,
                            onTrackSelected: (Map<String, dynamic> selectedTrack) async {
                              if (!mounted) return;

                              // 1. استخراج الرابط بأمان مع التحقق
                              final String? rawUrl =
                                  selectedTrack['url'] ??
                                  selectedTrack['streamUrl'];
                              final String title =
                                  selectedTrack['title'] ??
                                  selectedTrack['name'] ??
                                  "صوت بدون عنوان";

                              if (rawUrl == null || rawUrl.isEmpty) {
                                debugPrint("خطأ: الرابط المستلم فارغ");
                                return;
                              }

                              // 2. تحديث الواجهة أولاً
                              _selectedAudioUrl = rawUrl;
                              _selectedAudioTitle = title;
                              _cropMusicRange = const RangeValues(0, 1);
                              _audioSource =
                                  'itunes'; // <-- أضف هذا السطر لتعريف أن المصدر هو iTunes
                              _selectedAudioArtist =
                                  selectedTrack['artist'] ??
                                  selectedTrack['uploader'];
                              _selectedAudioCover =
                                  selectedTrack['cover'] ??
                                  selectedTrack['artworkUrl100'];
                              audioTitleNotifier.value = title;

                              // 3. تشغيل الصوت داخل try-catch لمنع الانهيار
                              try {
                                // إيقاف أي صوت سابق قبل تحميل الجديد لتجنب التعارض
                                await _audioPlayer.stop();

                                // تحميل المصدر الجديد
                                await _audioPlayer.setSource(UrlSource(rawUrl));
                                await _audioPlayer.setVolume(
                                  musicVolume,
                                ); // تطبيق قيمة الميكسر الحالية

                                // لازم نحدث المنسق أول عشان يعرف عن الفيديو الحالي
                                _updateSyncController();

                                print("=== DEBUG SYNC ===");
                                print(
                                  "SyncController is null? ${_syncController == null}",
                                );
                                print(
                                  "Videos count: ${_activeVideoControllers.length}",
                                );
                                print("Audio URL: $_selectedAudioUrl");
                                print(
                                  "AudioPlayer state: ${_audioPlayer.state}",
                                );
                                for (
                                  var i = 0;
                                  i < _activeVideoControllers.length;
                                  i++
                                ) {
                                  print(
                                    "Video $i isPlaying: ${_activeVideoControllers[i].value.isPlaying}",
                                  );
                                  print(
                                    "Video $i isInitialized: ${_activeVideoControllers[i].value.isInitialized}",
                                  );
                                }
                                print("==================");

                                if (_activeVideoControllers.isNotEmpty) {
                                  await _syncController?.playAll();
                                } else {
                                  await _audioPlayer.resume();
                                }

                                debugPrint("تم ضبط المصدر بنجاح");
                              } catch (e) {
                                // إذا حدث خطأ، سيصل الكود هنا ولن ينهار التطبيق
                                debugPrint("حدث خطأ أثناء تحميل الصوت: $e");

                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        "تعذر تشغيل هذا الصوت: صيغة غير مدعومة أو رابط تالف",
                                      ),
                                      backgroundColor: Colors.redAccent,
                                    ),
                                  );
                                }
                              }
                            },
                          );
                        },
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.60,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.music_note,
                                color: Colors.white,
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: ValueListenableBuilder<String>(
                                  valueListenable: audioTitleNotifier,
                                  builder: (context, title, child) {
                                    return Text(
                                      title,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (!_isFilterMode && !_isCropMode)
                  Positioned(
                    right: 15,
                    top: MediaQuery.of(context).size.height * 0.15,
                    child: Column(
                      children: [
                        _sideToolIcon(Icons.tune, onTap: _openAudioMixerSheet),
                        _sideToolIcon(
                          Icons.text_fields,
                          onTap: () async {
                            // 1. حدد اذا فيديو ولا صورة
                            final bool isVideo =
                                widget.videoFile != null ||
                                (widget.selectedMedia != null &&
                                    widget.selectedMedia!.isNotEmpty &&
                                    widget.selectedMedia![_currentIndex].type ==
                                        AssetType.video);

                            // 2. حدد الفيديو/الصورة الحالية
                            File? currentFile;
                            AssetEntity? currentAsset;

                            if (widget.videoFile != null) {
                              currentFile = widget.videoFile;
                            } else if (widget.selectedMedia != null &&
                                widget.selectedMedia!.isNotEmpty) {
                              currentAsset =
                                  widget.selectedMedia![_currentIndex];
                            }

                            // 3. افتح المحرر ومرر كل شي صح
                            final result = await Navigator.of(context)
                                .push<List<TextLayer>>(
                                  MaterialPageRoute(
                                    builder: (_) => TextEditorOverlay(
                                      videoFile: isVideo ? currentFile : null,
                                      videoAsset: isVideo ? currentAsset : null,
                                      imageFile: !isVideo ? currentFile : null,
                                      imageAsset: !isVideo
                                          ? currentAsset
                                          : null,
                                      isVideo: isVideo, // مهم
                                      initialLayers: _textLayers,
                                    ),
                                  ),
                                );

                            // 4. استقبل النصوص لما يرجع
                            if (result != null && mounted) {
                              setState(() => _textLayers = result);
                            }
                          },
                        ),
                        _sideToolIcon(
                          Icons.sticky_note_2,
                          onTap: () async {
                            final StickerLayer? newSticker =
                                await showModalBottomSheet<StickerLayer>(
                                  context: context,
                                  backgroundColor:
                                      Colors.transparent, // ← غير هاد السطر
                                  isScrollControlled: true,
                                  barrierColor: Colors.black.withAlpha(
                                    25,
                                  ), // ← وغير هاد خليه اخف
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(12),
                                    ), // ← خليها 12 زي تيك توك
                                  ),
                                  builder: (context) =>
                                      const StickerPickerSheet(),
                                );

                            if (newSticker != null && mounted) {
                              _addStickerLayer(newSticker);
                            }
                          },
                        ),
                        _sideToolIcon(
                          Icons.auto_fix_high,
                          onTap: () {
                            setState(() => _isFilterMode = true);

                            showModalBottomSheet(
                              context: context,
                              backgroundColor: Colors.transparent,
                              isScrollControlled: true,
                              barrierColor: Colors.black.withAlpha(25),
                              builder: (context) => FilterBottomSheet(
                                initialFilter: _selectedFilter,
                                videoController:
                                    _activeVideoControllers.isNotEmpty
                                    ? _activeVideoControllers.first
                                    : null,
                                videoDuration:
                                    _activeVideoControllers.isNotEmpty
                                    ? _activeVideoControllers
                                          .first
                                          .value
                                          .duration
                                    : Duration(
                                        seconds: 10,
                                      ), // ← كمل هذا السطر كان ناقص
                                videoThumbnails: _videoThumbnails,
                                filterClips: _filterClips,
                                onFilterSelected: (filter) {
                                  setState(() => _selectedFilter = filter);
                                },
                                onClipAdded: (clip) {
                                  _saveStateForUndo();
                                  setState(() => _filterClips.add(clip));
                                },
                                onClipUpdated: (updatedClip) {
                                  _saveStateForUndo();
                                  setState(() {
                                    final index = _filterClips.indexWhere(
                                      (c) => c.id == updatedClip.id,
                                    );
                                    if (index != -1)
                                      _filterClips[index] = updatedClip;
                                  });
                                },
                                onClipSelected: (clipId) {
                                  setState(() {
                                    _selectedClipIndex = clipId != null
                                        ? _filterClips.indexWhere(
                                            (c) => c.id == clipId,
                                          )
                                        : null;
                                  });
                                },
                                onClipDeleted: (clipId) {
                                  // ← ضيف هذا البلوك كامل
                                  _saveStateForUndo();
                                  setState(() {
                                    _filterClips.removeWhere(
                                      (c) => c.id == clipId,
                                    );
                                    _selectedClipIndex = null;
                                  });
                                },
                                onClose: () {
                                  Navigator.pop(context); // ← بس سكر الشيت
                                },
                              ),
                            ).whenComplete(() {
                              // ← ضيف هاي
                              setState(
                                () => _isFilterMode = false,
                              ); // ← هاي الوحيدة اللي بترجع الفيديو
                            }); // ← ضيف هاي
                          },
                        ),
                        if (!widget.isDuet)
                          _sideToolIcon(
                            Icons.crop,
                            onTap: () {
                              setState(() {
                                _isCropMode = true;
                                _realVideoStart = Duration.zero;
                                _realVideoEnd = Duration.zero;
                                if (_cropClips.isNotEmpty &&
                                    (_selectedCropIndex == null ||
                                        _selectedCropIndex! >=
                                            _cropClips.length)) {
                                  _selectedCropIndex = 0;
                                }

                                if (_activeVideoControllers.isNotEmpty) {
                                  if (_cropAllDeleted) {
                                    _totalDurationNotifier.value =
                                        Duration.zero;
                                  } else if (_cropClips.isNotEmpty) {
                                    int totalMs = 0;
                                    for (var c in _cropClips) {
                                      totalMs +=
                                          c.playbackDuration.inMilliseconds;
                                    }
                                    _totalDurationNotifier.value = Duration(
                                      milliseconds: totalMs,
                                    );
                                  } else {
                                    final durationMs = _activeVideoControllers
                                        .first
                                        .value
                                        .duration
                                        .inMilliseconds;
                                    _totalDurationNotifier.value = Duration(
                                      milliseconds:
                                          (durationMs *
                                                  (_currentTrimRange.end -
                                                      _currentTrimRange.start))
                                              .round(),
                                    );
                                  }
                                }
                              });
                              _isFrameSelectedNotifier.value = false;
                              // Prevent native looping of the full source while the crop editor is open.
                              for (final controller
                                  in _activeVideoControllers) {
                                controller.setLooping(false);
                              }

                              _scaffoldKey.currentState!
                                  .showBottomSheet(
                                    (context) {
                                      return StatefulBuilder(
                                        builder: (context, setModalState) {
                                          _refreshCropSheet = setModalState;
                                          final sheetHeight = _cropSheetHeight(
                                            context,
                                          );
                                          return Container(
                                            height: sheetHeight,
                                            decoration: const BoxDecoration(
                                              color: Color(0xFF0E161B),
                                              borderRadius:
                                                  BorderRadius.vertical(
                                                    top: Radius.circular(12),
                                                  ),
                                            ),
                                            child: CropBottomSheet(
                                              onRotate: widget.isDuet ? null : () {
                                                _rotateSelectedCropClip();
                                                setModalState(() {});
                                              },
                                              onOverlay:
                                                  widget.isDuet || _overlayBusy
                                                  ? null
                                                  : _editCropOverlays,
                                              onRetouch:
                                                  widget.isDuet || _retouchBusy
                                                  ? null
                                                  : _editCropRetouch,
                                              magicLayoutHeight:
                                                  _magicPanelExpanded
                                                  ? sheetHeight
                                                  : null,
                                              animationLayoutHeight:
                                                  _animationPanelExpanded
                                                  ? sheetHeight
                                                  : null,
                                              selectedColorFilter:
                                                  _selectedCropIndex != null &&
                                                      _selectedCropIndex! >=
                                                          0 &&
                                                      _selectedCropIndex! <
                                                          _cropClips.length
                                                  ? _cropClips[_selectedCropIndex!]
                                                        .colorFilter
                                                  : const CropFilterSelection(),
                                              onColorFilterPreview:
                                                  widget.isDuet
                                                  ? null
                                                  : _previewColorFilter,
                                              onColorFilterFinish:
                                                  _finishColorFilter,
                                              onColorFilterVisibilityChanged:
                                                  (open) {
                                                    setState(
                                                      () =>
                                                          _videoEffectsPanelExpanded =
                                                              open,
                                                    );
                                                    setModalState(() {});
                                                  },
                                              selectedVideoEffects:
                                                  _selectedCropIndex != null &&
                                                      _selectedCropIndex! >=
                                                          0 &&
                                                      _selectedCropIndex! <
                                                          _cropClips.length
                                                  ? _cropClips[_selectedCropIndex!]
                                                        .videoEffects
                                                  : const [],
                                              onVideoEffectsPreview:
                                                  widget.isDuet
                                                  ? null
                                                  : _previewTiniEffects,
                                              onVideoEffectsPanelVisibilityChanged:
                                                  (open) {
                                                    setState(
                                                      () =>
                                                          _videoEffectsPanelExpanded =
                                                              open,
                                                    );
                                                    setModalState(() {});
                                                  },
                                              onVideoEffectsConfirm:
                                                  (before, after) {
                                                    _finishTiniEffects(
                                                      save: true,
                                                      updated: after,
                                                    );
                                                    setModalState(() {});
                                                  },
                                              onVideoEffectsCancel: (before) {
                                                _finishTiniEffects(save: false);
                                                setModalState(() {});
                                              },
                                              selectedAnimations:
                                                  _selectedCropIndex != null &&
                                                      _selectedCropIndex! >=
                                                          0 &&
                                                      _selectedCropIndex! <
                                                          _cropClips.length
                                                  ? _cropClips[_selectedCropIndex!]
                                                        .animations
                                                  : const CropAnimationSettings(),
                                              onAnimationPanelVisibilityChanged:
                                                  (expanded) {
                                                    setState(
                                                      () =>
                                                          _animationPanelExpanded =
                                                              expanded,
                                                    );
                                                    setModalState(() {});
                                                  },
                                              onAnimationPreview: widget.isDuet
                                                  ? null
                                                  : _previewClipAnimations,
                                              onAnimationTimelineResize:
                                                  widget.isDuet
                                                  ? null
                                                  : _resizeTimelineAnimation,
                                              onAnimationConfirm:
                                                  (original, updated) {
                                                    _finishClipAnimations(
                                                      save: true,
                                                      updated: updated,
                                                    );
                                                    setModalState(() {});
                                                  },
                                              onAnimationCancel: (original) {
                                                _finishClipAnimations(
                                                  save: false,
                                                );
                                                setModalState(() {});
                                              },
                                              videoController:
                                                  _activeVideoControllers
                                                      .isNotEmpty
                                                  ? _activeVideoControllers
                                                        .first
                                                  : null,
                                              videoDuration:
                                                  _activeVideoControllers
                                                      .isNotEmpty
                                                  ? _activeVideoControllers
                                                        .first
                                                        .value
                                                        .duration
                                                  : const Duration(seconds: 10),
                                              videoThumbnails: _videoThumbnails,
                                              cropClips: _cropClips,
                                              isTimelineEmpty: _cropAllDeleted,
                                              onDeleteUnsplit: () {
                                                if (_cropAllDeleted) return;
                                                _saveCropStateForUndo();
                                                _activeVideoControllers
                                                    .firstOrNull
                                                    ?.pause();
                                                _audioPlayer.pause();
                                                setState(() {
                                                  _cropAllDeleted = true;
                                                  _selectedCropIndex = null;
                                                  _isFrameSelectedNotifier
                                                          .value =
                                                      false;
                                                  _totalDurationNotifier.value =
                                                      Duration.zero;
                                                  _videoPositionNotifier.value =
                                                      Duration.zero;
                                                });
                                                setModalState(() {});
                                              },
                                              replacementThumbnails:
                                                  _replacementThumbnails,
                                              onReplace:
                                                  _replaceSelectedCropClip,
                                              onBackground: _editCropBackground,
                                              onCutout: _editCropCutout,
                                              selectedSpeed:
                                                  _selectedCropIndex != null &&
                                                      _selectedCropIndex! >=
                                                          0 &&
                                                      _selectedCropIndex! <
                                                          _cropClips.length
                                                  ? _cropClips[_selectedCropIndex!]
                                                        .speed
                                                  : const CropSpeed.normal(),
                                              onSpeedPanelVisibilityChanged:
                                                  (expanded) {
                                                    setState(
                                                      () =>
                                                          _speedPanelExpanded =
                                                              expanded,
                                                    );
                                                    setModalState(() {});
                                                  },
                                              onSpeedPreview: (speed) {
                                                if (_cropAllDeleted ||
                                                    _activeVideoControllers
                                                        .isEmpty)
                                                  return;
                                                final sourceDuration =
                                                    _activeVideoControllers
                                                        .first
                                                        .value
                                                        .duration;
                                                if (sourceDuration
                                                        .inMilliseconds <=
                                                    0)
                                                  return;
                                                if (_speedEditBeforeState ==
                                                    null) {
                                                  _speedEditBeforeState =
                                                      _captureCropState();
                                                  _speedInitialProjectMs =
                                                      _totalDurationNotifier
                                                          .value
                                                          .inMilliseconds;
                                                  _speedInitialMusicRange =
                                                      _cropMusicRange;
                                                }
                                                setState(() {
                                                  if (_cropClips.isEmpty) {
                                                    final startMs =
                                                        (sourceDuration
                                                                    .inMilliseconds *
                                                                _currentTrimRange
                                                                    .start)
                                                            .round();
                                                    final endMs =
                                                        (sourceDuration
                                                                    .inMilliseconds *
                                                                _currentTrimRange
                                                                    .end)
                                                            .round();
                                                    _cropClips = [
                                                      CropClip(
                                                        id: 'speed_base_clip',
                                                        startTime: Duration(
                                                          milliseconds: startMs,
                                                        ),
                                                        endTime: Duration(
                                                          milliseconds: endMs,
                                                        ),
                                                        startFraction:
                                                            _currentTrimRange
                                                                .start,
                                                        endFraction:
                                                            _currentTrimRange
                                                                .end,
                                                      ),
                                                    ];
                                                    _selectedCropIndex = 0;
                                                  }
                                                  final index =
                                                      (_selectedCropIndex ?? 0)
                                                          .clamp(
                                                            0,
                                                            _cropClips.length -
                                                                1,
                                                          )
                                                          .toInt();
                                                  _cropClips[index] =
                                                      _cropClips[index]
                                                          .copyWith(
                                                            speed: speed,
                                                          );
                                                  final newTotalMs = _cropClips
                                                      .fold<int>(
                                                        0,
                                                        (sum, clip) =>
                                                            sum +
                                                            clip
                                                                .playbackDuration
                                                                .inMilliseconds,
                                                      );
                                                  _totalDurationNotifier
                                                      .value = Duration(
                                                    milliseconds: newTotalMs,
                                                  );
                                                  // Added music is a separate timeline track; changing video speed must
                                                  // not independently retime the music or move its original in/out marks.
                                                  if (newTotalMs > 0 &&
                                                      _speedInitialProjectMs !=
                                                          null &&
                                                      _speedInitialMusicRange !=
                                                          null) {
                                                    final oldTotal =
                                                        _speedInitialProjectMs!;
                                                    final original =
                                                        _speedInitialMusicRange!;
                                                    final begin =
                                                        (original.start *
                                                                oldTotal /
                                                                newTotalMs)
                                                            .clamp(0.0, 1.0)
                                                            .toDouble();
                                                    final end =
                                                        (original.end *
                                                                oldTotal /
                                                                newTotalMs)
                                                            .clamp(begin, 1.0)
                                                            .toDouble();
                                                    _cropMusicRange =
                                                        RangeValues(begin, end);
                                                  }
                                                });
                                                final controller =
                                                    _activeVideoControllers
                                                        .first;
                                                _applyCropPlaybackSpeed(
                                                  controller,
                                                  controller.value.position,
                                                );
                                                setModalState(() {});
                                              },
                                              onSpeedConfirm:
                                                  (original, updated) {
                                                    final previous =
                                                        _speedEditBeforeState;
                                                    _speedEditBeforeState =
                                                        null;
                                                    _speedInitialProjectMs =
                                                        null;
                                                    _speedInitialMusicRange =
                                                        null;
                                                    if (previous != null) {
                                                      _cropUndoStack.add(
                                                        previous,
                                                      );
                                                      _cropRedoStack.clear();
                                                    }
                                                    setModalState(() {});
                                                  },
                                              onSpeedCancel: (original) {
                                                final previous =
                                                    _speedEditBeforeState;
                                                _speedEditBeforeState = null;
                                                _speedInitialProjectMs = null;
                                                _speedInitialMusicRange = null;
                                                if (previous != null)
                                                  setState(
                                                    () => _restoreCropState(
                                                      previous,
                                                    ),
                                                  );
                                                setModalState(() {});
                                              },
                                              selectedMagicEffectId:
                                                  _selectedCropIndex != null &&
                                                      _selectedCropIndex! >=
                                                          0 &&
                                                      _selectedCropIndex! <
                                                          _cropClips.length
                                                  ? _cropClips[_selectedCropIndex!]
                                                        .magicEffectId
                                                  : null,
                                              magicSourcePath:
                                                  _selectedCropIndex != null &&
                                                      _selectedCropIndex! >=
                                                          0 &&
                                                      _selectedCropIndex! <
                                                          _cropClips.length &&
                                                      _cropClips[_selectedCropIndex!]
                                                              .replacementPath !=
                                                          null
                                                  ? _cropClips[_selectedCropIndex!]
                                                        .replacementPath!
                                                  : (_activeVideoControllers
                                                            .firstOrNull
                                                            ?.dataSource ??
                                                        ''),
                                              magicSourceStart:
                                                  _selectedCropIndex != null &&
                                                      _selectedCropIndex! >=
                                                          0 &&
                                                      _selectedCropIndex! <
                                                          _cropClips.length
                                                  ? (_cropClips[_selectedCropIndex!]
                                                                .replacementPath !=
                                                            null
                                                        ? _cropClips[_selectedCropIndex!]
                                                              .replacementStartTime
                                                        : _cropClips[_selectedCropIndex!]
                                                              .startTime)
                                                  : Duration(
                                                      milliseconds:
                                                          ((_activeVideoControllers
                                                                          .firstOrNull
                                                                          ?.value
                                                                          .duration
                                                                          .inMilliseconds ??
                                                                      0) *
                                                                  _currentTrimRange
                                                                      .start)
                                                              .round(),
                                                    ),
                                              magicSourceEnd:
                                                  _selectedCropIndex != null &&
                                                      _selectedCropIndex! >=
                                                          0 &&
                                                      _selectedCropIndex! <
                                                          _cropClips.length
                                                  ? ((_cropClips[_selectedCropIndex!]
                                                                    .replacementPath !=
                                                                null
                                                            ? _cropClips[_selectedCropIndex!]
                                                                  .replacementStartTime
                                                            : _cropClips[_selectedCropIndex!]
                                                                  .startTime) +
                                                        _cropClips[_selectedCropIndex!]
                                                            .duration)
                                                  : Duration(
                                                      milliseconds:
                                                          ((_activeVideoControllers
                                                                          .firstOrNull
                                                                          ?.value
                                                                          .duration
                                                                          .inMilliseconds ??
                                                                      0) *
                                                                  _currentTrimRange
                                                                      .end)
                                                              .round(),
                                                    ),
                                              onMagicPanelVisibilityChanged:
                                                  (expanded) {
                                                    setState(
                                                      () =>
                                                          _magicPanelExpanded =
                                                              expanded,
                                                    );
                                                    setModalState(() {});
                                                  },
                                              onMagicPreview:
                                                  _previewMagicEffect,
                                              onMagicConfirm:
                                                  (original, updated) {
                                                    _finishMagicEffect(
                                                      save: true,
                                                      updated: updated,
                                                    );
                                                    setModalState(() {});
                                                  },
                                              onMagicCancel: (original) {
                                                _finishMagicEffect(save: false);
                                                setModalState(() {});
                                              },
                                              hasMusic:
                                                  _selectedAudioUrl != null,
                                              musicPlayer:
                                                  _selectedAudioUrl != null
                                                  ? _audioPlayer
                                                  : null,
                                              audioName:
                                                  _selectedAudioTitle ?? 'صوت',
                                              audioRange: _cropMusicRange,
                                              initialRange: _currentTrimRange,
                                              onAudioRangeChanged: (range) {
                                                setState(
                                                  () => _cropMusicRange = range,
                                                );
                                                setModalState(() {});
                                              },
                                              onClipSelected: (id) {
                                                final index = _cropClips
                                                    .indexWhere(
                                                      (c) => c.id == id,
                                                    );
                                                if (index < 0) return;
                                                setState(() {
                                                  _selectedCropIndex = index;
                                                  _currentTrimRange =
                                                      RangeValues(
                                                        _cropClips[index]
                                                            .startFraction,
                                                        _cropClips[index]
                                                            .endFraction,
                                                      );
                                                });
                                                setModalState(() {});
                                              },
                                              selectedClipId:
                                                  _selectedCropIndex != null
                                                  ? _cropClips[_selectedCropIndex!]
                                                        .id
                                                  : null,
                                              onClipMuteChanged:
                                                  (clipId, isMuted) {
                                                    _handleClipMuteChanged(
                                                      clipId,
                                                      isMuted,
                                                    );
                                                    setModalState(() {});
                                                  },
                                              onTrimChanged: (start, end) {
                                                if (_activeVideoControllers
                                                    .isEmpty)
                                                  return;
                                                final controller =
                                                    _activeVideoControllers
                                                        .first;
                                                final totalMs = controller
                                                    .value
                                                    .duration
                                                    .inMilliseconds;
                                                if (totalMs <= 0) return;
                                                // The range is in ORIGINAL video time; never shift other clips' source times.
                                                final minFraction =
                                                    (100 / totalMs).clamp(
                                                      0.0,
                                                      1.0,
                                                    );
                                                double safeStart = start
                                                    .clamp(
                                                      0.0,
                                                      1.0 - minFraction,
                                                    )
                                                    .toDouble();
                                                double safeEnd = end
                                                    .clamp(
                                                      safeStart + minFraction,
                                                      1.0,
                                                    )
                                                    .toDouble();
                                                // When a segment has an alternative source, never drag beyond that
                                                // video's real frames. The unrelated original segments remain unchanged.
                                                if (_selectedCropIndex !=
                                                        null &&
                                                    _selectedCropIndex! >= 0 &&
                                                    _selectedCropIndex! <
                                                        _cropClips.length) {
                                                  final selected =
                                                      _cropClips[_selectedCropIndex!];
                                                  if (selected.replacementPath !=
                                                          null &&
                                                      selected.replacementSourceDuration !=
                                                          null) {
                                                    final minStartMs =
                                                        selected
                                                            .startTime
                                                            .inMilliseconds -
                                                        selected
                                                            .replacementStartTime
                                                            .inMilliseconds;
                                                    final maxEndMs =
                                                        selected
                                                            .endTime
                                                            .inMilliseconds +
                                                        selected
                                                            .replacementSourceDuration!
                                                            .inMilliseconds -
                                                        (selected
                                                                .replacementStartTime
                                                                .inMilliseconds +
                                                            selected
                                                                .duration
                                                                .inMilliseconds);
                                                    safeStart = safeStart
                                                        .clamp(
                                                          (minStartMs / totalMs)
                                                              .clamp(0.0, 1.0),
                                                          selected.endFraction -
                                                              minFraction,
                                                        )
                                                        .toDouble();
                                                    safeEnd = safeEnd
                                                        .clamp(
                                                          safeStart +
                                                              minFraction,
                                                          (maxEndMs / totalMs)
                                                              .clamp(0.0, 1.0),
                                                        )
                                                        .toDouble();
                                                  }
                                                }
                                                final isDraggingStart =
                                                    (safeStart -
                                                            _currentTrimRange
                                                                .start)
                                                        .abs() >
                                                    (safeEnd -
                                                            _currentTrimRange
                                                                .end)
                                                        .abs();
                                                setState(() {
                                                  _currentTrimRange =
                                                      RangeValues(
                                                        safeStart,
                                                        safeEnd,
                                                      );
                                                  if (_cropClips.isNotEmpty &&
                                                      _selectedCropIndex !=
                                                          null &&
                                                      _selectedCropIndex! >=
                                                          0 &&
                                                      _selectedCropIndex! <
                                                          _cropClips.length) {
                                                    final index =
                                                        _selectedCropIndex!;
                                                    final previousClip =
                                                        _cropClips[index];
                                                    final deltaStartMs =
                                                        (totalMs * safeStart)
                                                            .round() -
                                                        previousClip
                                                            .startTime
                                                            .inMilliseconds;
                                                    _cropClips[index] =
                                                        previousClip.copyWith(
                                                          replacementStartTime:
                                                              previousClip
                                                                  .replacementStartTime +
                                                              Duration(
                                                                milliseconds:
                                                                    deltaStartMs,
                                                              ),
                                                          startFraction:
                                                              safeStart,
                                                          endFraction: safeEnd,
                                                          startTime: Duration(
                                                            milliseconds:
                                                                (totalMs *
                                                                        safeStart)
                                                                    .round(),
                                                          ),
                                                          endTime: Duration(
                                                            milliseconds:
                                                                (totalMs *
                                                                        safeEnd)
                                                                    .round(),
                                                          ),
                                                        );
                                                    final durationMs =
                                                        _cropClips.fold<int>(
                                                          0,
                                                          (ms, clip) =>
                                                              ms +
                                                              clip
                                                                  .playbackDuration
                                                                  .inMilliseconds,
                                                        );
                                                    _totalDurationNotifier
                                                        .value = Duration(
                                                      milliseconds: durationMs,
                                                    );
                                                  } else {
                                                    _realVideoStart = Duration(
                                                      milliseconds:
                                                          (totalMs * safeStart)
                                                              .round(),
                                                    );
                                                    _realVideoEnd = Duration(
                                                      milliseconds:
                                                          (totalMs * safeEnd)
                                                              .round(),
                                                    );
                                                    _totalDurationNotifier
                                                            .value =
                                                        _realVideoEnd -
                                                        _realVideoStart;
                                                  }
                                                });
                                                final target = Duration(
                                                  milliseconds:
                                                      (totalMs *
                                                              (isDraggingStart
                                                                  ? safeStart
                                                                  : safeEnd))
                                                          .round(),
                                                );
                                                controller.pause();
                                                controller.seekTo(target);
                                                _videoPositionNotifier.value =
                                                    target;
                                                setModalState(() {});
                                              },
                                              onCropApplied: (clip) {
                                                _saveCropStateForUndo();
                                                setState(() {
                                                  _cropClips.add(clip);
                                                  _cropAllDeleted = false;
                                                  int totalMs = 0;
                                                  for (var c in _cropClips) {
                                                    totalMs += c
                                                        .playbackDuration
                                                        .inMilliseconds;
                                                  }
                                                  _totalDurationNotifier.value =
                                                      Duration(
                                                        milliseconds: totalMs,
                                                      );
                                                });
                                                setModalState(() {});
                                              },
                                              onClipDeleted: (clipId) {
                                                final int delIndex = _cropClips
                                                    .indexWhere(
                                                      (c) => c.id == clipId,
                                                    );
                                                if (delIndex == -1) return;
                                                _saveCropStateForUndo();
                                                final Duration vidDur =
                                                    _activeVideoControllers
                                                        .isNotEmpty
                                                    ? _activeVideoControllers
                                                          .first
                                                          .value
                                                          .duration
                                                    : const Duration(
                                                        seconds: 10,
                                                      );
                                                // Preserve the logical position of neighbouring clips and ripple audio.
                                                final oldTotalMs = _cropClips
                                                    .fold<int>(
                                                      0,
                                                      (total, clip) =>
                                                          total +
                                                          clip
                                                              .playbackDuration
                                                              .inMilliseconds,
                                                    );
                                                final removedStartMs = _cropClips
                                                    .take(delIndex)
                                                    .fold<int>(
                                                      0,
                                                      (total, clip) =>
                                                          total +
                                                          clip
                                                              .playbackDuration
                                                              .inMilliseconds,
                                                    );
                                                final removedDurationMs =
                                                    _cropClips[delIndex]
                                                        .playbackDuration
                                                        .inMilliseconds;
                                                final remainingAudioRange =
                                                    _musicRangeAfterDelete(
                                                      oldTotalMs,
                                                      removedStartMs,
                                                      removedDurationMs,
                                                    );
                                                final List<CropClip> newClips =
                                                    CropCutActions.deleteClip(
                                                      clips: _cropClips,
                                                      selectedIndex: delIndex,
                                                      videoDuration: vidDur,
                                                    );
                                                _activeVideoControllers
                                                    .firstOrNull
                                                    ?.pause();
                                                _audioPlayer.pause();
                                                setState(() {
                                                  _cropClips = newClips;
                                                  _cropAllDeleted =
                                                      newClips.isEmpty;
                                                  _cropMusicRange =
                                                      remainingAudioRange;
                                                  _selectedCropIndex =
                                                      newClips.isEmpty
                                                      ? null
                                                      : delIndex
                                                            .clamp(
                                                              0,
                                                              newClips.length -
                                                                  1,
                                                            )
                                                            .toInt();
                                                  _isFrameSelectedNotifier
                                                          .value =
                                                      newClips.isNotEmpty;
                                                  if (_cropAllDeleted) {
                                                    _currentTrimRange =
                                                        const RangeValues(
                                                          0.0,
                                                          1.0,
                                                        );
                                                    _totalDurationNotifier
                                                            .value =
                                                        Duration.zero;
                                                    _realVideoStart =
                                                        Duration.zero;
                                                    _realVideoEnd =
                                                        Duration.zero;
                                                  } else {
                                                    final selected =
                                                        newClips[_selectedCropIndex!];
                                                    _currentTrimRange =
                                                        RangeValues(
                                                          selected
                                                              .startFraction,
                                                          selected.endFraction,
                                                        );
                                                    _totalDurationNotifier
                                                        .value = Duration(
                                                      milliseconds: newClips.fold<int>(
                                                        0,
                                                        (total, clip) =>
                                                            total +
                                                            clip
                                                                .playbackDuration
                                                                .inMilliseconds,
                                                      ),
                                                    );
                                                  }
                                                  final newPosition =
                                                      _cropAllDeleted
                                                      ? Duration.zero
                                                      : newClips[_selectedCropIndex!]
                                                            .startTime;
                                                  if (!_cropAllDeleted)
                                                    _activeVideoControllers
                                                        .firstOrNull
                                                        ?.seekTo(newPosition);
                                                  _videoPositionNotifier.value =
                                                      newPosition;
                                                  // The music player seeks in the compact edited timeline, not source time.
                                                  final positionMs =
                                                      _cropAllDeleted
                                                      ? 0
                                                      : newClips
                                                            .take(
                                                              _selectedCropIndex!,
                                                            )
                                                            .fold<int>(
                                                              0,
                                                              (total, clip) =>
                                                                  total +
                                                                  clip
                                                                      .playbackDuration
                                                                      .inMilliseconds,
                                                            );
                                                  if (_selectedAudioUrl !=
                                                      null) {
                                                    _audioPlayer.seek(
                                                      Duration(
                                                        milliseconds:
                                                            positionMs,
                                                      ),
                                                    );
                                                  }
                                                });
                                                setModalState(() {});
                                              },
                                              onSplit: (fraction) {
                                                if (_cropAllDeleted ||
                                                    _activeVideoControllers
                                                        .isEmpty)
                                                  return;
                                                final controller =
                                                    _activeVideoControllers
                                                        .first;
                                                if (!controller
                                                    .value
                                                    .isInitialized)
                                                  return;
                                                final Duration videoDur =
                                                    controller.value.duration;
                                                final durationMs =
                                                    videoDur.inMilliseconds;
                                                if (durationMs <= 0) return;

                                                // أول تقسيم يبدأ من حدود القص الفعلية، ولا يُعيد الفيديو الأصلي كاملاً.
                                                final List<CropClip>
                                                originalClips =
                                                    _cropClips.isEmpty
                                                    ? [
                                                        CropClip(
                                                          id: 'base_clip',
                                                          startFraction:
                                                              _currentTrimRange
                                                                  .start,
                                                          endFraction:
                                                              _currentTrimRange
                                                                  .end,
                                                          startTime: Duration(
                                                            milliseconds:
                                                                (durationMs *
                                                                        _currentTrimRange
                                                                            .start)
                                                                    .round(),
                                                          ),
                                                          endTime: Duration(
                                                            milliseconds:
                                                                (durationMs *
                                                                        _currentTrimRange
                                                                            .end)
                                                                    .round(),
                                                          ),
                                                        ),
                                                      ]
                                                    : _cropClips;

                                                final splitMs =
                                                    (fraction.clamp(0.0, 1.0) *
                                                            durationMs)
                                                        .round();
                                                // تحديد المقطع من زمن المصدر، والتأكد من بقاء 0.1 ثانية بكل جزء.
                                                final targetIndex =
                                                    originalClips.indexWhere(
                                                      (clip) =>
                                                          splitMs -
                                                                  clip
                                                                      .startTime
                                                                      .inMilliseconds >=
                                                              100 &&
                                                          clip.endTime.inMilliseconds -
                                                                  splitMs >=
                                                              100,
                                                    );
                                                if (targetIndex < 0) return;

                                                final updatedClips =
                                                    CropCutActions.splitAt(
                                                      clips: originalClips,
                                                      fraction: fraction,
                                                      selectedIndex:
                                                          targetIndex,
                                                      videoDuration: videoDur,
                                                    );
                                                if (updatedClips.length !=
                                                    originalClips.length + 1)
                                                  return;

                                                // احفظ الحالة قبل إنشاء أول base_clip، لتعمل Undo/Redo بشكل صحيح.
                                                _saveCropStateForUndo();
                                                controller.pause();
                                                _audioPlayer.pause();
                                                setState(() {
                                                  _cropClips = updatedClips;
                                                  _selectedCropIndex =
                                                      targetIndex + 1;
                                                  final newClip =
                                                      _cropClips[_selectedCropIndex!];
                                                  _currentTrimRange =
                                                      RangeValues(
                                                        newClip.startFraction,
                                                        newClip.endFraction,
                                                      );
                                                  _isFrameSelectedNotifier
                                                          .value =
                                                      true;
                                                  _isCropMode = true;
                                                  _isSeekingCropNotifier.value =
                                                      false;
                                                  _totalDurationNotifier
                                                      .value = Duration(
                                                    milliseconds: _cropClips
                                                        .fold<int>(
                                                          0,
                                                          (total, clip) =>
                                                              total +
                                                              clip
                                                                  .playbackDuration
                                                                  .inMilliseconds,
                                                        ),
                                                  );
                                                  controller.seekTo(
                                                    newClip.startTime,
                                                  );
                                                  _videoPositionNotifier.value =
                                                      newClip.startTime;
                                                });
                                                setModalState(() {});
                                              },
                                              onClose: () =>
                                                  Navigator.pop(context),
                                              onFullScreen: () {
                                                setState(
                                                  () => _isCropMode = false,
                                                );
                                                Navigator.pop(context);
                                              },
                                              onUndo: () {
                                                if (_cropUndoStack.isEmpty)
                                                  return;
                                                setState(() {
                                                  _cropRedoStack.add(
                                                    _captureCropState(),
                                                  );
                                                  _restoreCropState(
                                                    _cropUndoStack.removeLast(),
                                                  );
                                                });
                                                setModalState(() {});
                                              },
                                              onRedo: () {
                                                if (_cropRedoStack.isEmpty)
                                                  return;
                                                setState(() {
                                                  _cropUndoStack.add(
                                                    _captureCropState(),
                                                  );
                                                  _restoreCropState(
                                                    _cropRedoStack.removeLast(),
                                                  );
                                                });
                                                setModalState(() {});
                                              },
                                              canUndo:
                                                  _cropUndoStack.isNotEmpty,
                                              canRedo:
                                                  _cropRedoStack.isNotEmpty,
                                              videoPositionNotifier:
                                                  _videoPositionNotifier,
                                              totalDurationNotifier:
                                                  _totalDurationNotifier,
                                              isFrameSelectedNotifier:
                                                  _isFrameSelectedNotifier,
                                            ),
                                          );
                                        },
                                      );
                                    },
                                    backgroundColor: Colors.transparent,
                                    enableDrag: true,
                                  )
                                  .closed
                                  .whenComplete(() {
                                    // Restore the pre-existing full-video looping outside the crop editor.
                                    for (final controller
                                        in _activeVideoControllers) {
                                      controller.setLooping(!_cropAllDeleted);
                                    }
                                    setState(() {
                                      _isCropMode = false;
                                      _realVideoStart = Duration.zero;
                                      _realVideoEnd = Duration.zero;
                                    });
                                    _isFrameSelectedNotifier.value = false;
                                    final pendingSpeedEdit =
                                        _speedEditBeforeState;
                                    if (pendingSpeedEdit != null) {
                                      _restoreCropState(pendingSpeedEdit);
                                    }
                                    _speedPanelExpanded = false;
                                    _magicPanelExpanded = false;
                                    _animationPanelExpanded = false;
                                    final pendingColorFilter =
                                        _colorFilterBeforeState;
                                    _colorFilterBeforeState = null;
                                    if (pendingColorFilter != null)
                                      _restoreCropState(pendingColorFilter);
                                    _videoEffectsPanelExpanded = false;
                                    final pendingVideoEffects =
                                        _videoEffectsBeforeState;
                                    _videoEffectsBeforeState = null;
                                    if (pendingVideoEffects != null)
                                      _restoreCropState(pendingVideoEffects);
                                    final pendingAnimations =
                                        _animationEditBeforeState;
                                    _animationEditBeforeState = null;
                                    if (pendingAnimations != null)
                                      _restoreCropState(pendingAnimations);
                                    final pendingMagicEdit =
                                        _magicEditBeforeState;
                                    _magicEditBeforeState = null;
                                    if (pendingMagicEdit != null)
                                      _restoreCropState(pendingMagicEdit);
                                    _speedEditBeforeState = null;
                                    _speedInitialProjectMs = null;
                                    _speedInitialMusicRange = null;
                                    _resetCropPlaybackSpeeds();
                                    _refreshCropSheet = null;
                                    _currentlyPlayingReplacement = null;
                                    _backgroundPreviewPlayer?.pause();
                                    for (final player
                                        in _replacementPlayers.values) {
                                      player.pause();
                                    }
                                    for (final base
                                        in _activeVideoControllers) {
                                      base.setVolume(videoVolume);
                                    }
                                  });
                            },
                          ),
                      ],
                    ),
                  ),

                // --- أزرار Undo/Redo/Delete بوضع الفلاتر ---
                if (_isFilterMode) // فقط مع الفلاتر
                  Positioned(
                    right: 15,
                    bottom: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A222C),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white24,
                          width: 1,
                        ), // ضفت بوردر
                        boxShadow: [
                          // ضفت شادو عشان يبين فوق الشيت
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _filterToolIcon(
                            Icons.delete_outline,
                            onTap: _deleteSelectedClip,
                            enabled: _selectedClipIndex != null,
                          ),
                          const SizedBox(height: 12),
                          _filterToolIcon(
                            Icons.redo,
                            onTap: _redoFilter,
                            enabled: _redoStack.isNotEmpty,
                          ),
                          const SizedBox(height: 12),
                          _filterToolIcon(
                            Icons.undo,
                            onTap: _undoFilter,
                            enabled: _undoStack.isNotEmpty,
                          ),
                        ],
                      ),
                    ),
                  ),

                if (!_isFilterMode && !_isCropMode)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_totalCount > 0 &&
                            widget.videoFile == null &&
                            !widget.isDuet)
                          _buildThumbnailBar(),

                        Container(
                          height: bottomBarHeight,
                          padding: const EdgeInsets.symmetric(horizontal: 15),
                          alignment: Alignment.center,
                          child: Row(
                            children: [
                              _buildActionBtn(
                                label: _isStoryUploading
                                    ? "جاري النشر... ${(Provider.of<StoryProvider>(context).uploadProgress * 100).toStringAsFixed(0)}%"
                                    : "قصتك",
                                icon: _isStoryUploading
                                    ? Icons.hourglass_top
                                    : Icons.person_outline,
                                color: const Color(0xFF1A222C),
                                onTap: () async {
                                  if (_isStoryUploading) return;
                                  setState(() => _isStoryUploading = true);

                                  File? fileToUpload;
                                  if (widget.videoFile != null) {
                                    fileToUpload = widget.videoFile;
                                  } else if (widget.selectedMedia != null &&
                                      widget.selectedMedia!.isNotEmpty) {
                                    fileToUpload =
                                        await widget.selectedMedia!.first.file;
                                  }

                                  if (fileToUpload == null) {
                                    setState(() => _isStoryUploading = false);
                                    return;
                                  }

                                  final bool isVideo =
                                      fileToUpload.path.toLowerCase().endsWith(
                                        '.mp4',
                                      ) ||
                                      fileToUpload.path.toLowerCase().endsWith(
                                        '.mov',
                                      );

                                  final authProvider =
                                      Provider.of<custom.AuthProvider>(
                                        context,
                                        listen: false,
                                      );
                                  final storyProvider =
                                      Provider.of<StoryProvider>(
                                        context,
                                        listen: false,
                                      );

                                  storyProvider.addListener(() {
                                    if (mounted) setState(() {});
                                  });

                                  await storyProvider.uploadStory(
                                    file: fileToUpload,
                                    isVideo: isVideo,
                                    auth: authProvider,
                                  );

                                  setState(() => _isStoryUploading = false);
                                  if (mounted)
                                    Navigator.of(
                                      context,
                                    ).popUntil((route) => route.isFirst);
                                },
                              ),
                              const SizedBox(width: 12),
                              _buildActionBtn(
                                label: _isProcessing
                                    ? "جاري المعالجة..."
                                    : "التالي",
                                icon: Icons.arrow_forward,
                                color: const Color(0xFFFF3B30),
                                isPrimary: true,
                                onTap: () async {
                                  if (_isProcessing) return;
                                  if (_cropAllDeleted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'لا يوجد فيديو للنشر. يمكنك التراجع عن الحذف.',
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  for (final controller
                                      in _activeVideoControllers) {
                                    controller.pause();
                                  }
                                  _audioPlayer.pause();
                                  _syncController?.pauseAll();
                                  setState(() => _isProcessing = true);

                                  try {
                                    // Freeze the editor project before navigating. The render
                                    // callback must not read mutable State after the page pops.
                                    _syncEditorRevision();
                                    final clips = List<CropClip>.unmodifiable(
                                      _cropClips,
                                    );
                                    final publishRevision = _editorRevision;
                                    final publishParentRevision =
                                        _parentEditorRevision;
                                    final retouchedBase =
                                        _retouchPlayer
                                                is! CropRetouchGpuController &&
                                            _retouchKey == _retouchSignature()
                                        ? _retouchPath
                                        : null;
                                    // The preview lease belongs to a specific
                                    // input video, not only clip settings.
                                    // A full replacement or another selected
                                    // gallery item must not publish stale
                                    // pixels from the previous source.
                                    final retouchedSource =
                                        _activeVideoControllers.firstOrNull?.dataSource;
                                    final overlaySnapshot =
                                        List<CropOverlay>.unmodifiable(
                                          _cropOverlays,
                                        );
                                    final trim = _currentTrimRange;
                                    final musicRange = _cropMusicRange;
                                    final audioUrl = _selectedAudioUrl;
                                    final sourceVideoVolume = videoVolume;
                                    final sourceMusicVolume = musicVolume;
                                    final selectedIndex = _currentIndex;
                                    final selectedEffectClipIndex =
                                        _selectedCropIndex ?? 0;
                                    final replacementFile =
                                        _fullReplacementFile;
                                    final replacementIndex =
                                        _fullReplacementIndex;
                                    final sourceSize =
                                        _activeVideoControllers.isNotEmpty
                                        ? _activeVideoControllers
                                              .first
                                              .value
                                              .size
                                        : Size.zero;
                                    final overlaySize =
                                        CropOverlayOutputSize.fromSource(
                                          sourceSize.width,
                                          sourceSize.height,
                                        );
                                    final size = Size(
                                      overlaySize.width.toDouble(),
                                      overlaySize.height.toDouble(),
                                    );
                                    final sourceDuration =
                                        _activeVideoControllers.isNotEmpty
                                        ? _activeVideoControllers
                                              .first
                                              .value
                                              .duration
                                        : Duration.zero;
                                    final selectedMedia = widget.selectedMedia;
                                    final directVideoFile = widget.videoFile;
                                    final isDuet = widget.isDuet;
                                    final effects =
                                        List<FilterClip>.unmodifiable(
                                          _filterClips,
                                        );

                                    final hasEditedClips =
                                        overlaySnapshot.isNotEmpty ||
                                        clips.isNotEmpty ||
                                        trim.start > 0.00001 ||
                                        trim.end < 0.99999;
                                    String? sourcePath =
                                        replacementFile?.path ??
                                        directVideoFile?.path;
                                    bool isVideo =
                                        directVideoFile != null || isDuet;
                                    if (directVideoFile == null &&
                                        selectedMedia != null &&
                                        selectedMedia.isNotEmpty) {
                                      final index = hasEditedClips
                                          ? selectedIndex
                                                .clamp(
                                                  0,
                                                  selectedMedia.length - 1,
                                                )
                                                .toInt()
                                          : (selectedIndex <
                                                    selectedMedia.length
                                                ? selectedIndex
                                                : 0);
                                      final media = selectedMedia[index];
                                      isVideo = media.type == AssetType.video;
                                      sourcePath =
                                          (replacementIndex == index
                                              ? replacementFile?.path
                                              : null) ??
                                          (await media.file)?.path;
                                    }
                                    if (sourcePath == null ||
                                        sourcePath.isEmpty) {
                                      throw StateError(
                                        'لم يتم العثور على ملف الفيديو أو الصورة',
                                      );
                                    }
                                    if (!mounted) return;

                                    // This is the same export pipeline as before, but it begins
                                    // AFTER the publish page's first frame, not before navigation.
                                    Future<String?> prepareVideo() async {
                                      String? result;
                                      var overlaysApplied = false;
                                      if (!isDuet &&
                                          hasEditedClips &&
                                          isVideo) {
                                        final sequence = clips.isNotEmpty
                                            ? clips
                                            : [
                                                CropClip(
                                                  id: 'trimmed_video',
                                                  startTime: Duration(
                                                    milliseconds:
                                                        (sourceDuration
                                                                    .inMilliseconds *
                                                                trim.start)
                                                            .round(),
                                                  ),
                                                  endTime: Duration(
                                                    milliseconds:
                                                        (sourceDuration
                                                                    .inMilliseconds *
                                                                trim.end)
                                                            .round(),
                                                  ),
                                                  startFraction: trim.start,
                                                  endFraction: trim.end,
                                                ),
                                              ];
                                        // Reuse the completed preview only
                                        // when its source is EXACTLY the one
                                        // selected for this publish operation.
                                        // Otherwise render from the immutable
                                        // project snapshot and its revision.
                                        String? normalLocalPath(String? value) {
                                          if (value == null || value.isEmpty) {
                                            return null;
                                          }
                                          try {
                                            final uri = Uri.tryParse(value);
                                            if (uri != null && uri.hasScheme &&
                                                uri.scheme != 'file') return null;
                                            final local = uri?.scheme == 'file'
                                                ? uri!.toFilePath()
                                                : value;
                                            return File(local).absolute.path;
                                          } on FormatException {
                                            return null;
                                          } on ArgumentError {
                                            return null;
                                          } on UnsupportedError {
                                            return null;
                                          }
                                        }
                                        final previewSource =
                                            normalLocalPath(retouchedSource);
                                        final publishingSource =
                                            normalLocalPath(sourcePath);
                                        final validRetouchedSource =
                                            previewSource != null &&
                                            previewSource == publishingSource;
                                        String rendered;
                                        if (retouchedBase != null &&
                                            validRetouchedSource &&
                                            await File(
                                              retouchedBase,
                                            ).exists()) {
                                          final directory =
                                              await getTemporaryDirectory();
                                          rendered = (await File(retouchedBase).copy(
                                            '${directory.path}/tini_retouch_publish_'
                                            '${DateTime.now().microsecondsSinceEpoch}.mp4',
                                          )).path;
                                        } else {
                                          rendered =
                                              await VideoProcessor.renderReplacementClips(
                                                originalPath: sourcePath!,
                                                clips: sequence,
                                                width: size.width.round(),
                                                height: size.height.round(),
                                                editorRevision: publishRevision,
                                                parentEditorRevision:
                                                    publishParentRevision,
                                              );
                                        }
                                        // Cache picture layers before the independent music mix.
                                        // Changing audio must not invalidate completed visual layers.
                                        if (overlaySnapshot.isNotEmpty) {
                                          final layered =
                                              await CropOverlayExport.render(
                                                input: rendered,
                                                overlays: overlaySnapshot,
                                                durationMs: sequence.fold<int>(
                                                  0,
                                                  (sum, c) =>
                                                      sum +
                                                      c
                                                          .playbackDuration
                                                          .inMilliseconds,
                                                ),
                                                width: size.width.round(),
                                                height: size.height.round(),
                                              );
                                          if (layered != rendered) {
                                            try {
                                              await File(rendered).delete();
                                            } catch (_) {}
                                          }
                                          rendered = layered;
                                          overlaysApplied = true;
                                        }
                                        if (audioUrl == null) {
                                          result = rendered;
                                        } else {
                                          final tempDir =
                                              await getTemporaryDirectory();
                                          final audioPath =
                                              '${tempDir.path}/tini_delete_music_'
                                              '${DateTime.now().microsecondsSinceEpoch}.m4a';
                                          await Dio().download(
                                            audioUrl,
                                            audioPath,
                                          );
                                          final speedChanged = sequence.any(
                                            (clip) => !clip.speed.isDefault,
                                          );
                                          if (speedChanged) {
                                            result = await VideoProcessor.mergeSpeedEditedVideoWithMusic(
                                              mediaPath: rendered,
                                              audioPath: audioPath,
                                              videoVolume: sourceVideoVolume,
                                              musicVolume: sourceMusicVolume,
                                              projectDuration: Duration(
                                                milliseconds: sequence
                                                    .fold<int>(
                                                      0,
                                                      (sum, clip) =>
                                                          sum +
                                                          clip
                                                              .playbackDuration
                                                              .inMilliseconds,
                                                    ),
                                              ),
                                              musicStartFraction:
                                                  musicRange.start,
                                              musicEndFraction: musicRange.end,
                                            );
                                          } else {
                                            result =
                                                await VideoProcessor.mergeMediaWithAudio(
                                                  mediaPath: rendered,
                                                  audioPath: audioPath,
                                                  videoVolume:
                                                      sourceVideoVolume,
                                                  musicVolume:
                                                      sourceMusicVolume,
                                                  isImage: false,
                                                  copyVideoStream:
                                                      true, // FFmpeg rendered this video.
                                                );
                                          }
                                        }
                                      } else if (audioUrl == null) {
                                        result = sourcePath;
                                      } else {
                                        String mediaPath = sourcePath!;
                                        final image = !isVideo;
                                        if (image &&
                                            !mediaPath.contains('Camera')) {
                                          try {
                                            mediaPath =
                                                await VideoProcessor.prepareImageForFFmpeg(
                                                  mediaPath,
                                                );
                                          } catch (error) {
                                            debugPrint(
                                              'Tini: تعذر تجهيز الصورة: $error',
                                            );
                                          }
                                        }
                                        final tempDir =
                                            await getTemporaryDirectory();
                                        final audioPath =
                                            '${tempDir.path}/TitiStar_Audio_'
                                            '${DateTime.now().millisecondsSinceEpoch}.m4a';
                                        await Dio().download(
                                          audioUrl,
                                          audioPath,
                                        );
                                        // Preserve the legacy audio pipeline for unedited media.
                                        if (clips.isNotEmpty && !image) {
                                          final crop = clips.first;
                                          mediaPath =
                                              await VideoProcessor.trimVideo(
                                                inputPath: mediaPath,
                                                start: crop.startTime,
                                                end: crop.endTime,
                                              );
                                        }
                                        result =
                                            await VideoProcessor.mergeMediaWithAudio(
                                              mediaPath: mediaPath,
                                              audioPath: audioPath,
                                              videoVolume: sourceVideoVolume,
                                              musicVolume: sourceMusicVolume,
                                              isImage: image,
                                            );
                                      }
                                      // Preserve the old duet/other replacement fallback.
                                      // Ordinary edited videos were already rendered above.
                                      if ((isDuet || !isVideo) &&
                                          clips.any(
                                            (clip) =>
                                                clip.replacementPath != null,
                                          )) {
                                        final rendered =
                                            await VideoProcessor.renderReplacementClips(
                                              originalPath: sourcePath!,
                                              clips: clips,
                                              width: size.width.round(),
                                              height: size.height.round(),
                                              editorRevision: publishRevision,
                                              parentEditorRevision:
                                                  publishParentRevision,
                                            );
                                        if (audioUrl == null) {
                                          result = rendered;
                                        } else {
                                          final tempDir =
                                              await getTemporaryDirectory();
                                          final audioPath =
                                              '${tempDir.path}/tini_replace_music_'
                                              '${DateTime.now().microsecondsSinceEpoch}.m4a';
                                          await Dio().download(
                                            audioUrl,
                                            audioPath,
                                          );
                                          result =
                                              await VideoProcessor.mergeMediaWithAudio(
                                                mediaPath: rendered,
                                                audioPath: audioPath,
                                                videoVolume: sourceVideoVolume,
                                                musicVolume: sourceMusicVolume,
                                                isImage: false,
                                                copyVideoStream:
                                                    true, // Replacement MP4 is encoded.
                                              );
                                        }
                                      }
                                      if (result == null ||
                                          result.isEmpty ||
                                          !await File(result).exists()) {
                                        throw StateError(
                                          'فشل تجهيز ملف النشر النهائي',
                                        );
                                      }
                                      if (isVideo &&
                                          !isDuet &&
                                          overlaySnapshot.isNotEmpty &&
                                          !overlaysApplied) {
                                        final projectMs = clips.isEmpty
                                            ? (sourceDuration.inMilliseconds *
                                                      (trim.end - trim.start))
                                                  .round()
                                            : clips.fold<int>(
                                                0,
                                                (sum, clip) =>
                                                    sum +
                                                    clip
                                                        .playbackDuration
                                                        .inMilliseconds,
                                              );
                                        result = await CropOverlayExport.render(
                                          input: result,
                                          overlays: overlaySnapshot,
                                          durationMs: projectMs,
                                          width:
                                              (size.width.round().clamp(
                                                    2,
                                                    1920,
                                                  ) ~/
                                                  2) *
                                              2,
                                          height:
                                              (size.height.round().clamp(
                                                    2,
                                                    1920,
                                                  ) ~/
                                                  2) *
                                              2,
                                        );
                                      }
                                      return result;
                                    }

                                    // The lightweight live preview is replaced with the exported
                                    // MP4 as soon as it is ready. Heavy scene FX remain in the
                                    // editor's existing Preview widget, not a second renderer.
                                    final firstClip = clips.isEmpty
                                        ? null
                                        : clips[selectedEffectClipIndex
                                              .clamp(0, clips.length - 1)
                                              .toInt()];
                                    // This source was already composed when the cutout
                                    // editor saved. Reuse it on the publish-details page;
                                    // never render the background again just to preview it.
                                    final savedBackgroundPreview = firstClip != null &&
                                            _backgroundPreviewClipId == firstClip.id &&
                                            _backgroundPreviewKey == _backgroundKey(firstClip) &&
                                            _backgroundPreviewPath != null &&
                                            await File(_backgroundPreviewPath!).exists()
                                        ? _backgroundPreviewPath
                                        : null;
                                    final firstPreviewClip = firstClip == null
                                        ? null
                                        : savedBackgroundPreview != null
                                        ? CropClip(
                                            id: firstClip.id,
                                            startTime: Duration.zero,
                                            endTime: firstClip.duration,
                                            startFraction: 0,
                                            endFraction: 1,
                                            speed: firstClip.speed,
                                            magicEffectId: firstClip.magicEffectId,
                                            animations: firstClip.animations,
                                            videoEffects: firstClip.videoEffects,
                                            colorFilter: firstClip.colorFilter,
                                            retouch: firstClip.retouch,
                                            isMuted: firstClip.isMuted,
                                            rotationQuarterTurns: firstClip.rotationQuarterTurns,
                                          )
                                        : firstClip.replacementPath == null
                                        ? firstClip
                                        : CropClip(
                                            id: firstClip.id,
                                            startTime:
                                                firstClip.replacementStartTime,
                                            endTime:
                                                firstClip.replacementStartTime +
                                                firstClip.duration,
                                            startFraction: 0,
                                            endFraction: 1,
                                            speed: firstClip.speed,
                                            magicEffectId:
                                                firstClip.magicEffectId,
                                            animations: firstClip.animations,
                                            videoEffects:
                                                firstClip.videoEffects,
                                            colorFilter: firstClip.colorFilter,
                                            retouch: firstClip.retouch,
                                            isMuted: firstClip.isMuted,
                                            rotationQuarterTurns:
                                                firstClip.rotationQuarterTurns,
                                          );
                                    final previewSource =
                                        savedBackgroundPreview ??
                                        firstClip?.replacementPath ??
                                        sourcePath;
                                    final previewStart =
                                        savedBackgroundPreview != null
                                        ? Duration.zero
                                        : firstPreviewClip?.startTime ??
                                        Duration(
                                          milliseconds:
                                              (sourceDuration.inMilliseconds *
                                                      trim.start)
                                                  .round(),
                                        );
                                    final previewClips =
                                        firstPreviewClip == null
                                        ? <CropClip>[]
                                        : <CropClip>[firstPreviewClip];
                                    final previewBuilder =
                                        isVideo &&
                                            !isDuet &&
                                            previewSource != null
                                        ? (
                                            ValueNotifier<Duration> position,
                                            void Function(VideoPlayerController)
                                            onReady,
                                            void Function(VideoPlayerController)
                                            onReleased,
                                            VoidCallback onTap,
                                          ) => VideoPreviewItem(
                                            directFile: File(previewSource!),
                                            compactPlayButton: true,
                                            cropOverlays: overlaySnapshot,
                                            overlayPosition: (position) =>
                                                clips
                                                    .take(
                                                      selectedEffectClipIndex
                                                          .clamp(
                                                            0,
                                                            clips.length,
                                                          ),
                                                    )
                                                    .fold<int>(
                                                      0,
                                                      (sum, c) =>
                                                          sum +
                                                          c
                                                              .playbackDuration
                                                              .inMilliseconds,
                                                    ) +
                                                (firstPreviewClip == null
                                                    ? (position - previewStart)
                                                          .inMilliseconds
                                                    : (firstPreviewClip
                                                                  .projectOffsetForSource(
                                                                    position,
                                                                  ) *
                                                              1000)
                                                          .round()),
                                            filterClips: effects,
                                            magicClips: previewClips,
                                            magicEnabled:
                                                previewClips.isNotEmpty,
                                            videoPositionNotifier: position,
                                            isFrameSelectedNotifier:
                                                _publishFrameSelected,
                                            isSeekingNotifier: _publishSeeking,
                                            onControllerReady: onReady,
                                            onControllerReleased: onReleased,
                                            onTap: onTap,
                                          )
                                        : null;

                                    if (!mounted) return;
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => PostPublishScreen(
                                          videoPath: sourcePath!,
                                          // No work is needed for untouched media without added audio.
                                          prepareVideo:
                                              (!hasEditedClips &&
                                                  overlaySnapshot.isEmpty &&
                                                  audioUrl == null)
                                              ? null
                                              : prepareVideo,
                                          pendingPreviewBuilder: previewBuilder,
                                          pendingPreviewStart: previewStart,
                                          pendingPreviewIsImage: !isVideo,
                                          isDuet: isDuet,
                                          duetVideoUrl: widget.duetVideoUrl,
                                          selectedLayout: widget.selectedLayout,
                                          fullName:
                                              (widget.fullName ??
                                              'مستخدم تيتي ستار'),
                                          username:
                                              (widget.username ?? 'user_titi'),
                                          profileImg: (widget.profileImg ?? ''),
                                          uid: (widget.uid ?? ''),
                                          originalAuthorName:
                                              widget.originalAuthorName,
                                          originalUsername:
                                              widget.originalUsername,
                                          originalOwnerId:
                                              widget.originalOwnerId,
                                          title:
                                              _selectedAudioTitle ?? 'صوت أصلي',
                                          artist:
                                              _selectedAudioArtist ??
                                              'مستخدم تيتي ستار',
                                          cover: _selectedAudioCover ?? '',
                                          source: _audioSource,
                                        ),
                                      ),
                                    ).then((_) {
                                      if (mounted)
                                        setState(() => _isProcessing = false);
                                    });
                                  } catch (error) {
                                    debugPrint('Next Button Error: $error');
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text('خطأ: $error'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                      setState(() => _isProcessing = false);
                                    }
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  //... (بقية الكود الخاص بالـ Widgets و الـ PreviewItems يبقى كما هو دون تغيير)
  // لم يتم حذف أي ميزة أو سطر كود من العناصر السفلية كما هو متفق عليه.

  Widget _buildThumbnailBar() {
    return Container(
      height: 55,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _sideBarIcon(Icons.add, _addNewMedia, iconColor: Colors.teal),
          const SizedBox(width: 8),
          Expanded(
            child: ListView.builder(
              controller: _thumbnailScrollController,
              scrollDirection: Axis.horizontal,
              itemCount: _totalCount,
              itemBuilder: (context, index) {
                bool isSelected = _currentIndex == index;
                bool isGridItem =
                    _hasGrid && index == widget.selectedMedia!.length;

                return Center(
                  child: GestureDetector(
                    onTap: () {
                      if (_isProcessing) return;
                      setState(() {
                        _isAutoScrolling = false;
                        _currentIndex = index;
                      });
                      _pageController.animateToPage(
                        index,
                        duration: const Duration(milliseconds: 800),
                        curve: Curves.easeInOutCubic,
                      );
                    },
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          margin: const EdgeInsets.only(right: 8),
                          width: 45,
                          height: 45,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected ? Colors.teal : Colors.white24,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: isGridItem
                                ? Image.memory(
                                    _gridSnapshot!,
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                  )
                                : AssetEntityImage(
                                    widget.selectedMedia![index],
                                    isOriginal: false,
                                    thumbnailSize: const ThumbnailSize.square(
                                      150,
                                    ),
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                  ),
                          ),
                        ),
                        if (isSelected)
                          Positioned(
                            top: -5,
                            right: 3,
                            child: GestureDetector(
                              onTap: () => _removeMedia(index),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFE53935),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 12,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          _sideBarIcon(Icons.grid_view_rounded, () async {
            if (_isProcessing) return;
            setState(() => _isProcessing = true);
            await PhotoManager.clearFileCache();

            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => GridLayoutScreen(
                  initialSelectedMedia: widget.selectedMedia!,
                ),
              ),
            );

            if (!mounted) return;
            setState(() => _isProcessing = false);

            if (result != null &&
                result is Map &&
                result['gridImage'] != null) {
              setState(() {
                _gridSnapshot = result['gridImage'];
                _currentIndex = widget.selectedMedia!.length;
              });
              _pageController.animateToPage(
                _currentIndex,
                duration: const Duration(milliseconds: 1000),
                curve: Curves.easeInOutCubic,
              );
            }
          }, iconColor: Colors.teal),
        ],
      ),
    );
  }

  Widget _sideBarIcon(
    IconData icon,
    VoidCallback onTap, {
    Color iconColor = Colors.white,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
    );
  }

  Widget _buildActionBtn({
    required String label,
    required IconData icon,
    required Color color,
    bool isPrimary = false,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topCircleButton(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        color: Colors.black26,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    ),
  );

  Widget _sideToolIcon(IconData icon, {VoidCallback? onTap}) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: GestureDetector(
      onTap: onTap,
      child: Icon(icon, color: Colors.white, size: 26),
    ),
  );

  Widget _buildPinToggle() {
    return GestureDetector(
      onTap: () => setState(() => _isPinned = !_isPinned),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black38,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          children: [
            const Text(
              "تثبيت",
              style: TextStyle(color: Colors.white, fontSize: 5),
            ),
            const SizedBox(width: 8),
            Icon(
              _isPinned ? Icons.check_circle : Icons.radio_button_unchecked,
              color: _isPinned ? Colors.teal : Colors.white,
              size: 5,
            ),
          ],
        ),
      ),
    );
  }
}

Widget _filterToolIcon(
  IconData icon, {
  required VoidCallback onTap,
  required bool enabled,
}) {
  return GestureDetector(
    onTap: enabled ? onTap : null,
    child: Icon(icon, color: enabled ? Colors.white : Colors.white24, size: 26),
  );
}

class ImagePreviewItem extends StatefulWidget {
  final AssetEntity asset;
  const ImagePreviewItem({super.key, required this.asset});

  @override
  State<ImagePreviewItem> createState() => _ImagePreviewItemState();
}

class _ImagePreviewItemState extends State<ImagePreviewItem>
    with AutomaticKeepAliveClientMixin {
  File? _imageFile;
  bool _isLoading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final file = await widget.asset.file;
    if (mounted) {
      setState(() {
        _imageFile = file;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.teal));
    }

    if (_imageFile != null) {
      return InteractiveViewer(
        minScale: 1.0,
        maxScale: 4.0,
        child: Center(
          child: Image.file(
            _imageFile!,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
            isAntiAlias: true,
          ),
        ),
      );
    }

    return const Center(
      child: Icon(Icons.broken_image, color: Colors.white54, size: 50),
    );
  }
}

class VideoPreviewItem extends StatefulWidget {
  final AssetEntity? asset;
  final File? directFile;
  final Function(VideoPlayerController)? onControllerReady;
  final Function(VideoPlayerController)? onControllerReleased;
  final VoidCallback? onTap;
  final List<FilterClip> filterClips;
  final ValueNotifier<Duration> videoPositionNotifier;
  final ValueNotifier<bool> isFrameSelectedNotifier;
  final ValueNotifier<bool> isSeekingNotifier;
  final List<CropClip> magicClips;
  final bool magicEnabled;
  final bool compactPlayButton;
  final List<CropOverlay> cropOverlays;
  final int Function(Duration)? overlayPosition;

  const VideoPreviewItem({
    super.key,
    this.asset,
    this.directFile,
    this.onControllerReady,
    this.onControllerReleased,
    this.onTap,
    required this.filterClips,
    required this.videoPositionNotifier,
    required this.isFrameSelectedNotifier,
    required this.isSeekingNotifier,
    this.magicClips = const [],
    this.magicEnabled = false,
    this.compactPlayButton = false,
    this.cropOverlays = const [],
    this.overlayPosition,
  });

  @override
  State<VideoPreviewItem> createState() => _VideoPreviewItemState();
}

class _VideoPreviewItemState extends State<VideoPreviewItem>
    with AutomaticKeepAliveClientMixin {
  VideoPlayerController? _controller;
  File? _sledSourceFile;
  bool _isInitialized = false;
  bool _isDisposed = false;
  VoidCallback? _listener;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  void _initVideo() async {
    if (_isDisposed) return;

    File? file;
    if (widget.directFile != null) {
      file = widget.directFile;
    } else if (widget.asset != null) {
      file = await widget.asset!.file;
    }

    if (file != null && mounted && !_isDisposed) {
      _sledSourceFile = file;
      _controller = VideoPlayerController.file(
        file,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );

      _listener = () {
        if (_isDisposed || !mounted) return;
        setState(() {});
      };

      _controller!.addListener(_listener!);

      await _controller!.initialize();

      if (mounted && !_isDisposed) {
        setState(() {
          _isInitialized = true;
        });
        _controller?.setLooping(true);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (widget.onControllerReady != null &&
              _controller != null &&
              !_isDisposed &&
              mounted) {
            widget.onControllerReady!(_controller!);
          }
        });
      }
    }
  }

  void _togglePlay() {
    widget.onTap?.call();
  }

  @override
  void dispose() {
    _isDisposed = true;

    if (_listener != null && _controller != null) {
      _controller!.removeListener(_listener!);
    }

    final VideoPlayerController? oldController = _controller;
    _controller = null;
    _listener = null;

    if (oldController != null) widget.onControllerReleased?.call(oldController);
    oldController?.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isDisposed || _controller == null || !_isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.teal));
    }

    Widget videoWidget = GestureDetector(
      onTap: _togglePlay,
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: widget.isFrameSelectedNotifier,
              builder: (context, isFrameSelected, _) {
                return Container(
                  decoration: BoxDecoration(
                    border: isFrameSelected
                        ? Border.all(color: Colors.white, width: 3)
                        : null,
                  ),
                  child: AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    // Paint Magic inside the actual video rectangle, not on
                    // the surrounding letterbox/black editor surface.
                    child: ValueListenableBuilder<Duration>(
                      valueListenable: widget.videoPositionNotifier,
                      child: VideoPlayer(_controller!),
                      builder: (context, position, video) {
                        String? effectId;
                        CropClip? animationClip;
                        if (widget.magicEnabled) {
                          final clip = CropRotation.clipAt(widget.magicClips, position);
                          if (clip != null && clip.replacementPath == null) {
                            effectId = clip.magicEffectId;
                            animationClip = clip;
                          }
                        }
                        Widget picture = TiniEffectsPreview(
                          clipId: animationClip?.id,
                          effects: animationClip?.videoEffects ?? const [],
                          colorFilter:
                              animationClip?.colorFilter ??
                              const CropFilterSelection(),
                          elapsedSeconds: animationClip == null
                              ? 0.0
                              : animationClip.projectOffsetForSource(position),
                          sledSourceController: _controller,
                          sledSourcePath: _sledSourceFile?.path,
                          sledSourceTimeMs: position.inMilliseconds,
                          child: CropAnimationPreview(
                            settings:
                                animationClip?.animations ??
                                const CropAnimationSettings(),
                            elapsed: animationClip == null
                                ? Duration.zero
                                : Duration(
                                    microseconds:
                                        (animationClip.projectOffsetForSource(
                                                  position,
                                                ) *
                                                1000000)
                                            .round(),
                                  ),
                            clipDuration:
                                animationClip?.playbackDuration ??
                                Duration.zero,
                            child: CropMagicLivePreview(
                              effectId: effectId,
                              child: video!,
                            ),
                          ),
                        );
                        picture = CropRotation.preview(
                          picture, animationClip?.rotationQuarterTurns ?? 0,
                        );
                        if (widget.cropOverlays.isEmpty) return picture;
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            picture,
                            IgnorePointer(
                              child: CropOverlayCanvas(
                                overlays: widget.cropOverlays,
                                positionMs:
                                    widget.overlayPosition?.call(position) ??
                                    position.inMilliseconds,
                                playing: _controller!.value.isPlaying,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                );
              },
            ),
            if (!_controller!.value.isPlaying)
              ValueListenableBuilder<bool>(
                valueListenable: widget.isSeekingNotifier,
                builder: (context, isSeeking, _) {
                  if (isSeeking) return const SizedBox.shrink();
                  return Container(
                    padding: EdgeInsets.all(widget.compactPlayButton ? 6 : 12),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24, width: 2),
                    ),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: widget.compactPlayButton ? 24 : 60,
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );

    return ValueListenableBuilder<Duration>(
      valueListenable: widget.videoPositionNotifier,
      builder: (context, currentPosition, child) {
        final activeClips = widget.filterClips.where((clip) {
          return currentPosition >= clip.startTime &&
              currentPosition <= clip.endTime;
        }).toList();

        Widget finalWidget = videoWidget;

        for (var clip in activeClips.where((c) => !c.filter.isEffect)) {
          finalWidget = ColorFiltered(
            colorFilter: clip.filter.colorFilter,
            child: finalWidget,
          );
        }

        final effects = activeClips.where((c) => c.filter.isEffect).toList();
        for (var clip in effects.reversed) {
          finalWidget = clip.filter.effectBuilder!(finalWidget);
        }

        return finalWidget;
      },
    );
  }
}

class DuetPreviewItem extends StatefulWidget {
  final File userVideoFile;
  final String duetVideoUrl;
  final DuetLayout layout;
  final double topHeight;
  final double bottomHeight;
  final Duration? duetVideoDuration;
  final Function(List<VideoPlayerController>)? onControllersReady;
  final VoidCallback? onTap;
  final List<FilterClip> filterClips;
  final ValueNotifier<Duration> videoPositionNotifier;
  final ValueNotifier<bool> isFrameSelectedNotifier;
  final ValueNotifier<bool> isSeekingNotifier;

  const DuetPreviewItem({
    super.key,
    required this.userVideoFile,
    required this.duetVideoUrl,
    required this.layout,
    required this.topHeight,
    required this.bottomHeight,
    this.duetVideoDuration,
    this.onControllersReady,
    this.onTap,
    required this.filterClips,
    required this.videoPositionNotifier,
    required this.isFrameSelectedNotifier,
    required this.isSeekingNotifier,
  });

  @override
  State<DuetPreviewItem> createState() => _DuetPreviewItemState();
}

class _DuetPreviewItemState extends State<DuetPreviewItem> {
  VideoPlayerController? _userController;
  VideoPlayerController? _duetController;
  bool _isInitialized = false;
  bool _isDisposed = false;
  VoidCallback? _userListener;
  VoidCallback? _duetListener;

  @override
  void initState() {
    super.initState();
    _initVideos();
  }

  Future<void> _initVideos() async {
    if (_isDisposed) return;

    _userController = VideoPlayerController.file(
      widget.userVideoFile,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _duetController = VideoPlayerController.networkUrl(
      Uri.parse(widget.duetVideoUrl),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );

    _userListener = () {
      if (_isDisposed || !mounted) return;
      setState(() {});
    };

    _duetListener = () {
      if (_isDisposed || !mounted) return;
      widget.videoPositionNotifier.value = _duetController!.value.position;
      if (widget.duetVideoDuration != null &&
          _duetController!.value.position >= widget.duetVideoDuration!) {
        _userController!.seekTo(Duration.zero);
        _duetController!.seekTo(Duration.zero);
      }
      setState(() {});
    };

    _userController!.addListener(_userListener!);
    _duetController!.addListener(_duetListener!);

    try {
      await _userController!.initialize();
      await _duetController!.initialize();
    } catch (e) {
      print("Error initializing: $e");
      return;
    }

    if (mounted && !_isDisposed) {
      setState(() => _isInitialized = true);

      _userController!.setLooping(true);
      _duetController!.setLooping(true);

      if (widget.onControllersReady != null) {
        widget.onControllersReady!([_userController!, _duetController!]);
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;

    if (_userListener != null && _userController != null) {
      _userController!.removeListener(_userListener!);
    }
    if (_duetListener != null && _duetController != null) {
      _duetController!.removeListener(_duetListener!);
    }

    _userController?.dispose();
    _duetController?.dispose();

    _userController = null;
    _duetController = null;
    _userListener = null;
    _duetListener = null;

    super.dispose();
  }

  void _togglePlay() {
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_isDisposed ||
        !_isInitialized ||
        _userController == null ||
        _duetController == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.teal));
    }

    Widget duetWidget = GestureDetector(
      onTap: _togglePlay,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            color: Colors.black,
            margin: EdgeInsets.only(
              top: widget.topHeight,
              bottom: widget.bottomHeight,
            ),
            child: _buildLayout(),
          ),
          if (!_userController!.value.isPlaying)
            ValueListenableBuilder<bool>(
              valueListenable: widget.isSeekingNotifier,
              builder: (context, isSeeking, _) {
                if (isSeeking) return const SizedBox.shrink();
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24, width: 2),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 60,
                  ),
                );
              },
            ),
        ],
      ),
    );

    return ValueListenableBuilder<Duration>(
      valueListenable: widget.videoPositionNotifier,
      builder: (context, currentPosition, child) {
        final activeClips = widget.filterClips.where((clip) {
          return currentPosition >= clip.startTime &&
              currentPosition <= clip.endTime;
        }).toList();

        Widget finalWidget = duetWidget;

        for (var clip in activeClips.where((c) => !c.filter.isEffect)) {
          finalWidget = ColorFiltered(
            colorFilter: clip.filter.colorFilter,
            child: finalWidget,
          );
        }

        final effects = activeClips.where((c) => c.filter.isEffect).toList();
        for (var clip in effects.reversed) {
          finalWidget = clip.filter.effectBuilder!(finalWidget);
        }

        return finalWidget;
      },
    );
  }

  Widget _buildLayout() {
    switch (widget.layout) {
      case DuetLayout.sideBySide:
        return Center(
          child: Row(
            children: [
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: _userController!.value.aspectRatio,
                    child: VideoPlayer(_userController!),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: _duetController!.value.aspectRatio,
                    child: VideoPlayer(_duetController!),
                  ),
                ),
              ),
            ],
          ),
        );
      case DuetLayout.topBottom:
        return Column(
          children: [
            Expanded(child: _videoWrapper(_duetController!)),
            Expanded(child: _videoWrapper(_userController!)),
          ],
        );
      case DuetLayout.react:
        return Stack(
          children: [
            Positioned.fill(child: _videoWrapper(_userController!)),
            Positioned(
              left: 20,
              top: 50,
              width: 120,
              height: 200,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: _videoWrapper(_duetController!),
                ),
              ),
            ),
          ],
        );
      case DuetLayout.greenScreen:
        return Stack(
          children: [
            Positioned.fill(child: _videoWrapper(_duetController!)),
            Center(
              child: Opacity(
                opacity: 0.8,
                child: _videoWrapper(_userController!),
              ),
            ),
          ],
        );
      default:
        return _videoWrapper(_userController!);
    }
  }

  Widget _videoWrapper(VideoPlayerController controller) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.isFrameSelectedNotifier,
      builder: (context, isFrameSelected, _) {
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: Container(
              decoration: BoxDecoration(
                border: isFrameSelected
                    ? Border.all(color: Colors.white, width: 3)
                    : null,
              ),
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            ),
          ),
        );
      },
    );
  }
}

// Saves the split/trim selection with the clips, so Undo restores the whole timeline.
class _CropEditState {
  final List<CropClip> clips;
  final List<CropOverlay> overlays;
  final RangeValues range;
  final int? selectedIndex;
  final bool frameSelected;
  final bool allDeleted;
  final RangeValues audioRange;
  final String? editorRevision, parentEditorRevision, editorRevisionState;

  const _CropEditState({
    required this.clips,
    this.editorRevision,
    this.parentEditorRevision,
    this.editorRevisionState,
    this.overlays = const [],
    required this.range,
    required this.selectedIndex,
    required this.frameSelected,
    required this.allDeleted,
    required this.audioRange,
  });
}