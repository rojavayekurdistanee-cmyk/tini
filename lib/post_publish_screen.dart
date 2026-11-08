// [Tini] ملف post_publish_screen.dart - نسخة "نظام الهاشتاجات الذكي والتركيز الكامل"
import 'dart:io';
import 'dart:async';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:provider/provider.dart';
// [القاعدة: المكتبة أولاً]
import 'package:path_provider/path_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_provider.dart' as custom;
import 'post_provider.dart';
import 'mention_picker_sheet.dart';
import 'mention_privacy_service.dart';
import 'hashtag_service.dart';
import 'location_picker_sheet.dart';
import 'video_processor.dart';
import 'package:gal/gal.dart';
import 'mystery_box_rules_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'moderation_service.dart';
import 'dart:convert';
import 'tini_cover_screen.dart';


// Read one actual still from the ALREADY exported video. This uses the same
// FFmpeg decoder that verifies the background H.264 graph; the Android
// video_thumbnail MethodChannel is unregistered on the tested Samsung device.
// No re-encoding, thumbnail-plugin fallback or safety-check bypass.
Future<String> _tiniExtractPublicationStill({
  required String videoPath,
  required Duration at,
  required File output,
  bool webp = false,
}) async {
  final done = Completer<FFmpegSession>();
  final session = await FFmpegKit.executeWithArgumentsAsync([
    '-hide_banner', '-loglevel', 'error',
    '-threads', '2',
    '-i', videoPath,
    // Output-side seek decodes from a keyframe rather than trusting a
    // potentially inaccurate keyframe index from the MP4 container.
    '-ss', (at.inMicroseconds / 1000000.0).toStringAsFixed(6),
    '-map', '0:v:0', '-an', '-sn', '-dn',
    '-vf', 'scale=480:-2:flags=fast_bilinear',
    '-frames:v', '1',
    if (webp) ...['-c:v', 'libwebp', '-quality', '75']
    else ...['-q:v', '6'],
    '-y', output.path,
  ], (finished) {
    if (!done.isCompleted) done.complete(finished);
  });
  final sessionId = session.getSessionId();
  FFmpegSession finished;
  try {
    finished = await done.future.timeout(const Duration(seconds: 30));
  } on TimeoutException {
    if (sessionId != null) {
      try {
        await FFmpegKit.cancel(sessionId);
      } catch (error) {
        debugPrint('[Tini Publication] Still cancellation: $error');
      }
    }
    throw StateError('انتهت مهلة قراءة إطار الفيديو عند ${at.inMilliseconds}ms.');
  }
  final code = await finished.getReturnCode();
  if (!ReturnCode.isSuccess(code) ||
      !await output.exists() || await output.length() == 0) {
    final log = (await finished.getAllLogsAsString()) ?? '';
    final summary = log.length > 1000 ? log.substring(log.length - 1000) : log;
    debugPrint('[Tini Publication] Invalid still at ${at.inMilliseconds}ms: '
        '$code; $summary');
    throw StateError('فشل قراءة إطار الفيديو عند ${at.inMilliseconds}ms. '
        'راجع سجل Tini Publication لمعرفة سبب فك الترميز.');
  }
  return output.path;
}

// These helpers are stateless: they can run after PostPublishScreen is popped.
Future<void> _tiniLogPublishMention(String toUsername, String postId) async {
  try {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUid.isEmpty) return;
    final query = await FirebaseFirestore.instance.collection('users')
        .where('username_lowercase', isEqualTo: toUsername.toLowerCase())
        .limit(1).get();
    if (query.docs.isEmpty) return;
    final toUid = query.docs.first.id;
    if (toUid == currentUid) return;
    if (!await MentionPrivacyService.canMentionUser(
        targetUid: toUid, senderUid: currentUid)) return;
    final userDoc = await FirebaseFirestore.instance.collection('users')
        .doc(currentUid).get();
    final userName = userDoc.data()?['fullName'] ??
        userDoc.data()?['username'] ?? 'مستخدم';
    await FirebaseFirestore.instance.collection('activities').add({
      'toUid': toUid, 'fromUid': currentUid, 'type': 'mention',
      'text': '$userName ذكرك في منشور', 'postId': postId,
      'timestamp': FieldValue.serverTimestamp(), 'seen': false,
    });
  } catch (_) {}
}

Future<void> _tiniLogPublishDuet(
    String toUid, String fullName, String postId) async {
  try {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUid.isEmpty || toUid == currentUid) return;
    await FirebaseFirestore.instance.collection('activities').add({
      'toUid': toUid, 'fromUid': currentUid, 'type': 'duet',
      'text': '$fullName عمل ديو معك', 'postId': postId,
      'timestamp': FieldValue.serverTimestamp(), 'seen': false,
    });
  } catch (_) {}
}

class PostPublishScreen extends StatefulWidget {
  final String videoPath;
  final Future<String?> Function()? prepareVideo;
  final TiniPublishPreviewBuilder? pendingPreviewBuilder;
  final Duration pendingPreviewStart;
  final bool pendingPreviewIsImage;
  final bool isDuet;
  final String? duetVideoUrl;
  final dynamic duetLayout;
  final String fullName;
  final String username;
  final String profileImg;
  final String uid;
  final String? originalAuthorName;
  final String? originalUsername;
  final String? originalOwnerId; // <-- جديد
  final String title;
  final String artist;
  final String cover;
  final String source;
  final DuetLayout
  selectedLayout; // أضف هذا السطر في تعريف الشاشة لكي يعمل الكود

