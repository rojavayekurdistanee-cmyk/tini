// [Tini] Cover preview and cover-frame editor.
// Uses the existing live editor preview; never starts a final video export.
import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'auth_provider.dart' as custom;
import 'post_like_button.dart';

// Same contract used by the editor's publish preview; one video controller
// belongs to each visible preview, and is released when its route is hidden.
typedef TiniPublishPreviewBuilder = Widget Function(
  ValueNotifier<Duration> position,
  void Function(VideoPlayerController) onReady,
  void Function(VideoPlayerController) onReleased,
  VoidCallback onTap,
);

// Immutable cover project: only a still image is edited, never the video.
// Fractions and text coordinates are resolution independent.
class TiniCoverDesign {
  const TiniCoverDesign({
    this.fraction = 0,
    this.style = 0,
    this.text = '',
    this.x = 0.5,
    this.y = 0.43,
    this.scale = 1.0,
  });

  final double fraction;
  final int style;
  final String text;
  final double x;
  final double y;
  final double scale;

  bool get hasText => style != 0 && text.trim().isNotEmpty;

  TiniCoverDesign copyWith({double? fraction, int? style, String? text,
      double? x, double? y, double? scale}) => TiniCoverDesign(
        fraction: fraction ?? this.fraction,
        style: style ?? this.style,
        text: text ?? this.text,
        x: x ?? this.x,
        y: y ?? this.y,
        scale: scale ?? this.scale,
      );
}

class TiniCoverViewResult {
  const TiniCoverViewResult({
    required this.fraction,
    this.publish = false,
    this.design,
  });

  final double fraction;
  final bool publish;
  final TiniCoverDesign? design;
}

class TiniCoverPreviewScreen extends StatefulWidget {
  const TiniCoverPreviewScreen({
    super.key,
    required this.videoPath,
    required this.fullName,
    required this.username,
    required this.profileImg,
    required this.soundTitle,
    this.soundCover = '',
    this.soundSource = '',
    required this.coverFraction,
    this.coverDesign,
    this.previewBuilder,
    this.previewStart = Duration.zero,
    this.isImage = false,
  });

  final String videoPath;
  final String fullName;
  final String username;
  final String profileImg;
  final String soundTitle;
  final String soundCover;
  final String soundSource;
  final double coverFraction;
  final TiniCoverDesign? coverDesign;
  final TiniPublishPreviewBuilder? previewBuilder;
  final Duration previewStart;
  final bool isImage;

  @override
  State<TiniCoverPreviewScreen> createState() => _TiniCoverPreviewScreenState();
}

class _TiniCoverPreviewScreenState extends State<TiniCoverPreviewScreen> {
  bool _showControls = true;
  bool _editingCover = false;
  late double _coverFraction;
  TiniCoverDesign? _coverDesign;

  @override
  void initState() {
    super.initState();
    _coverFraction = widget.coverFraction.clamp(0.0, 1.0).toDouble();
    _coverDesign = widget.coverDesign;
  }

