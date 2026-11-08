import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart' as titi_video;
import 'media_picker_screen.dart';
import 'media_preview_screen.dart';
import 'dart:io';
import 'dart:async';
import 'package:video_trimmer/video_trimmer.dart';
import 'package:audio_session/audio_session.dart';
import 'auth_provider.dart' as custom;
import 'package:provider/provider.dart';
import 'video_processor.dart';
import 'music_library_sheet.dart';
import 'package:audioplayers/audioplayers.dart' hide AVAudioSessionCategory, AVAudioSessionCategoryOptions;

class CreatePostScreen extends StatefulWidget {
  final String? duetVideoUrl;
  final bool isDuet;
  final String? videoPath;
  final String? originalAuthorName;
  final String? originalUsername;
  final DuetLayout selectedLayout;
  final String? originalOwnerId; // <-- جديد

  const CreatePostScreen({
    super.key,
    this.duetVideoUrl,
    this.isDuet = false,
    this.videoPath,
    this.originalAuthorName,
    this.originalUsername,
    required this.selectedLayout,
    this.originalOwnerId, // <-- جديد
  });

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  late PageController _pageController;
  int _currentPage = 0;
  final List<String> _tabs = ["منشور", "الإبداع", "LIVE"];
  final ValueNotifier<String> audioTitleNotifier = ValueNotifier<String>("إضافة صوت");

  DuetLayout _currentLayout = DuetLayout.sideBySide;
  bool _isSegmentationEnabled = false;

  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isInitializing = false;
  bool _hasScrolledInThisGesture = false;
  int _selectedCameraIndex = 0;

  final Trimmer _trimmer = Trimmer();
  bool _isTrimmerInitialized = false;

  late final Player _player;
  late final titi_video.VideoController _videoController;
  bool _isMediaKitInitialized = false;
  bool _isProcessing = false;
  double _previewOpacity = 0.0;

  bool _isRecording = false;
  Timer? _recordingTimer;
  Duration _currentDuration = Duration.zero;
  Duration _maxDuration = const Duration(seconds: 30);
  double _progressPercent = 0.0;
  List<String> _videoSegments = [];

  String? _selectedAudioUrl;
  String? _selectedAudioTitle;
  String? _selectedAudioArtist;
  final AudioPlayer _audioPlayer = AudioPlayer();