  const PostPublishScreen({
    super.key,
    required this.videoPath,
    this.prepareVideo,
    this.pendingPreviewBuilder,
    this.pendingPreviewStart = Duration.zero,
    this.pendingPreviewIsImage = false,
    this.isDuet = false,
    this.duetVideoUrl,
    this.duetLayout,
    required this.fullName,
    required this.username,
    required this.profileImg,
    required this.uid,
    this.originalAuthorName,
    this.originalUsername,
    this.originalOwnerId, // <-- جديد
    required this.selectedLayout,
    required this.title,
    required this.artist,
    required this.cover,
    required this.source,
  });

@override
State<PostPublishScreen> createState() => _PostPublishScreenState();
}

class _PostPublishScreenState extends State<PostPublishScreen> {
  bool _isLoading = false;
  final ValueNotifier<Duration> _pendingPosition = ValueNotifier(Duration.zero);
  double _selectedCoverFraction = 0.0;
  TiniCoverDesign? _selectedCoverDesign;
  bool _coverPreviewOpen = false;
  VideoPlayerController? _pendingController;
  VoidCallback? _pendingPositionListener;

  void _seekPreviewToCover(VideoPlayerController controller) {
    if (!controller.value.isInitialized) return;
    final durationMs = controller.value.duration.inMilliseconds;
    final startMs = widget.pendingPreviewStart.inMilliseconds
        .clamp(0, durationMs).toInt();
    final maxMs = durationMs > 100 ? durationMs - 100 : durationMs;
    final atMs = (startMs +
            ((durationMs - startMs) * _selectedCoverFraction).round())
        .clamp(0, maxMs).toInt();
    controller.seekTo(Duration(milliseconds: atMs));
  }

  void _onPendingControllerReady(VideoPlayerController controller) {
    if (!mounted) return;
    _pendingController = controller;
    void updatePosition() {
      if (mounted) _pendingPosition.value = controller.value.position;
    }
    _pendingPositionListener = updatePosition;
    controller.addListener(updatePosition);
    controller.setVolume(0);
    _seekPreviewToCover(controller);
    updatePosition();
  }

  void _onPendingControllerReleased(VideoPlayerController controller) {
    if (identical(_pendingController, controller)) {
      final listener = _pendingPositionListener;
      if (listener != null) controller.removeListener(listener);
      _pendingPositionListener = null;
      _pendingController = null;
    }
  }

  void _togglePendingPreview() {
    final controller = _pendingController;
    if (controller == null || !controller.value.isInitialized) return;
    controller.value.isPlaying ? controller.pause() : controller.play();
  }

  final TextEditingController _captionController = TextEditingController();
  VideoPlayerController? _videoPlayerController;
  VideoPlayerController?
  _duetController; // [إضافة تقنية 1]: المشغل الثاني للديو

  // [Tini Logic]: متغيرات صمامات الأمان والخصوصية - مفصول
  String _privacy = "public"; // public, friends, private
  String _commentPrivacy = "comment_everyone"; // comment_everyone / comment_friends / comment_nobody
  bool _allowDownload = true;
  bool _allowDuet = true;

  bool _saveToDevice = false;
  bool _showWatermark = true;
  List<String> _selectedMentions = [];

  // [Tini Logic]: صمام أمان لمنع التخبط عند اختيار الهاشتاج
  bool _isApplyingHashtag = false;

    // [Tini V30.4]: متغيرات بحر الصناديق - سعر ثابت
  bool _isMysteryBox = false;
  String? _selectedBoxRarity; // null = مش صندوق | bronze/silver/gold/diamond
  final TextEditingController _boxTitleController = TextEditingController(); // عنوان الصندوق الإجباري

  // ألوان الهوية البصرية المعتمدة لـ Tini
  final Color titiTeal = const Color(0xFF009688);
  final Color bgDark = const Color(0xFF0F1720);
  final Color surfaceDark = const Color(0xFF1A222C);
  final Color errorRed = const Color(0xFFE53935);
  final Color draftGrey = const Color(0xFF2C353F);