  Future<void> _editCover() async {
    if (widget.isImage) return;
    // Remove the first texture before the editor creates its own controller.
    setState(() => _editingCover = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final selected = await Navigator.push<TiniCoverDesign>(
      context,
      MaterialPageRoute(
        builder: (_) => TiniCoverEditorScreen(
          videoPath: widget.videoPath,
          previewBuilder: widget.previewBuilder,
          previewStart: widget.previewStart,
          selectedFraction: _coverFraction,
          initialDesign: _coverDesign,
        ),
      ),
    );
    if (!mounted) return;
    if (selected != null) {
      // Saving leaves BOTH cover routes and returns to publish details.
      Navigator.pop(context, TiniCoverViewResult(
        fraction: selected.fraction,
        design: selected,
      ));
      return;
    }
    setState(() => _editingCover = false);
  }

  void _finish({bool publish = false}) {
    Navigator.pop(context, TiniCoverViewResult(
      fraction: _coverFraction, publish: publish, design: _coverDesign));
  }

  // Match the same action geometry and typography as PostItemContent.
  // These controls remain display-only until the post actually exists.
  Widget _buildSideAction(IconData icon, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 28),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white,
            fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // The actual publishing account is the same source used by PostViewScreen.
    final auth = context.watch<custom.AuthProvider>();
    final fullName = auth.isAuthChecked ? auth.fullName : widget.fullName;
    final username = auth.isAuthChecked ? auth.username : widget.username;
    final profileImg = auth.isAuthChecked ? auth.profileImg : widget.profileImg;
    final soundTitle = widget.soundTitle.isNotEmpty ? widget.soundTitle : 'صوت أصلي';
    final soundImage = widget.soundSource == 'itunes' && widget.soundCover.isNotEmpty
        ? widget.soundCover : profileImg;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1720),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              height: 56,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Text('معاينة', style: TextStyle(
                      color: Colors.white, fontSize: 18,
                      fontWeight: FontWeight.bold)),
                  Positioned(
                    right: 8,
                    child: IconButton(
                      tooltip: 'رجوع',
                      icon: const Icon(Icons.arrow_forward, color: Colors.white),
                      onPressed: () => _finish(),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    child: IconButton(
                      tooltip: _showControls ? 'إخفاء عناصر المنشور' : 'إظهار عناصر المنشور',
                      icon: Icon(_showControls
                          ? Icons.fullscreen_rounded
                          : Icons.fullscreen_exit_rounded,
                          color: Colors.white, size: 29),
                      onPressed: () => setState(() => _showControls = !_showControls),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (!_editingCover)
                      _TiniCoverPlayback(
                        videoPath: widget.videoPath,
                        previewBuilder: widget.previewBuilder,
                        previewStart: widget.previewStart,
                        coverFraction: _coverFraction,
                        isImage: widget.isImage,
                      )
                    else
                      const ColoredBox(color: Colors.black),
                    if (!_editingCover && _coverDesign?.hasText == true)
                      Positioned.fill(child: IgnorePointer(
                        child: CustomPaint(painter: TiniCoverArtworkPainter(
                          design: _coverDesign!)),
                      )),
                    if (_showControls && !_editingCover) ...[
                      // Same right-hand action order, spacing and icon sizes
                      // as post_view_screen.dart. A draft has no post ID yet.
                      Positioned(
                        right: 15,
                        bottom: 60,
                        child: IgnorePointer(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              PostLikeButton(
                                postId: '',
                                likesCount: 0,
                                currentUserId: auth.uid,
                                postOwnerId: auth.uid,
                              ),
                              const SizedBox(height: 20),
                              _buildSideAction(Icons.chat_bubble_outline, '0'),
                              const SizedBox(height: 20),
                              Column(
                                children: [
                                  const Icon(Icons.reply_all_rounded,
                                      size: 35, color: Colors.white),
                                  const SizedBox(height: 4),
                                  const Text('0', style: TextStyle(
                                      color: Colors.white, fontSize: 12)),
                                ],
                              ),
                              const SizedBox(height: 20),
                              _buildSideAction(Icons.bookmark_border_rounded, '0'),
                              const SizedBox(height: 20),
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(width: 6, height: 6,
                                        decoration: const BoxDecoration(
                                            color: Color(0xFF009688),
                                            shape: BoxShape.circle)),
                                    const SizedBox(width: 4),
                                    Container(width: 6, height: 6,
                                        decoration: const BoxDecoration(
                                            color: Color(0xFFFF1744),
                                            shape: BoxShape.circle)),
                                    const SizedBox(width: 4),
                                    Container(width: 6, height: 6,
                                        decoration: const BoxDecoration(
                                            color: Color(0xFFFFEB3B),
                                            shape: BoxShape.circle)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // PostViewScreen displays the publisher's real avatar and
                      // full name at the lower left, not in the action column.
                      Positioned(
                        left: 15,
                        bottom: 75,
                        child: IgnorePointer(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                                maxWidth: MediaQuery.sizeOf(context).width * 0.78),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(
                                  radius: 22,
                                  backgroundColor: const Color(0xFF1A222C),
                                  backgroundImage: profileImg.isNotEmpty
                                      ? CachedNetworkImageProvider(profileImg) : null,
                                  child: profileImg.isEmpty
                                      ? Text(fullName.isNotEmpty
                                          ? fullName[0].toUpperCase() : '?',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold))
                                      : null,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(fullName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      shadows: [Shadow(blurRadius: 10,
                                          color: Colors.black)],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Identical sound-bar convention: title + publisher's
                      // username, then album art (iTunes) or profile image.
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: Container(
                            height: 45,
                            color: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                const Icon(Icons.music_note,
                                    color: Colors.white, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text('$soundTitle - $username',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13)),
                                ),
                                Container(
                                  width: 25,
                                  height: 25,
                                  decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white),
                                  child: ClipOval(
                                    child: soundImage.isNotEmpty
                                        ? CachedNetworkImage(
                                            imageUrl: soundImage,
                                            fit: BoxFit.cover,
                                            errorWidget: (context, url, error) =>
                                                const Icon(Icons.music_note,
                                                    size: 15),
                                          )
                                        : const Icon(Icons.music_note, size: 15),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
              child: Row(children: [
                Expanded(child: SizedBox(height: 50, child: ElevatedButton.icon(
                  onPressed: () => _finish(publish: true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
                  icon: const Icon(Icons.arrow_circle_up_outlined),
                  label: const Text('نشر', style: TextStyle(fontWeight: FontWeight.bold)),
                ))),
                const SizedBox(width: 10),
                Expanded(child: SizedBox(height: 50, child: ElevatedButton.icon(
                  onPressed: widget.isImage ? null : _editCover,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A222C),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('تعديل الغلاف',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ))),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class TiniCoverEditorScreen extends StatefulWidget {
  const TiniCoverEditorScreen({
    super.key,
    required this.videoPath,
    required this.selectedFraction,
    this.initialDesign,
    this.previewBuilder,
    this.previewStart = Duration.zero,
  });

  final String videoPath;
  final double selectedFraction;
  final TiniCoverDesign? initialDesign;
  final TiniPublishPreviewBuilder? previewBuilder;
  final Duration previewStart;

  @override
  State<TiniCoverEditorScreen> createState() => _TiniCoverEditorScreenState();
}

class _TiniCoverEditorScreenState extends State<TiniCoverEditorScreen> {
  final GlobalKey<_TiniCoverPlaybackState> _playerKey = GlobalKey();
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocus = FocusNode();
  late TiniCoverDesign _design;
  bool _editingText = false;
  bool _thumbsStarted = false;
  bool _thumbsLoading = false;
  Directory? _thumbDir;
  int? _thumbSession;
  List<File> _thumbnails = const [];
  Offset _panOrigin = Offset.zero;
  Offset _panStart = Offset.zero;
  double _scaleStart = 1.0;

  static const _labels = [
    'بدون', 'كلاسيكي', 'إطار', 'نيون', 'ملصق',
    'فقاعة', 'مشرق', 'متدرج', 'عنوان',
  ];

  @override
  void initState() {
    super.initState();
    _design = (widget.initialDesign ?? const TiniCoverDesign()).copyWith(
      fraction: widget.selectedFraction.clamp(0.0, 1.0).toDouble(),
    );
    _textController.text = _design.text;
  }

  @override
  void dispose() {
    _textController.dispose();
    _textFocus.dispose();
    final sessionId = _thumbSession;
    if (sessionId != null) unawaited(FFmpegKit.cancel(sessionId));
    final directory = _thumbDir;
    // Temp-only timeline images; never touch the original video.
    if (directory != null) {
      unawaited(directory.delete(recursive: true).then((_) {},
          onError: (Object error) { debugPrint('[Tini Cover] Cleanup: $error'); }));
    }
    super.dispose();
  }

  String _format(Duration value) {
    final seconds = value.inSeconds;
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  void _onPlayerReady() {
    if (!mounted) return;
    setState(() {});
    if (!_thumbsStarted) {
      _thumbsStarted = true;
      unawaited(_generateThumbnails());
    }
  }

  Future<void> _generateThumbnails() async {
    final duration = _playerKey.currentState?.availableDuration ?? Duration.zero;
    if (duration.inMilliseconds <= 0 || !await File(widget.videoPath).exists()) return;
    setState(() => _thumbsLoading = true);
    try {
      final temp = await getTemporaryDirectory();
      final dir = await Directory('${temp.path}/tini_cover_frames_'
          '${DateTime.now().microsecondsSinceEpoch}').create();
      _thumbDir = dir;
      const count = 12;
      final seconds = duration.inMilliseconds / 1000;
      final start = widget.previewStart.inMilliseconds / 1000;
      final finished = Completer<FFmpegSession>();
      final session = await FFmpegKit.executeWithArgumentsAsync([
        '-hide_banner', '-loglevel', 'error', '-threads', '2',
        '-ss', start.toStringAsFixed(3),
        '-i', widget.videoPath, '-an', '-sn', '-dn',
        '-vf', 'fps=${(count / seconds).clamp(0.01, 30.0).toStringAsFixed(6)},'
            'scale=80:140:force_original_aspect_ratio=increase,crop=80:140',
        '-frames:v', '$count', '-q:v', '7', '-y',
        '${dir.path}/frame_%02d.jpg',
      ], (result) {
        if (!finished.isCompleted) finished.complete(result);
      });
      _thumbSession = session.getSessionId();
      final result = await finished.future.timeout(const Duration(seconds: 35));
      if (!ReturnCode.isSuccess(await result.getReturnCode())) {
        throw StateError('تعذّر استخراج لقطات الشريط');
      }
      final frames = dir.listSync().whereType<File>()
          .where((f) => f.path.endsWith('.jpg')).toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      if (mounted) setState(() => _thumbnails = frames);
    } catch (error) {
      debugPrint('[Tini Cover] Frame strip: $error');
    } finally {
      _thumbSession = null;
      if (mounted) setState(() => _thumbsLoading = false);
    }
  }

  void _setFraction(double value) {
    final fraction = value.clamp(0.0, 1.0).toDouble();
    setState(() => _design = _design.copyWith(fraction: fraction));
    _playerKey.currentState?.seek(fraction);
  }

  void _selectStyle(int style) {
    setState(() => _design = _design.copyWith(style: style));
    if (style == 0) {
      if (_editingText) _finishTextEdit();
      return;
    }
    // Choosing a cover template opens its text editor immediately.
    _beginTextEdit();
  }

  void _beginTextEdit() {
    if (_design.style == 0) {
      setState(() => _design = _design.copyWith(style: 1));
    }
    if (!_editingText) _textController.text = _design.text;
    setState(() => _editingText = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _textFocus.requestFocus();
    });
  }

  void _finishTextEdit() {
    setState(() {
      _design = _design.copyWith(text: _textController.text.trim());
      _editingText = false;
    });
    _textFocus.unfocus();
  }

  void _save() {
    if (_editingText) _finishTextEdit();
    // The prompt is never committed as the user's actual cover text.
    Navigator.pop(context, _design.copyWith(text: _textController.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final duration = _playerKey.currentState?.availableDuration ?? Duration.zero;
    final position = Duration(milliseconds:
        (duration.inMilliseconds * _design.fraction).round());
    return Scaffold(
      backgroundColor: const Color(0xFF0F1720),
      // This is essential: the Android keyboard MUST NOT resize the video.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1720),
        surfaceTintColor: const Color(0xFF0F1720),
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء', style: TextStyle(color: Colors.white70)),
        ),
        leadingWidth: 74,
        title: const Text('تعديل الغلاف',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold,
                fontSize: 17)),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('حفظ', style: TextStyle(
              color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        maintainBottomViewPadding: true,
        child: LayoutBuilder(builder: (context, viewport) {
          // The video dimensions depend on the screen, NEVER viewInsets.bottom.
          // Controls are overlaid at the bottom instead of shrinking the video.
          final previewHeight = (viewport.maxWidth * 16.0 / 9.0)
              .clamp(0.0, viewport.maxHeight).toDouble();
          final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
          final visiblePreviewHeight = (viewport.maxHeight - keyboardHeight)
              .clamp(0.0, previewHeight).toDouble();
          return Stack(children: [
            Positioned(
              left: 0, top: 0, right: 0, height: previewHeight,
              child: ClipRect(child: LayoutBuilder(builder: (context, box) {
                // Keep the video at its original size. During typing, only
                // the artwork position may temporarily move above the keyboard.
                // The editable glyphs occupy the painter's own text rectangle,
                // so there is no second black/text-field layer over the cover.
                final size = Size(box.maxWidth, box.maxHeight);
                var editingDesign = _design;
                if (_editingText && keyboardHeight > 0) {
                  final artwork = TiniCoverArtworkPainter.textGeometry(
                    design: editingDesign,
                    size: size,
                    showPlaceholder: true,
                  );
                  final visibleBottom = (visiblePreviewHeight - 8.0)
                      .clamp(0.0, size.height).toDouble();
                  if (artwork.frame.bottom > visibleBottom) {
                    final shift = artwork.frame.bottom - visibleBottom;
                    editingDesign = editingDesign.copyWith(
                      y: ((editingDesign.y * size.height - shift) /
                              size.height)
                          .clamp(0.1, 0.9).toDouble(),
                    );
                  }
                }
                final textGeometry = _editingText
                    ? TiniCoverArtworkPainter.textGeometry(
                        design: editingDesign,
                        size: size,
                        showPlaceholder: true,
                      )
                    : null;
                return Stack(fit: StackFit.expand, children: [
                  _TiniCoverPlayback(
                    key: _playerKey,
                    videoPath: widget.videoPath,
                    previewBuilder: widget.previewBuilder,
                    previewStart: widget.previewStart,
                    coverFraction: _design.fraction,
                    onReady: _onPlayerReady,
                  ),
                  // Same artwork painter is used for preview and final WebP.
                  if (_design.style != 0)
                    IgnorePointer(child: CustomPaint(
                      painter: TiniCoverArtworkPainter(
                        design: _editingText ? editingDesign : _design,
                        showPlaceholder: true,
                      ),
                    )),
                  if (_design.style != 0)
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      // Touching outside the text closes the keyboard; the
                      // same cover can then be moved or pinched immediately.
                      onTap: _editingText ? _finishTextEdit : _beginTextEdit,
                      onScaleStart: (details) {
                        if (_editingText) _finishTextEdit();
                        _panOrigin = details.localFocalPoint;
                        _panStart = Offset(_design.x, _design.y);
                        _scaleStart = _design.scale;
                      },
                      onScaleUpdate: (details) {
                        setState(() => _design = _design.copyWith(
                          x: (_panStart.dx + (details.localFocalPoint.dx -
                                  _panOrigin.dx) / box.maxWidth)
                              .clamp(0.1, 0.9).toDouble(),
                          y: (_panStart.dy + (details.localFocalPoint.dy -
                                  _panOrigin.dy) / box.maxHeight)
                              .clamp(0.1, 0.9).toDouble(),
                          scale: (_scaleStart * details.scale)
                              .clamp(TiniCoverArtworkPainter.minScale,
                                  TiniCoverArtworkPainter.maxScale).toDouble(),
                        ));
                      },
                    ),
                  if (_editingText && textGeometry != null)
                    Positioned(
                      left: textGeometry.editor.left,
                      top: textGeometry.editor.top,
                      width: textGeometry.editor.width,
                      height: textGeometry.editor.height,
                      // EditableText paints ONLY glyphs, selection and caret.
                      // Its background is the ORIGINAL selected cover style.
                      child: EditableText(
                        controller: _textController,
                        focusNode: _textFocus,
                        autofocus: true,
                        // Render the real styled text with the painter.
                        // This editor supplies ONLY the cursor and keyboard,
                        // never a second text layer or background rectangle.
                        style: TextStyle(
                          color: Colors.transparent,
                          fontSize: textGeometry.fontSize,
                          height: 1.15,
                          fontWeight: FontWeight.w900,
                        ),
                        textScaler: TextScaler.noScaling,
                        cursorColor: Colors.teal,
                        backgroundCursorColor: Colors.white54,
                        selectionColor: Colors.teal.withValues(alpha: 0.30),
                        textAlign: TextAlign.center,
                        textDirection: TextDirection.rtl,
                        maxLines: 3,
                        minLines: 1,
                        textInputAction: TextInputAction.done,
                        keyboardType: TextInputType.text,
                        inputFormatters: [LengthLimitingTextInputFormatter(65)],
                        onChanged: (value) => setState(() =>
                            _design = _design.copyWith(text: value)),
                        onSubmitted: (_) => _finishTextEdit(),
                        onTapOutside: (_) => _finishTextEdit(),
                      ),
                    ),
                ]);
              })),
            ),
            // Floating tool panel. The keyboard may cover the panel, but it
            // cannot modify the geometry of the video above it.
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: Container(
                color: const Color(0xFF0F1720),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 7, 18, 6),
                    child: Row(children: [
                      Text(_format(position), style: const TextStyle(
                          color: Colors.white70, fontSize: 12)),
                      const Spacer(),
                      Text(_format(duration), style: const TextStyle(
                          color: Colors.white70, fontSize: 12)),
                    ]),
                  ),
                  // Frame strip; it still selects the exact cover timestamp.
                  SizedBox(height: 70, child: Row(children: [
                    const SizedBox(width: 9),
                    const Column(mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                      Icon(Icons.add_box_outlined,
                          color: Colors.teal, size: 23),
                      Text('لقطات', style: TextStyle(
                          color: Colors.white70, fontSize: 10)),
                    ]),
                    const SizedBox(width: 8),
                    Expanded(child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _thumbnails.isNotEmpty ? _thumbnails.length : 12,
                      itemBuilder: (context, index) {
                        final count = _thumbnails.isNotEmpty
                            ? _thumbnails.length : 12;
                        final fraction = count <= 1 ? 0.0 : index / (count - 1);
                        final selected = (fraction - _design.fraction).abs() <=
                            (count <= 1 ? 1.0 : 0.5 / (count - 1));
                        return GestureDetector(
                          onTap: () => _setFraction(fraction),
                          child: Container(
                            width: 48, height: 62,
                            margin: const EdgeInsets.only(
                                right: 2, top: 2, bottom: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A222C),
                              border: Border.all(
                                color: selected ? Colors.teal : Colors.white24,
                                width: selected ? 2.5 : 1,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: _thumbnails.isNotEmpty
                                ? Image.file(_thumbnails[index], fit: BoxFit.cover,
                                    gaplessPlayback: true)
                                : Center(child: _thumbsLoading
                                    ? const SizedBox(width: 14, height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1.5, color: Colors.teal))
                                    : const Icon(Icons.photo_outlined,
                                        size: 17, color: Colors.white54)),
                          ),
                        );
                      },
                    )),
                    const SizedBox(width: 9),
                  ])),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 9, 16, 4),
                    child: Align(alignment: Alignment.centerRight,
                      child: Text('قوالب الغلاف', style: TextStyle(
                        color: Colors.white, fontSize: 14,
                        fontWeight: FontWeight.bold))),
                  ),
                  SizedBox(height: 91, child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    itemCount: _labels.length,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    itemBuilder: (context, index) {
                      final selected = _design.style == index;
                      final example = TiniCoverDesign(style: index,
                          text: 'Tini', x: 0.5, y: 0.5, scale: 1);
                      return InkWell(
                        onTap: () => _selectStyle(index),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(children: [
                            Container(
                              width: 70, height: 56,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A222C),
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(
                                  color: selected ? Colors.teal : Colors.white24,
                                  width: selected ? 2.5 : 1.0,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: index == 0
                                  ? const Icon(Icons.block,
                                      color: Colors.white54)
                                  : CustomPaint(
                                      painter: TiniCoverArtworkPainter(
                                          design: example)),
                            ),
                            const SizedBox(height: 5),
                            Text(_labels[index], style: TextStyle(
                              fontSize: 11,
                              color: selected ? Colors.teal : Colors.white70,
                              fontWeight: selected
                                  ? FontWeight.bold : FontWeight.normal,
                            )),
                          ]),
                        ),
                      );
                    },
                  )),
                ]),
              ),
            ),
          ]);
        }),
      ),
    );
  }

}

// Scalable painter shared between the in-editor preview, published thumbnail,
// and the cover preview. No TikTok branding or baked-in logos.
class TiniCoverArtworkPainter extends CustomPainter {
  const TiniCoverArtworkPainter({required this.design,
      this.showPlaceholder = false, this.paintText = true});

  final TiniCoverDesign design;
  final bool showPlaceholder;
  final bool paintText;

  // Wider pinch range shared with the painter used for the final WebP.
  // Keep a small positive lower bound to avoid zero-sized text and a generous
  // upper bound to avoid pathological layout sizes on mobile devices.
  static const double minScale = 0.10;
  static const double maxScale = 8.0;

  // Scale the text's available line width with its font and frame padding.
  // The old fixed 77% line width made enlarged templates wrap prematurely.
  static double _maxTextWidth(Size size, double scale) {
    final unit = size.width / 480.0;
    return ((size.width * 0.77 - 36.0 * unit) * scale)
        .clamp(1.0, size.width * maxScale).toDouble();
  }

  // Keep the template anchored to the chosen position. When enlarged beyond
  // the canvas, allow natural clipping instead of snapping it to top/left.
  static double _visibleOffset(double center, double extent, double canvas) {
    return extent <= canvas
        ? (center - extent / 2).clamp(0.0, canvas - extent).toDouble()
        : (center - extent / 2).clamp(canvas - extent, 0.0).toDouble();
  }

  // This uses the very same font metrics, frame padding and clamping as paint().
  // The inline keyboard editor therefore sits INSIDE the actual chosen cover
  // template instead of painting a second input box over that template.
  static _TiniCoverTextGeometry textGeometry({
    required TiniCoverDesign design,
    required Size size,
    bool showPlaceholder = false,
  }) {
    final label = design.text.trim().isEmpty
        ? (showPlaceholder ? 'أدخل النص' : '') : design.text.trim();
    final unit = size.width / 480.0;
    final fontSize = 30.0 * unit * design.scale;
    final paddingX = 18.0 * unit * design.scale;
    final paddingY = 11.0 * unit * design.scale;
    final maxWidth = _maxTextWidth(size, design.scale);
    final textPainter = TextPainter(
      text: TextSpan(text: label, style: TextStyle(
        fontSize: fontSize, height: 1.15, fontWeight: FontWeight.w900,
      )),
      maxLines: 3,
      ellipsis: '…',
      textAlign: TextAlign.center,
      textDirection: TextDirection.rtl,
    )..layout(maxWidth: maxWidth);
    final textWidth = textPainter.width;
    final textHeight = textPainter.height;
    textPainter.dispose();
    final padded = design.style != 3 && design.style != 7;
    final frameWidth = textWidth + (padded ? paddingX * 2 : 0);
    final frameHeight = textHeight + (padded ? paddingY * 2 : 0);
    final cx = design.x.clamp(0.1, 0.9) * size.width;
    final cy = design.y.clamp(0.1, 0.9) * size.height;
    final left = _visibleOffset(cx, frameWidth, size.width);
    final top = _visibleOffset(cy, frameHeight, size.height);
    final frame = Rect.fromLTWH(left, top, frameWidth, frameHeight);
    // EditableText has no decoration or background. Give the cursor a little
    // breathing room but center the glyphs in the painter's text rectangle.
    final editorWidth = maxWidth.clamp(1.0, size.width).toDouble();
    final editorHeight = (textHeight + 8.0).clamp(24.0, size.height).toDouble();
    final editorLeft = (frame.center.dx - editorWidth / 2)
        .clamp(0.0, (size.width - editorWidth).clamp(0.0, size.width))
        .toDouble();
    final editorTop = (frame.center.dy - editorHeight / 2)
        .clamp(0.0, (size.height - editorHeight).clamp(0.0, size.height))
        .toDouble();
    return _TiniCoverTextGeometry(
      frame: frame,
      editor: Rect.fromLTWH(editorLeft, editorTop, editorWidth, editorHeight),
      fontSize: fontSize,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (design.style == 0 || size.isEmpty) return;
    final label = design.text.trim().isEmpty
        ? (showPlaceholder ? 'أدخل النص' : '') : design.text.trim();
    if (label.isEmpty) return;

    final unit = size.width / 480.0;
    final fontSize = 30.0 * unit * design.scale;
    final paddingX = 18.0 * unit * design.scale;
    final paddingY = 11.0 * unit * design.scale;
    final style = design.style;
    Color color = Colors.white;
    if (style == 2) color = const Color(0xFF141E27);
    if (style == 3) color = const Color(0xFFDBFF3F);
    if (style == 4) color = const Color(0xFF12212B);
    if (style == 6) color = const Color(0xFF151515);
    if (style == 7) color = const Color(0xFFFFF04D);

    TextPainter painterFor({Paint? foreground}) => TextPainter(
      text: TextSpan(text: label, style: TextStyle(
        fontSize: fontSize,
        height: 1.15,
        fontWeight: FontWeight.w900,
        color: foreground == null ? color : null,
        foreground: foreground,
        shadows: style == 0 || style == 1 || style == 3 || style == 7
            ? const [Shadow(color: Colors.black87, blurRadius: 5,
                offset: Offset(1, 2))] : null,
      )),
      maxLines: 3,
      ellipsis: '…',
      textAlign: TextAlign.center,
      textDirection: TextDirection.rtl,
    );

    final textPainter = painterFor()..layout(
      maxWidth: _maxTextWidth(size, design.scale),
    );
    final padded = style != 3 && style != 7;
    final width = textPainter.width + (padded ? paddingX * 2 : 0);
    final height = textPainter.height + (padded ? paddingY * 2 : 0);
    final cx = design.x.clamp(0.1, 0.9) * size.width;
    final cy = design.y.clamp(0.1, 0.9) * size.height;
    final left = _visibleOffset(cx, width, size.width);
    final top = _visibleOffset(cy, height, size.height);
    canvas.save();
    canvas.translate(left.toDouble(), top.toDouble());
    final bounds = Rect.fromLTWH(0, 0, width, height);
    final radius = Radius.circular(14 * unit * design.scale);

    if (style == 1 || style == 5 || style == 8) {
      canvas.drawRRect(RRect.fromRectAndRadius(bounds, radius),
          Paint()..color = style == 5 ? const Color(0xFF35B8A6)
              : style == 8 ? const Color(0xEE0F1720)
              : const Color(0xEE17242F));
      if (style == 5) {
        final tail = Path()..moveTo(width * 0.22, height - 1)
          ..lineTo(width * 0.31, height + 11 * unit * design.scale)
          ..lineTo(width * 0.39, height - 1)..close();
        canvas.drawPath(tail, Paint()..color = const Color(0xFF35B8A6));
      }
      if (style == 8) canvas.drawRect(
          Rect.fromLTWH(0, 0, 5 * unit * design.scale, height),
          Paint()..color = Colors.tealAccent);
    } else if (style == 2 || style == 4 || style == 6) {
      canvas.drawRRect(RRect.fromRectAndRadius(bounds, radius),
          Paint()..color = style == 4 ? const Color(0xFFFFDF54)
              : style == 6 ? const Color(0xFFECF7F5) : Colors.white);
      canvas.drawRRect(RRect.fromRectAndRadius(bounds, radius),
          Paint()..style = PaintingStyle.stroke
            ..strokeWidth = 2.4 * unit * design.scale
            ..color = style == 4 ? const Color(0xFF14212C) : Colors.teal);
    }
    final textOffset = Offset(padded ? paddingX : 0, padded ? paddingY : 0);
    if (paintText) {
      if (style == 3 || style == 7) {
        final outline = painterFor(foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4 * unit * design.scale
          ..strokeJoin = StrokeJoin.round
          ..color = style == 3 ? Colors.black : const Color(0xFFE53935))
          ..layout(maxWidth: _maxTextWidth(size, design.scale));
        outline.paint(canvas, textOffset);
        outline.dispose();
      }
      textPainter.paint(canvas, textOffset);
    }
    textPainter.dispose();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant TiniCoverArtworkPainter oldDelegate) =>
      design != oldDelegate.design ||
      showPlaceholder != oldDelegate.showPlaceholder ||
      paintText != oldDelegate.paintText;
}

// Private layout of the template text relative to the video canvas.
class _TiniCoverTextGeometry {
  const _TiniCoverTextGeometry({
    required this.frame,
    required this.editor,
    required this.fontSize,
  });

  final Rect frame;
  final Rect editor;
  final double fontSize;
}

// Produces only the FINAL WebP cover after the user's «نشر» action. The
// already-exported MP4 is NEVER modified or encoded again by this compositor.
class TiniCoverComposer {
  static Future<String> composeWebp({
    required File sourceStill,
    required File destination,
    required TiniCoverDesign design,
  }) async {
    if (!design.hasText) throw ArgumentError('الغلاف لا يحتوي على نص');
    final codec = await ui.instantiateImageCodec(await sourceStill.readAsBytes());
    final frame = await codec.getNextFrame();
    codec.dispose();
    const width = 480;
    const height = 854;
    const size = Size(480.0, 854.0);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 480, 854));
    paintImage(canvas: canvas, rect: Offset.zero & size, image: frame.image,
      fit: BoxFit.cover, filterQuality: FilterQuality.high);
    TiniCoverArtworkPainter(design: design).paint(canvas, size);
    final picture = recorder.endRecording();
    final composed = await picture.toImage(width, height);
    picture.dispose();
    frame.image.dispose();
    final png = await composed.toByteData(format: ui.ImageByteFormat.png);
    composed.dispose();
    if (png == null) throw StateError('تعذّر تكوين صورة الغلاف');
    final intermediate = File('${destination.path}.png');
    await intermediate.writeAsBytes(png.buffer.asUint8List(), flush: true);
    try {
      final done = Completer<FFmpegSession>();
      final session = await FFmpegKit.executeWithArgumentsAsync([
        '-hide_banner', '-loglevel', 'error', '-threads', '2',
        '-i', intermediate.path, '-frames:v', '1',
        '-c:v', 'libwebp', '-quality', '75', '-y', destination.path,
      ], (result) {
        if (!done.isCompleted) done.complete(result);
      });
      final id = session.getSessionId();
      FFmpegSession result;
      try {
        result = await done.future.timeout(const Duration(seconds: 30));
      } on TimeoutException {
        if (id != null) await FFmpegKit.cancel(id);
        rethrow;
      }
      if (!ReturnCode.isSuccess(await result.getReturnCode()) ||
          !await destination.exists() || await destination.length() == 0) {
        throw StateError('فشل حفظ صورة الغلاف بصيغة WebP');
      }
      return destination.path;
    } finally {
      if (await intermediate.exists()) await intermediate.delete();
    }
  }
}

// A single owner for either the existing montage preview or a plain file.
// Hidden routes release their player before the next screen creates another.
class _TiniCoverPlayback extends StatefulWidget {
  const _TiniCoverPlayback({
    super.key,
    required this.videoPath,
    required this.coverFraction,
    this.previewBuilder,
    this.previewStart = Duration.zero,
    this.isImage = false,
    this.onReady,
  });

  final String videoPath;
  final double coverFraction;
  final TiniPublishPreviewBuilder? previewBuilder;
  final Duration previewStart;
  final bool isImage;
  final VoidCallback? onReady;

  @override
  State<_TiniCoverPlayback> createState() => _TiniCoverPlaybackState();
}

class _TiniCoverPlaybackState extends State<_TiniCoverPlayback> {
  final ValueNotifier<Duration> _position = ValueNotifier(Duration.zero);
  VideoPlayerController? _filePlayer;
  VideoPlayerController? _controller;
  VoidCallback? _playerListener;
  double? _requestedSeek;
  bool _seeking = false;

  Duration get availableDuration {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return Duration.zero;
    final ms = controller.value.duration.inMilliseconds - widget.previewStart.inMilliseconds;
    return Duration(milliseconds: ms > 0 ? ms : controller.value.duration.inMilliseconds);
  }

  @override
  void initState() {
    super.initState();
    if (!widget.isImage && widget.previewBuilder == null) _initFilePlayer();
  }

  Future<void> _initFilePlayer() async {
    final player = VideoPlayerController.file(File(widget.videoPath),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    _filePlayer = player;
    try {
      await player.initialize();
      if (!mounted || !identical(_filePlayer, player)) return;
      await player.setLooping(true);
      _attach(player);
      if (mounted) setState(() {});
    } catch (error) {
      debugPrint('[Tini Cover] Preview failed: $error');
      if (mounted) setState(() {});
    }
  }

  void _attach(VideoPlayerController player) {
    if (!mounted) return;
    if (!identical(_controller, player)) _detach(_controller);
    _controller = player;
    _playerListener = () {
      if (mounted && identical(_controller, player)) {
        _position.value = player.value.position;
      }
    };
    player.addListener(_playerListener!);
    player.setVolume(0);
    player.pause();
    seek(widget.coverFraction);
    widget.onReady?.call();
  }

  void _detach(VideoPlayerController? player) {
    if (player == null || !identical(_controller, player)) return;
    final listener = _playerListener;
    if (listener != null) player.removeListener(listener);
    _playerListener = null;
    _controller = null;
  }

  Future<void> seek(double fraction) async {
    _requestedSeek = fraction.clamp(0.0, 1.0).toDouble();
    if (_seeking) return;
    _seeking = true;
    try {
      while (mounted && _requestedSeek != null) {
        final desired = _requestedSeek!;
        _requestedSeek = null;
        final player = _controller;
        if (player == null || !player.value.isInitialized) break;
        final durationMs = player.value.duration.inMilliseconds;
        final startMs = widget.previewStart.inMilliseconds.clamp(0, durationMs).toInt();
        final usableMs = durationMs - startMs;
        final atMs = (startMs + (usableMs * desired).round())
            .clamp(0, durationMs > 100 ? durationMs - 100 : durationMs).toInt();
        await player.seekTo(Duration(milliseconds: atMs));
        if (mounted && identical(_controller, player)) {
          _position.value = Duration(milliseconds: atMs);
        }
      }
    } catch (error) {
      debugPrint('[Tini Cover] Seeking: $error');
    } finally {
      _seeking = false;
    }
  }

  void _toggle() {
    final player = _controller;
    if (player == null || !player.value.isInitialized) return;
    player.value.isPlaying ? player.pause() : player.play();
  }

  @override
  void dispose() {
    _detach(_controller);
    _filePlayer?.dispose();
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isImage) {
      return Image.file(File(widget.videoPath), fit: BoxFit.cover);
    }
    if (widget.previewBuilder != null) {
      // This is the SAME live effects/overlay preview used by the editor.
      return widget.previewBuilder!(_position, _attach, _detachFromBuilder, _toggle);
    }
    final player = _filePlayer;
    if (player == null || !player.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.teal));
    }
    final size = player.value.size;
    if (size.width <= 0 || size.height <= 0) {
      return const Center(child: CircularProgressIndicator(color: Colors.teal));
    }
    return GestureDetector(
      onTap: _toggle,
      child: SizedBox.expand(child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(width: size.width, height: size.height,
            child: VideoPlayer(player)),
      )),
    );
  }

  void _detachFromBuilder(VideoPlayerController player) => _detach(player);
}