  double _startValue = 0.0;
  double _endValue = 0.0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _checkPermissionAndInit();
  }

  Future<void> _prepareAudio(String url) async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.setSource(UrlSource(url));
      await _audioPlayer.pause();
    } catch (e) {
      debugPrint("خطأ في تجهيز الصوت: $e");
    }
  }

  Future<void> _configureAudioSession() async {
    if (!widget.isDuet) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.defaultToSpeaker |
                                       AVAudioSessionCategoryOptions.allowBluetooth |
                                       AVAudioSessionCategoryOptions.mixWithOthers,
        avAudioSessionMode: AVAudioSessionMode.measurement,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      ));
      await session.setActive(true);
    } catch (e) {
      debugPrint("Tini Audio Session Error: $e");
    }
  }

  Future<void> _initializeMediaKit() async {
    try {
      _player = Player();
      _videoController = titi_video.VideoController(
        _player,
        configuration: const titi_video.VideoControllerConfiguration(),
      );

      await _player.open(Media(widget.duetVideoUrl!), play: false);

      _player.stream.duration.listen((duration) {
        if (mounted && duration.inMilliseconds > 0) {
          setState(() {
            _maxDuration = duration;
          });
        }
      });

      if (mounted) {
        setState(() {
          _isMediaKitInitialized = true;
        });
      }
    } catch (e) {
      debugPrint("Tini Error (MediaKit): $e");
    }
  }

  Future<void> _checkPermissionAndInit() async {
    var status = await Permission.camera.status;
    var micStatus = await Permission.microphone.status;

    if (status.isGranted && micStatus.isGranted) {
      if (widget.isDuet) {
        await _configureAudioSession();
        await _initializeMediaKit();
      }
      await _initializeCamera();
    } else {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.camera,
        Permission.microphone,
      ].request();

      if (statuses[Permission.camera]!.isGranted) {
        if (widget.isDuet) {
          await _configureAudioSession();
          await _initializeMediaKit();
        }
        await _initializeCamera();
      }
    }
  }

  Future<void> _initializeCamera() async {
    if (_isInitializing ||!mounted) return;
    _isInitializing = true;

    try {
      _cameras = await availableCameras();
      if (!mounted || _cameras == null || _cameras!.isEmpty) return;

      if (_cameraController!= null) {
        await _cameraController!.dispose();
        _cameraController = null;
      }

      CameraDescription selectedCamera = _cameras![_selectedCameraIndex];

      if (widget.isDuet && _cameraController == null && _selectedCameraIndex == 0) {
        for (int i = 0; i < _cameras!.length; i++) {
          if (_cameras![i].lensDirection == CameraLensDirection.front) {
            _selectedCameraIndex = i;
            selectedCamera = _cameras![i];
            break;
          }
        }
      }

      _cameraController = CameraController(
        selectedCamera,
        ResolutionPreset.high,
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();

      if (!mounted) return;

      setState(() {
        _isCameraInitialized = true;
      });

      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        setState(() => _previewOpacity = 1.0);
      }
    } catch (e) {
      debugPrint("خطأ في الكاميرا: $e");
    } finally {
      if (mounted) _isInitializing = false;
    }
  }

  Future<void> _toggleCamera() async {
    if (_cameras == null || _cameras!.isEmpty || _isInitializing) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras!.length;
    await _initializeCamera();
  }

  void _disposeCamera() {
    if (_cameraController!= null) {
      _isCameraInitialized = false;
      _previewOpacity = 0.0;
      _cameraController!.dispose();
      _cameraController = null;
    }
    if (widget.isDuet && _isMediaKitInitialized) {
      _player.dispose();
    }
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _audioPlayer.dispose(); // مهم: وقف الموسيقى
    _trimmer.dispose(); // مهم: نظف الـ trimmer
    _disposeCamera();
    _pageController.dispose();
    audioTitleNotifier.dispose();
    super.dispose();
  }

  Future<void> _onRecordHoldStart() async {
    if (_isProcessing || _cameraController == null ||!_cameraController!.value.isInitialized) return;
    if (_currentDuration >= _maxDuration) return;

    try {
      if (widget.isDuet) {
        final session = await AudioSession.instance;
        await session.setActive(true);
      }

      if (_selectedAudioUrl!= null &&!widget.isDuet) {
        await _audioPlayer.seek(Duration.zero);
        await _audioPlayer.resume();
      }

      await _cameraController!.startVideoRecording();

      if (widget.isDuet && _isMediaKitInitialized) {
        Future.delayed(const Duration(milliseconds: 100), () {
          _player.play();
        });
      }

      setState(() {
        _isRecording = true;
      });

      _recordingTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          _currentDuration += const Duration(milliseconds: 50);
          _progressPercent = _currentDuration.inMilliseconds / _maxDuration.inMilliseconds;

          if (_currentDuration >= _maxDuration) {
            _onRecordHoldEnd();
          }
        });
      });
    } catch (e) {
      debugPrint("Tini Hold Start Error: $e");
    }
  }

  Future<void> _onRecordHoldEnd() async {
    if (!_isRecording || _cameraController == null) return;
    _recordingTimer?.cancel();

    try {
      if (widget.isDuet && _isMediaKitInitialized) {
        _player.pause();
      }

      if (_selectedAudioUrl!= null &&!widget.isDuet) {
        await _audioPlayer.pause();
      }

      final XFile segment = await _cameraController!.stopVideoRecording();
      _videoSegments.add(segment.path);

      if (mounted) {
        setState(() {
          _isRecording = false;
        });
      }

      await _trimmer.loadVideo(videoFile: File(segment.path));

      if (mounted) {
        setState(() {
          _isTrimmerInitialized = true;
          _startValue = 0.0;
          _endValue = _currentDuration.inMilliseconds.toDouble();
        });
      }
    } catch (e) {
      debugPrint("Tini Hold End Error: $e");
    }
  }

  void _resetRecording() async {
    // 1. وقف كل شي فوراً
    _recordingTimer?.cancel();
    await _audioPlayer.stop();
    await _cameraController?.dispose();
    _cameraController = null;

    // 2. صفر الواجهة فوراً عشان ما تجمد
    if (mounted) {
      setState(() {
        _videoSegments.clear();
        _currentDuration = Duration.zero;
        _progressPercent = 0.0;
        _isRecording = false;
        _isTrimmerInitialized = false;
        _isCameraInitialized = false;
        _previewOpacity = 0.0;
      });
    }

    // 3. احذف الملفات بالخلفية بدون await
    for (var path in _videoSegments) {
      File(path).delete().catchError((_) {});
    }

    // 4. نظف الـ trimmer
    _trimmer.videoPlayerController?.dispose();

    // 5. شغل الكاميرا من جديد
    await _initializeCamera();
  }

  Future<void> _processAndFinalizeVideo() async {
    if (_isProcessing) return;

    // مهم: وقف الموسيقى قبل القص عشان ما يصير تعارض
    await _audioPlayer.stop();

    if (_cameraController!= null) {
      if (_cameraController!.value.isRecordingVideo) {
        await _cameraController!.stopVideoRecording();
      }
      await _cameraController!.dispose();
      _cameraController = null;
    }

    if (mounted) setState(() => _isProcessing = true);

    await Future.delayed(const Duration(milliseconds: 1500));

    if (_videoSegments.isEmpty) {
      if (mounted) setState(() => _isProcessing = false);
      return;
    }

    String rawPath = _videoSegments.last;

    // إذا المستخدم ما حرك المسطرة، ابعت الفيديو الأصلي بدون قص
    if (_startValue == 0 && _endValue >= _currentDuration.inMilliseconds - 10) {
      _navigateToPreview(rawPath);
      return;
    }

    try {
      final double currentStopPos = _trimmer.videoPlayerController?.value.position.inMilliseconds.toDouble()?? _endValue;

      await _trimmer.saveTrimmedVideo(
        startValue: _startValue,
        endValue: currentStopPos,
        onSave: (String? outputPath) async {
          bool isFileValid = false;
          if (outputPath!= null && outputPath.isNotEmpty) {
            final file = File(outputPath);
            if (await file.exists() && await file.length() > 100 * 1024) {
              isFileValid = true;
            }
          }

          String finalPath = isFileValid? outputPath! : rawPath;
          _navigateToPreview(finalPath);
        },
      );
    } catch (e) {
      debugPrint("Tini System Recovery: $e");
      _navigateToPreview(rawPath);
    }
  }

    void _navigateToPreview(String path) {
    if (!mounted) return;

    final auth = Provider.of<custom.AuthProvider>(context, listen: false);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MediaPreviewScreen(
          videoFile: File(path),
          fullName: auth.fullName,
          username: auth.username,
          profileImg: auth.profileImg,
          uid: auth.uid,
          originalAuthorName: widget.originalAuthorName,
          originalUsername: widget.originalUsername,
          originalOwnerId: widget.originalOwnerId, // <-- تمرير
          isDuet: widget.isDuet,
          duetVideoUrl: widget.duetVideoUrl,
          selectedLayout: _currentLayout,
          duetVideoDuration: _currentDuration,
        ),
      ),
    ).then((_) {
      if (mounted) setState(() => _isProcessing = false);
    });
  }

  void _handleSwipe(DragUpdateDetails details) {
    if (_hasScrolledInThisGesture || widget.isDuet) return;

    if (details.delta.dx < -10 && _currentPage < _tabs.length - 1) {
      _hasScrolledInThisGesture = true;
      _onTabTap(_currentPage + 1);
    } else if (details.delta.dx > 10 && _currentPage > 0) {
      _hasScrolledInThisGesture = true;
      _onTabTap(_currentPage - 1);
    }
  }

  void _onTabTap(int index) async {
    if (_currentPage == index ||!mounted || _isProcessing || widget.isDuet) return;

    setState(() {
      _currentPage = index;
      if (index!= 0) _previewOpacity = 0.0;
    });

    if (index == 0) {
      await _initializeCamera();
    } else {
      _disposeCamera();
    }

    if (mounted) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _toggleLayout() {
    setState(() {
      int nextIndex = (_currentLayout.index + 1) % DuetLayout.values.length;
      _currentLayout = DuetLayout.values[nextIndex];
    });
  }

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double topBarHeight = screenHeight * 0.032;
    final double bottomBarHeight = screenHeight * 0.139;
    String timerText = "${_currentDuration.inMinutes.toString().padLeft(2, '0')}:${(_currentDuration.inSeconds % 60).toString().padLeft(2, '0')}";

    return Scaffold(
      backgroundColor: const Color(0xFF0F1720),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            height: topBarHeight,
            color: Colors.teal,
            child: const SizedBox.shrink(),
          ),

          Expanded(
            child: GestureDetector(
              onPanStart: (_) => _hasScrolledInThisGesture = false,
              onPanUpdate: _handleSwipe,
              child: PageView.builder(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _tabs.length,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Container(
                      color: const Color(0xFF0F1720),
                      child: Stack(
                        children: [
                          if (_isCameraInitialized && _cameraController!= null)
                            Positioned.fill(
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 400),
                                opacity: _previewOpacity,
                                child: widget.isDuet
                                 ? _buildFlexibleDuetView()
                                  : _buildNormalCameraView(),
                              ),
                            ),

                          if (!_isRecording)
                            Positioned(
                              top: 20,
                              left: 10,
                              child: GestureDetector(
                                onTap: () => Navigator.maybePop(context),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close, color: Colors.white, size: 22),
                                ),
                              ),
                            ),
if (!_isRecording &&!widget.isDuet)
  Positioned(
    top: 20,
    left: 0,
    right: 0,
    child: Center(
      child: GestureDetector(
        onTap: () {
  showMusicSheet(
    context: context,
    onTrackSelected: (Map<String, dynamic> selectedTrack) {
      final String? newUrl = selectedTrack['url']?? selectedTrack['streamUrl'];
      final String newTitle = selectedTrack['title']?? selectedTrack['name']?? "إضافة صوت";

      _selectedAudioUrl = newUrl;
      _selectedAudioTitle = newTitle;
      _selectedAudioArtist = selectedTrack['artist']?? selectedTrack['uploader'];

      audioTitleNotifier.value = newTitle;

      if (newUrl!= null) {
        _prepareAudio(newUrl);
      }
    },
  );
},
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.60,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.music_note, color: Colors.white, size: 18),
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

                          if (_currentPage == 0)
                            Positioned(
                              bottom: 15,
                              left: 0,
                              right: 0,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (widget.isDuet &&!_isRecording)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 15),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          _buildSideAction(Icons.dashboard_customize, "تنسيق", _toggleLayout),
                                          const SizedBox(width: 40),
                                          _buildSideAction(Icons.flip_camera_ios, "قلب", _toggleCamera),
                                        ],
                                      ),
                                    ),

                                  if (_isTrimmerInitialized &&!widget.isDuet &&!_isRecording && _videoSegments.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                      child: Column(
                                        children: [
                                          TrimViewer(
                                            trimmer: _trimmer,
                                            viewerHeight: 50.0,
                                            viewerWidth: MediaQuery.of(context).size.width,
                                            maxVideoLength: Duration(milliseconds: _currentDuration.inMilliseconds),
                                            onChangeStart: (value) => _startValue = value,
                                            onChangeEnd: (value) => _endValue = value,
                                            onChangePlaybackState: (value) {},
                                            editorProperties: TrimEditorProperties(
                                              borderPaintColor: Colors.teal,
                                              circlePaintColor: Colors.teal,
                                              circleSize: 6.0,
                                              borderWidth: 2,
                                            ),
                                            areaProperties: TrimAreaProperties.edgeBlur(blurColor: Colors.black54),
                                          ),
                                          const SizedBox(height: 5),
                                          const Text(
                                            "اسحب لتحديد جزء من الفيديو",
                                            style: TextStyle(color: Colors.white70, fontSize: 10),
                                          )
                                        ],
                                      ),
                                    ),

                                  if (_isRecording)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 15),
                                      child: Text(
                                        timerText,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                          shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                                        ),
                                      ),
                                    ),

                                  Center(
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        if (!_isRecording && _videoSegments.isNotEmpty)
                                          GestureDetector(
                                            onTap: _resetRecording,
                                            child: Container(
                                              width: 45,
                                              height: 45,
                                              decoration: const BoxDecoration(
                                                color: Color(0xFFE53935),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(Icons.backspace_outlined, color: Colors.white, size: 20),
                                            ),
                                          ),

                                        if (!_isRecording && _videoSegments.isNotEmpty) const SizedBox(width: 20),

                                        GestureDetector(
                                          onTap: () {
                                            if (_isRecording) {
                                              _onRecordHoldEnd();
                                            } else {
                                              _onRecordHoldStart();
                                            }
                                          },
                                          child: Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              SizedBox(
                                                width: 85,
                                                height: 85,
                                                child: CircularProgressIndicator(
                                                  value: _progressPercent,
                                                  strokeWidth: 5,
                                                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                                  backgroundColor: Colors.white24,
                                                ),
                                              ),
                                              AnimatedContainer(
                                                duration: const Duration(milliseconds: 200),
                                                width: _isRecording? 65 : 70,
                                                height: _isRecording? 65 : 70,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: const Color(0xFFFF3B30),
                                                  border: Border.all(color: Colors.white, width: 4),
                                                ),
                                                child: Center(
                                                  child: _isRecording
                                                   ? Container(
                                                        width: 25,
                                                        height: 25,
                                                        decoration: BoxDecoration(
                                                          color: Colors.white,
                                                          borderRadius: BorderRadius.circular(4)
                                                        ),
                                                      )
                                                    : const Icon(Icons.videocam, color: Colors.white, size: 32),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                        if (!_isRecording && _videoSegments.isNotEmpty) const SizedBox(width: 65)
                                        else const SizedBox.shrink(),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          if (!widget.isDuet &&!_isRecording && index == 0)
                            Positioned(
                              right: 20,
                              top: 20,
                              child: _buildSideAction(Icons.flip_camera_ios, "قلب", _toggleCamera),
                            ),

                          if (_previewOpacity == 0.0 || _isProcessing)
                            const Center(child: CircularProgressIndicator(color: Colors.teal)),
                        ],
                      ),
                    );
                  }
                  return Container(
                    color: const Color(0xFF0F1720),
                    child: Center(child: Text(_tabs[index], style: const TextStyle(color: Colors.white))),
                  );
                },
              ),
            ),
          ),

          Container(
            width: double.infinity,
            height: bottomBarHeight,
            color: Colors.teal,
            padding: const EdgeInsets.only(bottom: 20),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (!widget.isDuet &&!_isRecording)
                Positioned(
                  top: 10,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_tabs.length, (index) {
                      bool isSelected = _currentPage == index;
                      String tabText = _tabs[index];
                      Color textColor = isSelected
                         ? (tabText == "LIVE"? const Color(0xFFFF3B30) : Colors.white)
                          : Colors.white.withValues(alpha: 0.4);

                      return GestureDetector(
                        onTap: () => _onTabTap(index),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 15),
                          child: Text(
                            tabText,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 14,
                              fontWeight: isSelected? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),

                if (_currentPage == 0 &&!_isRecording)
                  Positioned(
                    left: 25,
                    child: IconButton(
                      icon: const Icon(Icons.photo_library_outlined, color: Colors.white, size: 24),
                      onPressed: () async {
                        if (_isProcessing) return;
                        setState(() => _isProcessing = true);
                        _disposeCamera();
                        await Future.delayed(const Duration(milliseconds: 200));
                        if (!mounted) return;
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => MediaPickerScreen(
                              isDuet: widget.isDuet,
                              duetVideoUrl: widget.duetVideoUrl,
                            ),
                          ),
                        );
                        if (mounted) {
                          setState(() => _isProcessing = false);
                          if (_currentPage == 0) _initializeCamera();
                        }
                      },
                    ),
                  ),

                if (_videoSegments.isNotEmpty &&!_isRecording)
                  Positioned(
                    right: 25,
                    child: GestureDetector(
                      onTap: () {
                        if (_isProcessing) return;
                        _processAndFinalizeVideo();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                        child: const Icon(Icons.check, color: Colors.teal, size: 24),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSideAction(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildNormalCameraView() {
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _cameraController!.value.previewSize!.height,
            height: _cameraController!.value.previewSize!.width,
            child: CameraPreview(_cameraController!),
          ),
        ),
      ),
    );
  }

  Widget _buildFlexibleDuetView() {
    if (!_isMediaKitInitialized) return const Center(child: CircularProgressIndicator(color: Colors.teal));

    return Container(
      color: const Color(0xFF0F1720),
      child: _getLayoutWidget(),
    );
  }

  Widget _getLayoutWidget() {
    final double fullHeight = MediaQuery.of(context).size.height;
    final double topBarHeight = fullHeight * 0.032;
    final double bottomBarHeight = fullHeight * 0.139;

    final double availableHeight = fullHeight - topBarHeight - bottomBarHeight;
    final double halfHeight = availableHeight / 2;

    switch (_currentLayout) {
      case DuetLayout.sideBySide:
        return Row(
          children: [
            Expanded(
              child: Container(
                decoration: const BoxDecoration(border: Border(right: BorderSide(color: Color(0xFF0F1720), width: 1))),
                child: titi_video.Video(controller: _videoController, fill: const Color(0xFF0F1720)),
              ),
            ),
            Expanded(child: _buildNormalCameraView()),
          ],
        );

      case DuetLayout.react:
        return Stack(
          children: [
            Positioned.fill(child: _buildNormalCameraView()),
            Positioned(
              top: 40,
              left: 20,
              child: Container(
                width: 140,
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F1720).withValues(alpha: 0.5),
                      blurRadius: 10
                    )
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: titi_video.Video(
                    controller: _videoController,
                    fill: const Color(0xFF1A222C),
                    fit: BoxFit.cover,
                    controls: null,
                  ),
                ),
              ),
            ),
          ],
        );

      case DuetLayout.topBottom:
        return Column(
          children: [
            SizedBox(
              height: halfHeight,
              width: double.infinity,
              child: titi_video.Video(
                controller: _videoController,
                fill: const Color(0xFF0F1720),
                fit: BoxFit.cover,
              ),
            ),
            SizedBox(
              height: halfHeight,
              width: double.infinity,
              child: _buildNormalCameraView(),
            ),
          ],
        );

      case DuetLayout.greenScreen:
        return Stack(
          children: [
            Positioned.fill(
              child: titi_video.Video(
                controller: _videoController,
                fill: const Color(0xFF0F1720),
                fit: BoxFit.cover,
              )
            ),
            Positioned.fill(
              child: _isSegmentationEnabled
               ? _buildNormalCameraView()
                : Opacity(opacity: 0.5, child: _buildNormalCameraView()),
            ),
            const Positioned(
              bottom: 150,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  "وضع الشاشة الخضراء مفعل",
                  style: TextStyle(color: Colors.white70, fontSize: 12, backgroundColor: Colors.black45),
                ),
              ),
            ),
          ],
        );
    }
  }
}