  @override
  void initState() {
    super.initState();
    // No FFmpeg/MP4 export in the publish screen. The live preview remains
    // active; the final render starts ONLY when «نشر الآن» is pressed.
    if (widget.pendingPreviewBuilder == null && !widget.pendingPreviewIsImage) {
      _initializePreview(widget.videoPath);
    }
    _captionController.addListener(_onCaptionChanged);
    // [ADDITION] تحميل الخصوصية الافتراضية من الإعدادات
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Provider.of<custom.AuthProvider>(context, listen: false);
setState(() {
  if (auth.defaultPrivacy == 'friends') {
    _privacy = 'friends';
  } else if (auth.defaultPrivacy == 'only_me') {
    _privacy = 'private';
  } else {
    _privacy = 'public';
  }

  _commentPrivacy = auth.commentPrivacy;
});
    });
  }



  Future<void> _initializePreview(String path) async {
    try {
      // تهيئة فيديو الكاميرا الأساسي
      final controller = VideoPlayerController.file(File(path));
      _videoPlayerController = controller;
      await controller.initialize();
      if (!mounted || !identical(controller, _videoPlayerController)) {
        await controller.dispose();
        return;
      }

      // [إضافة تقنية 1 معدلة]: تهيئة فيديو الديو إذا كانت الخاصية مفعلة
      if (widget.isDuet && widget.duetVideoUrl != null) {
       _duetController = VideoPlayerController.networkUrl(Uri.parse(widget.duetVideoUrl!));
        await _duetController!.initialize();
        await _duetController!.setVolume(0.0); // كتم صوت الديو لمنع التداخل
        await _duetController!.setLooping(false);
      }

      if (mounted) {
        setState(() {});
        _videoPlayerController?.pause();
        _seekPreviewToCover(controller);
        _videoPlayerController?.setLooping(false);
        _duetController?.pause();
      }
    } catch (_) {
      
    }
  }

  @override
  void dispose() {
    if (_pendingController != null && _pendingPositionListener != null) {
      _pendingController!.removeListener(_pendingPositionListener!);
    }
    _pendingPositionListener = null;
    _pendingController = null;
    _pendingPosition.dispose();
    _captionController.removeListener(_onCaptionChanged);
    _captionController.dispose();
    _boxTitleController.dispose();
    _videoPlayerController?.pause();
    _videoPlayerController?.dispose();
    _duetController?.pause(); // [إضافة]
    _duetController?.dispose(); // [إضافة]
    super.dispose();
  }

  void _onVideoPreviewTap() {
    if (widget.pendingPreviewBuilder != null) {
      _togglePendingPreview();
    }
  }

  Future<void> _onCoverTap() async {
    if (_coverPreviewOpen || _isLoading) return;
    _videoPlayerController?.pause();
    _pendingController?.pause();
    setState(() => _coverPreviewOpen = true);
    // Allow the compact live-preview texture to be disposed before opening
    // another route that uses the same renderer.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    try {
      final selection = await Navigator.push<TiniCoverViewResult>(
        context,
        MaterialPageRoute(
          builder: (_) => TiniCoverPreviewScreen(
            videoPath: widget.videoPath,
            previewBuilder: widget.pendingPreviewBuilder,
            previewStart: widget.pendingPreviewStart,
            isImage: widget.pendingPreviewIsImage,
            coverFraction: _selectedCoverFraction,
            coverDesign: _selectedCoverDesign,
            fullName: widget.fullName,
            username: widget.username,
            profileImg: widget.profileImg,
            soundTitle: widget.title,
            soundCover: widget.cover,
            soundSource: widget.source,
          ),
        ),
      );
      if (!mounted) return;
      if (selection != null) {
        setState(() {
          _selectedCoverFraction = selection.fraction;
          _selectedCoverDesign = selection.design;
        });
        final controller = _pendingController ?? _videoPlayerController;
        if (controller != null && controller.value.isInitialized) {
          _seekPreviewToCover(controller);
        }
        if (selection.publish) {
          await _handlePublish();
        }
      }
    } finally {
      if (mounted && _coverPreviewOpen) {
        setState(() => _coverPreviewOpen = false);
      }
    }
  }

  void _handleSaveDraft() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("تم الحفظ كمسودة بنجاح")));
  }

  Future<void> _handlePublish() async {
    if (_isLoading) return;
    final postProv = Provider.of<PostProvider>(context, listen: false);
    if (postProv.isPublishingInBackground) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('هناك منشور قيد التجهيز أو الرفع. انتظر اكتماله.'),
      ));
      return;
    }
    setState(() => _isLoading = true);

    // Retain the original mandatory box title/rules gate before publishing.
    if (_isMysteryBox && _selectedBoxRarity != null) {
      final title = _boxTitleController.text.trim();
      if (title.isEmpty || title.length < 10) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(title.isEmpty
              ? 'عنوان الصندوق إجباري ولا يمكن النشر بدونه'
              : 'العنوان يجب أن يكون 10 أحرف على الأقل'),
          backgroundColor: errorRed,
        ));
        setState(() => _isLoading = false);
        return;
      }
      final accepted = await Navigator.push<bool>(context, MaterialPageRoute(
        builder: (_) => MysteryBoxRulesScreen(rarity: _selectedBoxRarity!),
      ));
      if (!mounted) return;
      if (accepted != true) {
        setState(() => _isLoading = false);
        return;
      }
    }
    if (!mounted) return;
    final auth = Provider.of<custom.AuthProvider>(context, listen: false);
    if (!auth.profileCompleted || !auth.isAuthChecked) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('يرجى إكمال بيانات الحساب أولاً'),
      ));
      setState(() => _isLoading = false);
      return;
    }

    // Freeze all settings before popping this route. The task below MUST NOT
    // read widget, State, controllers, or a disposed BuildContext afterward.
    final navigatorContext = Navigator.of(context).context;
    final render = widget.prepareVideo;
    final initialPath = widget.videoPath;
    final caption = _captionController.text.trim();
    final mentions = List<String>.of(_selectedMentions);
    final hashtags = HashtagService().extractHashtags(caption);
    final location = postProv.selectedLocation;
    final boxTitle = _isMysteryBox ? _boxTitleController.text.trim() : '';
    final boxRarity = _selectedBoxRarity;
    final privacy = _privacy;
    final commentPrivacy = _commentPrivacy;
    final allowDownload = _allowDownload;
    final allowDuet = _allowDuet;
    final saveToDevice = _saveToDevice;
    final showWatermark = _showWatermark;
    final selectedCoverFraction = _selectedCoverFraction;
    final selectedCoverDesign = _selectedCoverDesign;
    final isDuet = widget.isDuet;
    final duetUrl = widget.duetVideoUrl;
    final layout = widget.selectedLayout;
    final originalOwnerId = widget.originalOwnerId;
    final originalAuthorName = widget.originalAuthorName;
    final originalUsername = widget.originalUsername;
    final songTitle = widget.title;
    final songArtist = widget.artist;
    final songCover = widget.cover;
    final songSource = widget.source;
    final uid = auth.uid;
    final fullName = auth.fullName;
    final username = auth.username;
    final profileImg = auth.profileImg;
    final isPrivate = auth.isPrivate;

    final started = postProv.startPublication(() async {
      // 1. Render the frozen project on the user's phone. Never upload the
      // source clip instead if export fails or produces an empty path.
      var pathReadyToUpload = initialPath;
      var finalVideoAlreadyEncoded = false;
      if (render != null) {
        final rendered = await render();
        if (rendered == null || rendered.isEmpty || !await File(rendered).exists()) {
          throw StateError('فشل تصدير الفيديو النهائي؛ لم تُنشر النسخة الأصلية');
        }
        pathReadyToUpload = rendered;
        // A different path from VideoProcessor is an FFmpeg-produced MP4.
        // When no rendering occurred, retain the source compression path.
        finalVideoAlreadyEncoded = rendered != initialPath;
      }
      if (!await File(pathReadyToUpload).exists()) {
        throw StateError('ملف الفيديو غير موجود');
      }

      // 2. Extract actual output metadata; the publish preview may still be
      // showing the unrendered source clip (and could already be disposed).
      var exactDuration = 5.0;
      var videoWidth = 1.0;
      var videoHeight = 1.0;
      VideoPlayerController? metadata;
      try {
        metadata = VideoPlayerController.file(File(pathReadyToUpload));
        await metadata.initialize();
        exactDuration = metadata.value.duration.inMilliseconds / 1000.0;
        videoWidth = metadata.value.size.width;
        videoHeight = metadata.value.size.height;
      } catch (error) {
        debugPrint('[Tini Publication] Media metadata: $error');
      } finally {
        if (metadata != null) await metadata.dispose();
      }

      // 3. Retain the security/moderation checks, but run them off the publish
      // route. A rejection prevents the upload and appears on Home.
      postProv.setPublicationPhase('جاري فحص المحتوى...');
      var captionRes = ModerationResult(allowed: true);
      if (caption.isNotEmpty) {
        captionRes = await ModerationService.checkTextDetailed(caption);
        if (captionRes.isUnavailable) {
          throw StateError('تعذّر فحص الوصف. لم يُنشر الفيديو؛ حاول مجدداً.');
        }
        if (!captionRes.allowed) {
          throw StateError('الوصف محظور: ${captionRes.reason}');
        }
      }
      if (boxTitle.isNotEmpty) {
        final boxRes = await ModerationService.checkTextDetailed(boxTitle);
        if (boxRes.isUnavailable) {
          throw StateError('تعذّر فحص عنوان الصندوق. لم يُنشر الفيديو؛ حاول مجدداً.');
        }
        if (!boxRes.allowed) throw StateError('عنوان الصندوق محظور: ${boxRes.reason}');
      }
      var videoRes = ModerationResult(allowed: true);
      Directory? framesDir;
      try {
        final durationMs =
            (exactDuration * 1000).round().clamp(1, 2147483647).toInt();
        final times = <int>[0, durationMs ~/ 4, durationMs ~/ 2,
            durationMs * 3 ~/ 4, durationMs > 500 ? durationMs - 500 : 0];
        framesDir = await (await getTemporaryDirectory())
            .createTemp('tini_checked_frames_');
        final frames = <String>[];
        for (var i = 0; i < times.length; i++) {
          final photo = File('${framesDir.path}/frame_$i.jpg');
          await _tiniExtractPublicationStill(
            videoPath: pathReadyToUpload,
            at: Duration(milliseconds: times[i]),
            output: photo,
          );
          frames.add(base64Encode(await photo.readAsBytes()));
        }
        videoRes = await ModerationService.checkFullVideoDetailed(frames);
        if (videoRes.isUnavailable) {
          throw StateError('تعذّر فحص الفيديو. لم يُنشر؛ حاول مجدداً.');
        }
        if (!videoRes.allowed) {
          throw StateError('الفيديو محظور: ${videoRes.reason}');
        }
      } on StateError {
        rethrow; // Invalid frames and safety rejections always block upload.
      } catch (error, stack) {
        debugPrint('[Tini Publication] Video frame check: $error');
        debugPrintStack(stackTrace: stack);
        throw StateError('تعذّر استخراج إطارات الفيديو للفحص. لم يُنشر؛ حاول مجدداً.');
      } finally {
        if (framesDir != null) {
          try {
            await framesDir.delete(recursive: true);
          } on FileSystemException {
            // The OS may already have removed these temporary stills.
          }
        }
      }
      final isAgeRestricted = captionRes.isAgeRestricted || videoRes.isAgeRestricted;
      final verified = await MentionPrivacyService.validateMentions(
        text: caption, selected: mentions, senderUid: uid,
      );
      final validMentions = verified.keys.toList();

      // 4. Preserve duet and save-to-gallery paths exactly where they were
      // relative to upload. Only the beginning of the task moved.
      if (isDuet && duetUrl != null) {
        final merged = await VideoProcessor.mergeDuetVideo(
          videoPath: pathReadyToUpload, duetVideoUrl: duetUrl,
          selectedLayout: layout, maxDuration: exactDuration,
        );
        if (merged == null || merged.isEmpty || !await File(merged).exists()) {
          throw StateError('تعذّر تجهيز الديو؛ لم يتم نشر فيديو غير مكتمل');
        }
        pathReadyToUpload = merged;
        finalVideoAlreadyEncoded = true; // Duet merge uses FFmpeg H.264.
      }
      String? thumbPath;
      try {
        final durationMs = (exactDuration * 1000).round();
        final selectedMs = (durationMs * selectedCoverFraction)
            .round().clamp(0, durationMs > 200 ? durationMs - 200 : 0).toInt();
        // Keep the existing R2 .webp thumbnail contract. It uses an image
        // encoder only; the source MP4 is never re-encoded.
        final temp = await getTemporaryDirectory();
        final thumbnail = File('${temp.path}/tini_post_thumb_'
            '${DateTime.now().microsecondsSinceEpoch}.webp');
        if (selectedCoverDesign?.hasText == true) {
          // Decode the actual FINISHED video at the chosen cover time, then
          // draw the saved Arabic/Unicode artwork onto its still image.
          // No separate video render and no changes to the R2 WebP contract.
          final still = File('${temp.path}/tini_cover_still_'
              '${DateTime.now().microsecondsSinceEpoch}.jpg');
          try {
            await _tiniExtractPublicationStill(
              videoPath: pathReadyToUpload,
              at: Duration(milliseconds: selectedMs),
              output: still,
            );
            thumbPath = await TiniCoverComposer.composeWebp(
              sourceStill: still,
              destination: thumbnail,
              design: selectedCoverDesign!,
            );
          } finally {
            if (await still.exists()) await still.delete();
          }
        } else {
          // The untouched path still gets exactly the original WebP still.
          thumbPath = await _tiniExtractPublicationStill(
            videoPath: pathReadyToUpload,
            at: Duration(milliseconds: selectedMs),
            output: thumbnail,
            webp: true,
          );
        }
      } catch (error) {
        debugPrint('[Tini Publication] Thumbnail: $error');
        // A chosen designed cover must not silently publish without its text.
        if (selectedCoverDesign?.hasText == true) rethrow;
      }

      if (saveToDevice) {
        var pathForSaving = pathReadyToUpload;
        if (showWatermark) {
          final watermarked = await VideoProcessor.createSaveableVideoWithWatermark(
            inputPath: pathReadyToUpload, username: username,
          );
          if (watermarked != null && watermarked.isNotEmpty) {
            pathForSaving = watermarked;
          }
        }
        try {
          await Gal.putVideo(pathForSaving, album: 'Tini');
        } catch (error) {
          debugPrint('[Tini Publication] Gallery save: $error');
        }
      }

      // 5. Upload only a fully rendered, verified output.
      postProv.setPublicationPhase(finalVideoAlreadyEncoded
          ? 'جاري رفع الفيديو...' : 'جاري ضغط الفيديو ورفعه...', rendering: false);
      final realPostId = await postProv.uploadPost(
        context: navigatorContext,
        videoPath: pathReadyToUpload,
        finalVideoAlreadyEncoded: finalVideoAlreadyEncoded,
        thumbnailPath: thumbPath ?? '',
        videoWidth: videoWidth, videoHeight: videoHeight,
        description: caption, boxTitle: boxTitle,
        fullName: fullName, username: username, profileImg: profileImg,
        uid: uid, ownerIsPrivateAccount: isPrivate,
        originalAuthorName: originalAuthorName,
        originalUsername: originalUsername,
        duetOriginalOwnerId: originalOwnerId,
        privacy: privacy, commentPrivacy: commentPrivacy,
        allowDownload: allowDownload, allowDuet: allowDuet,
        isAgeRestricted: isAgeRestricted,
        saveToDevice: saveToDevice, showWatermark: showWatermark,
        mentions: validMentions, hashtags: hashtags, location: location,
        isDuet: isDuet, duetFrom: duetUrl,
        songTitle: songTitle, songArtist: songArtist,
        songCover: songCover, songSource: songSource,
        isMysteryBox: boxRarity != null, boxRarity: boxRarity,
      );
      if (realPostId == null) {
        throw StateError('تعذّر رفع الفيديو. لم يكتمل النشر.');
      }
      // Notification side effects should not retain the disposed route.
      for (final mention in validMentions) {
        await _tiniLogPublishMention(mention, realPostId);
      }
      if (isDuet && originalOwnerId != null && originalOwnerId.isNotEmpty &&
          originalOwnerId != uid) {
        await _tiniLogPublishDuet(originalOwnerId, fullName, realPostId);
      }
    });
    if (!started) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    // Navigation does NOT await FFmpeg or upload. Home observes PostProvider.
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<custom.AuthProvider>(context);
    final postProv = Provider.of<PostProvider>(context);

    // [Tini]: شرط التحقق من ظهور واجهة الهاشتاجات
    bool showHashtagOverlay = postProv.suggestedHashtags.isNotEmpty;

    return Scaffold(
      backgroundColor: bgDark,
      body: SafeArea(
        child: Column(
          children: [
            // 1. البار العلوي (AppBar)
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      icon: const Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const Text(
                    'نشر منشور جديد',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            // 2. منطقة الفيديو والوصف (تم التعديل لدعم الديو)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                                            auth.profileImg.isNotEmpty
                         ? CachedNetworkImage(
                              imageUrl: auth.profileImg,
                              cacheKey: auth.profileImg,
                              useOldImageOnUrlChange: false,
                              imageBuilder: (context, imageProvider) => CircleAvatar(
                                radius: 18,
                                backgroundColor: surfaceDark,
                                backgroundImage: imageProvider,
                              ),
                              placeholder: (context, url) => CircleAvatar(
                                radius: 18,
                                backgroundColor: surfaceDark,
                                child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: titiTeal)),
                              ),
                              errorWidget: (context, url, error) => CircleAvatar(
                                radius: 18,
                                backgroundColor: surfaceDark,
                                child: Text(
                                  auth.fullName.isNotEmpty? auth.fullName[0].toUpperCase() : "?",
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                ),
                              ),
                            )
                          : CircleAvatar(
                              radius: 18,
                              backgroundColor: surfaceDark,
                              child: Text(
                                auth.fullName.isNotEmpty? auth.fullName[0].toUpperCase() : "?",
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                              ),
                            ),
                      const SizedBox(width: 10),
                      Text(
                        auth.fullName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _captionController,
                          maxLines: 4,
                          enabled: !postProv.isUploading,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'اكتب وصفاً لتألقك اليوم...',
                            hintStyle: TextStyle(
                              color: Colors.grey,
                              fontSize: 13,
                            ),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                                            // [إضافة تقنية 2 و 3]: حاوية المعاينة المزدوجة للديو
                      Container(
                        width: 100,
                        height: 150,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: surfaceDark,
                          border: Border.all(color: Colors.white10),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          children: [
                            _coverPreviewOpen
                                ? const SizedBox.expand(child: ColoredBox(color: Colors.black))
                                : widget.pendingPreviewIsImage
                                ? Image.file(File(widget.videoPath), fit: BoxFit.cover,
                                    width: double.infinity, height: double.infinity)
                                : widget.pendingPreviewBuilder != null
                                ? widget.pendingPreviewBuilder!(
                                    _pendingPosition,
                                    _onPendingControllerReady,
                                    _onPendingControllerReleased,
                                    _togglePendingPreview)
                                : widget.isDuet && _duetController != null
                                ? Builder(
                                    builder: (context) {
                                      // 1. جنباً إلى جنب (تقسيم رأسي)
                                      if (widget.selectedLayout ==
                                          DuetLayout.sideBySide) {
                                        return Row(
                                          children: [
                                            Expanded(
                                              child: VideoPlayer(
                                                _videoPlayerController!,
                                              ),
                                            ),
                                            Container(
                                              width: 0.5,
                                              color: Colors.white12,
                                            ),
                                            Expanded(
                                              child: VideoPlayer(
                                                _duetController!,
                                              ),
                                            ),
                                          ],
                                        );
                                      }
                                      // 2. أعلى وأسفل (تقسيم أفقي)
                                      else if (widget.selectedLayout ==
                                          DuetLayout.topBottom) {
                                        return Column(
                                          children: [
                                            Expanded(
                                              child: VideoPlayer(
                                                _duetController!,
                                              ),
                                            ),
                                            Container(
                                              height: 0.5,
                                              color: Colors.white12,
                                            ),
                                            Expanded(
                                              child: VideoPlayer(
                                                _videoPlayerController!,
                                              ),
                                            ),
                                          ],
                                        );
                                      }
                                      // 3. رد الفعل (React)
                                      else if (widget.selectedLayout ==
                                          DuetLayout.react) {
                                        return Stack(
                                          children: [
                                            Positioned.fill(
                                              child: VideoPlayer(
                                                _videoPlayerController!,
                                              ),
                                            ),
                                            Positioned(
                                              top: 5,
                                              left: 5,
                                              child: Container(
                                                width: 35,
                                                height: 50,
                                                decoration: BoxDecoration(
                                                  border: Border.all(
                                                    color: Colors.white,
                                                    width: 0.5,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  child: VideoPlayer(
                                                    _duetController!,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        );
                                      }
                                      // 4. الشاشة الخضراء (Green Screen)
                                      else {
                                        return Stack(
                                          children: [
                                            Positioned.fill(
                                              child: VideoPlayer(
                                                _duetController!,
                                              ),
                                            ),
                                            Positioned.fill(
                                              child: Opacity(
                                                opacity: 0.7,
                                                child: VideoPlayer(
                                                  _videoPlayerController!,
                                                ),
                                              ),
                                            ),
                                          ],
                                        );
                                      }
                                    },
                                  )
                                : (_videoPlayerController != null &&
                                          _videoPlayerController!
                                              .value
                                              .isInitialized
                                      ? Positioned.fill(
                                          child: VideoPlayer(
                                            _videoPlayerController!,
                                          ),
                                        )
                                      : Center(
                                          child: CircularProgressIndicator(
                                            color: titiTeal,
                                            strokeWidth: 2,
                                          ),
                                        )),
                            if (widget.prepareVideo != null && widget.pendingPreviewBuilder != null)
                              Positioned(left: 0, right: 0, bottom: 0,
                                child: Container(
                                  color: const Color(0xBB0F1720),
                                  padding: const EdgeInsets.all(3),
                                  child: const Text('معاينة المؤثرات',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 10,
                                        color: Colors.white)),
                                )),
                            Positioned.fill(
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(onTap: _onCoverTap),
                              ),
                            ),
                            if (_selectedCoverDesign?.hasText == true)
                              Positioned.fill(child: IgnorePointer(
                                child: CustomPaint(
                                  painter: TiniCoverArtworkPainter(
                                    design: _selectedCoverDesign!),
                                ),
                              )),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: const IgnorePointer(child: Text('معاينة',
                                  style: TextStyle(color: Colors.white, fontSize: 10,
                                      shadows: [Shadow(color: Colors.black, blurRadius: 5)]))),
                            ),
                            Positioned(
                              left: 0, right: 0, bottom: 0,
                              child: IgnorePointer(
                                child: Container(
                                  color: const Color(0xBB0F1720),
                                  padding: const EdgeInsets.symmetric(vertical: 7),
                                  child: const Text('تعديل الغلاف',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.white,
                                        fontWeight: FontWeight.bold, fontSize: 12)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Divider(color: Colors.white10, thickness: 1, height: 1),

            // 3. منطقة المحتوى الديناميكي (إما الخيارات أو واجهة الهاشتاجات الكاملة)
            Expanded(
              child: Stack(
                children: [
                  // الطبقة الأساسية: الخيارات العادية
                  SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      children: [
                        if (postProv.isUploading)
                          Column(
                            children: [
                              LinearProgressIndicator(
                                value: postProv.uploadProgress,
                                backgroundColor: Colors.white10,
                                color: titiTeal,
                                minHeight: 3,
                              ),
                              Text(
                                "جاري النشر... ${(postProv.uploadProgress * 100).toStringAsFixed(0)}%",
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                        _buildActionTile(
                          Icons.alternate_email,
                          _selectedMentions.isEmpty
                              ? 'منشن أشخاص'
                              : 'تم منشن ${_selectedMentions.length} شخص',
                          onTap: () async {
                            final List<String>? result =
                                await showModalBottomSheet<List<String>>(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (context) => MentionPickerSheet(
                                    alreadySelected: _selectedMentions,
                                  ),
                                );
                            if (result!= null) {
  setState(() {
    // نحسب مين انضاف ومين انحذف
    final added = result.where((u) =>!_selectedMentions.contains(u)).toList();
    final removed = _selectedMentions.where((u) =>!result.contains(u)).toList();

    for (var username in added) {
      _captionController.text += _captionController.text.isEmpty? "@$username " : " @$username ";
    }
    for (var username in removed) {
      _captionController.text = _captionController.text.replaceAll("@$username", "").replaceAll(" ", " ").trim();
    }

    _selectedMentions = result;
  });
}
                          },
                        ),
                        _buildActionTile(
                          Icons.tag,
                          'إضافة هاشتاقات',
                          onTap: () {
                            String currentText = _captionController.text;
                            _captionController.text =
                                currentText +
                                (currentText.isEmpty ||
                                        currentText.endsWith(' ')
                                    ? '#'
                                    : ' #');
                            _captionController.selection =
                                TextSelection.fromPosition(
                                  TextPosition(
                                    offset: _captionController.text.length,
                                  ),
                                );
                          },
                        ),
                        Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            _buildActionTile(
                              Icons.location_on_outlined,
                              postProv.selectedLocation.isEmpty
                                  ? 'إضافة موقع'
                                  : postProv.selectedLocation,
                              onTap: () async {
                                final String? result =
                                    await showModalBottomSheet<String>(
                                      context: context,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.transparent,
                                      builder: (context) =>
                                          const LocationPickerSheet(),
                                    );
                                if (result != null) {
                                  postProv.updateLocation(result);
                                }
                              },
                            ),
                            if (postProv.selectedLocation.isNotEmpty)
                              Positioned(
                                left: 15,
                                child: GestureDetector(
                                  onTap: () {
                                    postProv.clearLocation();
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF1C1C1E),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      color: Color(0xFFE53935),
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        // [Tini V30.3]: واجهة بحر الصناديق - تمت الإضافة هنا
                        _buildSwitchTile(
                          Icons.inventory_2_outlined,
                          "📦 نشر كصندوق نادر",
                          _isMysteryBox,
                          (v) => setState(() => _isMysteryBox = v),
                        ),
                        if (_isMysteryBox)
  Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "اختر نوع الصندوق",
          style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _buildRarityCard('bronze', 'برونزي', 50, Icons.workspace_premium, Colors.brown),
        _buildRarityCard('silver', 'فضي', 250, Icons.military_tech, Colors.grey),
        _buildRarityCard('gold', 'ذهبي', 600, Icons.emoji_events, Colors.amber),
        _buildRarityCard('diamond', 'ماسي', 1000, Icons.diamond, Colors.cyan),
      ],
    ),
  ),

  if (_isMysteryBox && _selectedBoxRarity != null)
  Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    child: TextField(
      controller: _boxTitleController,
      maxLength: 60,
      textAlign: TextAlign.right,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: 'عنوان الصندوق * إجباري',
        labelStyle: const TextStyle(color: Color(0xFFE53935)),
        hintText: 'مثال: سر زيادة المتابعين 10K بشهر',
        hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
        filled: true,
        fillColor: surfaceDark,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE53935), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE53935), width: 2),
        ),
      ),
    ),
  ),
                        const Divider(color: Colors.white10, thickness: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              "إعدادات الخصوصية والتفاعل",
                              style: TextStyle(
                                color: titiTeal,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        _buildPrivacyOption(),
                        _buildCommentPrivacyOptionTile(),
                        _buildSwitchTile(
                          Icons.download_for_offline_outlined,
                          "السماح بتنزيل الفيديو للآخرين",
                          _allowDownload,
                          (v) => setState(() => _allowDownload = v),
                        ),
                        _buildSwitchTile(
                          Icons.repeat_rounded,
                          "السماح بالديو (Duet)",
                          _allowDuet,
                          (v) => setState(() => _allowDuet = v),
                        ),
                        const Divider(color: Colors.white10, thickness: 1),
                        _buildSwitchTile(
                          Icons.save_alt,
                          "حفظ النسخة على جهازي",
                          _saveToDevice,
                          (v) => setState(() => _saveToDevice = v),
                        ),
                        if (_saveToDevice)
                          _buildSwitchTile(
                            Icons.branding_watermark_outlined,
                            "إضافة العلامة المائية (Tini)",
                            _showWatermark,
                            (v) => setState(() => _showWatermark = v),
                          ),
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),

                  // الطبقة العلوية: واجهة الهاشتاجات (تظهر فقط عند كتابة #)
                  if (showHashtagOverlay)
                    Container(
                      color: bgDark,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            child: Text(
                              "هاشتاقات مقترحة لصفحتك",
                              style: TextStyle(
                                color: titiTeal,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Expanded(
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              itemCount: postProv.suggestedHashtags.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(
                                    color: Colors.white10,
                                    height: 1,
                                  ),
                              itemBuilder: (context, index) {
                                final tag = postProv.suggestedHashtags[index];
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: titiTeal.withValues(
                                      alpha: 0.1,
                                    ),
                                    child: Icon(
                                      Icons.tag,
                                      color: titiTeal,
                                      size: 20,
                                    ),
                                  ),
                                  title: Text(
                                    tag['name'],
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        "${tag['count']}",
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const Text(
                                        "مشاهدة",
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                  onTap: () => _applyHashtag(tag['name']),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // 4. منطقة الأزرار الثابتة
            if (!showHashtagOverlay)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: bgDark,
                  border: const Border(
                    top: BorderSide(color: Colors.white10, width: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: postProv.isUploading
                              ? null
                              : _handleSaveDraft,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: draftGrey,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'مسودة',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: postProv.isPublishingInBackground || _isLoading
                              ? null
                              : _handlePublish,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: titiTeal,
                            disabledBackgroundColor: titiTeal.withValues(
                              alpha: 0.3,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                          child: postProv.isUploading || _isLoading
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  'نشر الآن',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacyOption() {
    return ListTile(
      leading: const Icon(Icons.lock_outline, color: Colors.white, size: 20),
      title: const Text(
        "من يمكنه رؤية الفيديو",
        style: TextStyle(color: Colors.white, fontSize: 14),
      ),
      trailing: DropdownButton<String>(
        value: _privacy,
        dropdownColor: surfaceDark,
        underline: const SizedBox(),
        icon: const Icon(
          Icons.keyboard_arrow_down,
          color: Colors.white54,
          size: 20,
        ),
        items: const [
          DropdownMenuItem(
            value: "public",
            child: Text(
              "الجميع",
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          DropdownMenuItem(
            value: "friends",
            child: Text(
              "الأصدقاء",
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          DropdownMenuItem(
            value: "private",
            child: Text(
              "أنا فقط",
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
        onChanged: (value) => setState(() => _privacy = value!),
      ),
    );
  }

    Widget _buildCommentPrivacyOptionTile() {
    return ListTile(
      leading: const Icon(Icons.comment_outlined, color: Colors.white, size: 20),
      title: const Text("التعليقات", style: TextStyle(color: Colors.white, fontSize: 14)),
      trailing: DropdownButton<String>(
        value: _commentPrivacy,
        dropdownColor: surfaceDark,
        underline: const SizedBox(),
        icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white54, size: 20),
        items: const [
          DropdownMenuItem(value: "comment_everyone", child: Text("الجميع", style: TextStyle(color: Colors.white, fontSize: 13))),
          DropdownMenuItem(value: "comment_friends", child: Text("الأصدقاء", style: TextStyle(color: Colors.white, fontSize: 13))),
          DropdownMenuItem(value: "comment_nobody", child: Text("لا أحد", style: TextStyle(color: Colors.white, fontSize: 13))),
        ],
        onChanged: (value) => setState(() => _commentPrivacy = value!),
      ),
    );
  }

  Widget _buildSwitchTile(
    IconData icon,
    String title,
    bool value,
    Function(bool) onChanged,
  ) {
    return ListTile(
      leading: Icon(icon, color: Colors.white, size: 20),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      trailing: Transform.scale(
        scale: 0.8,
        child: Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: titiTeal,
          activeTrackColor: titiTeal.withValues(alpha: 0.3),
        ),
      ),
    );
  }

  Widget _buildActionTile(
    IconData icon,
    String title, {
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.white, size: 20),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      trailing: const Icon(
        Icons.arrow_forward_ios,
        color: Colors.white24,
        size: 12,
      ),
      onTap: onTap,
    );
  }



  Widget _buildRarityCard(String rarity, String title, int price, IconData icon, Color color) {
  final bool isSelected = _selectedBoxRarity == rarity;
  return GestureDetector(
    onTap: () {
      setState(() {
        _selectedBoxRarity = isSelected ? null : rarity;
      });
    },
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSelected ? titiTeal.withValues(alpha:0.2) : surfaceDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? titiTeal : Colors.white12,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                Text('$price عملة', style: TextStyle(color: titiTeal, fontSize: 13)),
              ],
            ),
          ),
          if (isSelected) Icon(Icons.check_circle, color: titiTeal, size: 22),
        ],
      ),
    ),
  );
}

  void _onCaptionChanged() {
    if (!mounted || _isApplyingHashtag) return;
    final text = _captionController.text;
    if (text.endsWith('#') || text.contains('#')) {
      context.read<PostProvider>().searchHashtags(text);
    } else {
      context.read<PostProvider>().searchHashtags("");
    }
  }

  void _applyHashtag(String hashtag) {
    setState(() {
      _isApplyingHashtag = true;
    });

    final text = _captionController.text;
    final lastHashIndex = text.lastIndexOf('#');
    if (lastHashIndex != -1) {
      final newText = "${text.substring(0, lastHashIndex)}#$hashtag ";
      _captionController.text = newText;
      _captionController.selection = TextSelection.fromPosition(
        TextPosition(offset: _captionController.text.length),
      );
    }

    context.read<PostProvider>().searchHashtags("");

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _isApplyingHashtag = false;
        });
      }
    });
  }
}
