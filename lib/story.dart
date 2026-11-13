import 'video_playback_handoff.dart';
import 'user_documents.dart';
import 'dart:async';
import 'audience_access.dart';
import 'audience_gate.dart';
import 'dart:math'; // ✅ NEW
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'story_provider.dart';
import 'chat_provider.dart'; // ✅ مهم
import 'tini_messaging_notice.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'share_story_sheet.dart';
import 'story_reply_bar.dart';
import 'emoji_burst_overlay.dart';
import 'emoji_picker.dart';
import 'post_provider.dart';
import 'titi_single_engine.dart';

// ألوان Tini الرسمية
const Color kBg = Color(0xFF0F1720);
const Color kSurface = Color(0xFF1A222C);
const Color kErrorRed = Color(0xFFE53935);

class Story extends StatelessWidget {
  final String userId;
  const Story({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return AudienceProfileGate(
      uid: userId,
      child: StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
.collection('stories')
.doc(userId)
.collection('items')
.orderBy('createdAt', descending: true)
.limit(20)
.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            backgroundColor: kBg,
            body: Center(child: CircularProgressIndicator(color: Colors.teal)),
          );
        }
                final stories = snap.data!.docs;
        if (stories.isEmpty) {
          return const Scaffold(
            backgroundColor: kBg,
            body: Center(child: Text('لا يوجد ستوري', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal'))),
          );
        }
        return StoryScreen(stories: stories, ownerUid: userId);
      },
      ),
    );
  }
}

class StoryScreen extends StatefulWidget {
  final List<QueryDocumentSnapshot> stories;
  final String ownerUid;

  const StoryScreen({
    super.key,
    required this.stories,
    required this.ownerUid,
  });

  @override
  State<StoryScreen> createState() => _StoryScreenState();
}

class _StoryScreenState extends State<StoryScreen> with WidgetsBindingObserver {
  ModalRoute<dynamic>? _storyRoute;
  @override
  void didChangeDependencies() { super.didChangeDependencies(); _storyRoute = ModalRoute.of(context); }
  int currentIndex = 0;
  double percent = 0.0;
  Timer? _timer;
  VideoPlayerController? _videoController;
  VideoPlayerController? _nextController;
  VideoPlayerController? _prevController;
  bool _isPaused = false;
  bool _isTransitioning = false;
  final TextEditingController _replyController = TextEditingController();
  bool _isLiked = false;
  bool _audienceAllowed = false;
  String? _audienceViewerUid;
  int _storyGeneration = 0;

  // ✅ FIX 1: كاش لللايكات
  final Map<String, bool> _likesCache = {};
  // ✅ FIX 2: ValueNotifier بدل setState كل 50ms
  final ValueNotifier<double> progressNotifier = ValueNotifier(0.0);
  VoidCallback? _videoListener;

  // ✅ NEW EMOJI SYSTEM
  final FocusNode _replyFocus = FocusNode();
  List<Widget> _flyingEmojis = [];
  final List<String> quickEmojis = ['😂','😍','👏'];
  final List<String> expandedEmojis = ['🤩','😳','😂','😍','🎉','🔥','👏','❤️'];
  final Random _rnd = Random();

    @override
  void initState() {
    super.initState();
    VideoPlaybackRegistry.watch(this, () {
      if (!mounted || _storyRoute?.isCurrent != true || !_canViewStory || widget.stories.isEmpty) return null;
      final id = widget.stories[currentIndex].id;
      return VideoPlaybackOrigin(engine: VideoPlaybackEngine.external, url: '', postId: id,
        isVisible: () => mounted && _storyRoute?.isCurrent == true && _canViewStory &&
          widget.stories.isNotEmpty && widget.stories[currentIndex].id == id,
        suspendExternal: () async {
          _timer?.cancel();
          if (mounted) setState(() => _isPaused = true);
          await _videoController?.pause();
          await _nextController?.pause(); await _prevController?.pause();
        },
        resumeExternal: () async {
          if (!mounted || _storyRoute?.isCurrent != true || !_canViewStory) return;
          setState(() => _isPaused = false);
          if (_videoController?.value.isInitialized == true) {
            await _playAuthorizedStory(_videoController);
            _startTimer(isVideo: true);
          } else { _startTimer(); }
        },
      );
    });
    WidgetsBinding.instance.addObserver(this);
    _replyFocus.addListener(() => setState(() {}));
    
    // [Fix صوت الهوم]: وقف كل فيديوهات الهوم نهائياً أول ما ينفتح الستوري
       WidgetsBinding.instance.addPostFrameCallback((_) {
  try {
    TitiSingleEngine().player.pause();
  } catch (_) {}
});

    _audienceViewerUid = FirebaseAuth.instance.currentUser?.uid;
    AudienceAccess.instance.addListener(_onAudienceChanged);
    _audienceAllowed = AudienceAccess.instance.canViewProfile(widget.ownerUid);
    if (_audienceAllowed) _loadStory();
  }

  bool get _canViewStory =>
      _audienceViewerUid == FirebaseAuth.instance.currentUser?.uid &&
      AudienceAccess.instance.canViewProfile(widget.ownerUid);

  void _onAudienceChanged() {
    if (!mounted) return;
    final viewerUid = FirebaseAuth.instance.currentUser?.uid;
    final allowed = AudienceAccess.instance.canViewProfile(widget.ownerUid);
    if (allowed == _audienceAllowed && viewerUid == _audienceViewerUid) return;
    _audienceViewerUid = viewerUid;
    _audienceAllowed = allowed;
    _storyGeneration++;
    _likesCache.clear();
    _timer?.cancel();
    if (_videoListener != null) {
      _videoController?.removeListener(_videoListener!);
    }
    _videoController?.dispose();
    _nextController?.dispose();
    _prevController?.dispose();
    _videoController = null;
    _nextController = null;
    _prevController = null;
    _videoListener = null;
    _isTransitioning = false;
    _isPaused = false;
    if (allowed) _loadStory();
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant StoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldStory = oldWidget.stories.isNotEmpty &&
        currentIndex < oldWidget.stories.length
        ? oldWidget.stories[currentIndex] : null;
    currentIndex = currentIndex.clamp(0,
        widget.stories.isEmpty ? 0 : widget.stories.length - 1);
    final story = widget.stories.isEmpty ? null : widget.stories[currentIndex];
    final oldData = oldStory?.data() as Map<String, dynamic>?;
    final data = story?.data() as Map<String, dynamic>?;
    if (oldWidget.ownerUid != widget.ownerUid || oldStory?.id != story?.id ||
        oldData?['mediaUrl'] != data?['mediaUrl']) {
      _storyGeneration++;
      _loadStory();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted || !_canViewStory) return;

    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _videoController?.pause();
      _nextController?.pause();
      _prevController?.pause();
      _timer?.cancel();
      setState(() => _isPaused = true);
    } else if (state == AppLifecycleState.resumed && _storyRoute?.isCurrent == true) {
      if (_isPaused) {
        setState(() => _isPaused = false);
        if (_videoController?.value.isInitialized == true) {
          _playAuthorizedStory(_videoController);
          _startTimer(isVideo: true);
        } else {
          _startTimer();
        }
      }
    }
  }

  Future<void> _playAuthorizedStory(VideoPlayerController? controller) async {
    final generation = _storyGeneration;
    if (!mounted || _storyRoute?.isCurrent != true || !_canViewStory || controller == null ||
        !identical(_videoController, controller)) return;
    await controller.play();
    if (!mounted || _storyRoute?.isCurrent != true || !_canViewStory || generation != _storyGeneration ||
        !identical(_videoController, controller)) {
      await controller.setVolume(0);
      await controller.pause();
    }
  }

  void _loadStory() {
    final generation = ++_storyGeneration;
    _timer?.cancel();
    if (_videoListener!= null) {
      _videoController?.removeListener(_videoListener!);
    }
    _videoController?.dispose();
    _videoController = null;
    _nextController?.dispose();
    _prevController?.dispose();
    _nextController = null;
    _prevController = null;
    percent = 0.0;
    progressNotifier.value = 0.0; // ✅ FIX

        if (widget.stories.isEmpty || !_canViewStory) {
      return;
    }

    final data = widget.stories[currentIndex].data() as Map<String, dynamic>;
    final String mediaUrl = data['mediaUrl']?? '';
    final String type = data['type']?? 'image';

    _markAsSeen(widget.stories[currentIndex].id);
    _checkIfLiked(); // ✅

    if (type == 'video' && mediaUrl.isNotEmpty) {
      final controller = VideoPlayerController.networkUrl(Uri.parse(mediaUrl));
      _videoController = controller;
      controller.setLooping(false);
      controller.initialize().then((_) {
          if (mounted && generation == _storyGeneration && _canViewStory &&
              identical(_videoController, controller)) {
            _playAuthorizedStory(controller);
            // ✅ FIX 3: listener نهاية الفيديو
            _videoListener = () {
              if (!_canViewStory || generation != _storyGeneration ||
                  !identical(_videoController, controller) ||
                  !controller.value.isInitialized) return;
              final pos = _videoController!.value.position;
              final dur = _videoController!.value.duration;
              if (dur.inMilliseconds > 0 && pos >= dur &&!_videoController!.value.isPlaying &&!_isPaused) {
                _nextStory();
              }
            };
            controller.addListener(_videoListener!);
            _startTimer(isVideo: true);
            setState(() {});
          }
        }).catchError((Object error) {
          if (mounted && generation == _storyGeneration && _canViewStory) {
            setState(() {});
          }
        });
    } else {
      _startTimer();
    }

    _preloadNext();
    _preloadPrevious();
  }

  void _preloadNext() {
    if (!_canViewStory) return;
    _nextController?.dispose();
    _nextController = null;
    final nextIndex = currentIndex + 1;
    if (nextIndex < widget.stories.length) {
      final nextData = widget.stories[nextIndex].data() as Map<String, dynamic>;
      if (nextData['type'] == 'video' && (nextData['mediaUrl']?? '').isNotEmpty) {
        _nextController = VideoPlayerController.networkUrl(
          Uri.parse(nextData['mediaUrl']),
        )..setLooping(false)..initialize();
      }
    }
  }

  void _preloadPrevious() {
    if (!_canViewStory) return;
    _prevController?.dispose();
    _prevController = null;
    final prevIndex = currentIndex - 1;
    if (prevIndex >= 0) {
      final prevData = widget.stories[prevIndex].data() as Map<String, dynamic>;
      if (prevData['type'] == 'video' && (prevData['mediaUrl']?? '').isNotEmpty) {
        _prevController = VideoPlayerController.networkUrl(
          Uri.parse(prevData['mediaUrl']),
        )..setLooping(false)..initialize();
      }
    }
  }

  void _markAsSeen(String storyId) {
    if (!_canViewStory) return;
    Provider.of<StoryProvider>(context, listen: false)
.markStoryAsSeen(widget.ownerUid, storyId);
    // ✅ NEW: عد المشاهدات مرة واحدة
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid!= null && uid!= widget.ownerUid) {
      final storyRef = FirebaseFirestore.instance.collection('stories').doc(widget.ownerUid).collection('items').doc(storyId);
      storyRef.update({
        'views': FieldValue.arrayUnion([uid]),
        'viewedBy': FieldValue.arrayUnion([uid]),
      });
    }
  }

  // ✅ تحقق من اللايك - مع كاش
  Future<void> _checkIfLiked() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final storyId = widget.stories[currentIndex].id;
    final generation = _storyGeneration;
    if (!_canViewStory) return;
    if (_likesCache.containsKey(storyId)) {
      if (mounted) setState(() => _isLiked = _likesCache[storyId]!);
      return;
    }
    final doc = await FirebaseFirestore.instance
.collection('stories')
.doc(widget.ownerUid)
.collection('items')
.doc(storyId)
.collection('likes')
.doc(uid)
.get();
    if (!mounted || generation != _storyGeneration ||
        uid != FirebaseAuth.instance.currentUser?.uid || !_canViewStory) return;
    setState(() => _isLiked = doc.exists);
    _likesCache[storyId] = doc.exists;
  }

  void _startTimer({bool isVideo = false}) {
    if (!_canViewStory) return;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (t) {
      if (!mounted || _storyRoute?.isCurrent != true || _isPaused || !_canViewStory) return;
      double step = isVideo &&
                _videoController!= null &&
                _videoController!.value.isInitialized
  ? 50 / _videoController!.value.duration.inMilliseconds
            : 0.01;
      // ✅ FIX: بدون setState
      progressNotifier.value = (progressNotifier.value + step).clamp(0.0, 1.0);
      percent = progressNotifier.value;
      if (progressNotifier.value >= 1) {
        progressNotifier.value = 0;
        percent = 0;
        _nextStory();
      }
    });
  }

  void _nextStory() {
    if (!_canViewStory) return;
    if (_isTransitioning) return;
    _isTransitioning = true;
    _timer?.cancel();
    if (currentIndex < widget.stories.length - 1) {
      _storyGeneration++;
      currentIndex++;
      _prevController?.dispose();
      _prevController = _videoController;
      _videoController = _nextController;
      _nextController = null;
      percent = 0.0;
      progressNotifier.value = 0.0;

      final data = widget.stories[currentIndex].data() as Map<String, dynamic>;
      _markAsSeen(widget.stories[currentIndex].id);
      _checkIfLiked();

      if (data['type'] == 'video') {
        if (_videoController!= null && _videoController!.value.isInitialized) {
          _playAuthorizedStory(_videoController);
          _startTimer(isVideo: true);
          setState(() {});
        } else {
          _loadStory();
        }
      } else {
        _startTimer();
        setState(() {});
      }
      _preloadNext();
    } else {
      if (mounted) Navigator.pop(context);
    }
    Future.delayed(const Duration(milliseconds: 300), () {
      _isTransitioning = false;
    });
  }

  void _previousStory() {
    if (!_canViewStory) return;
    if (_isTransitioning) return;
    _isTransitioning = true;
    _timer?.cancel();
    if (currentIndex > 0) {
      _storyGeneration++;
      currentIndex--;
      _nextController?.dispose();
      _nextController = _videoController;
      _videoController = _prevController;
      _prevController = null;
      percent = 0.0;
      progressNotifier.value = 0.0;

      final data = widget.stories[currentIndex].data() as Map<String, dynamic>;
      _markAsSeen(widget.stories[currentIndex].id);
      _checkIfLiked();

      if (data['type'] == 'video') {
        if (_videoController!= null && _videoController!.value.isInitialized) {
          _videoController!.seekTo(Duration.zero);
          _playAuthorizedStory(_videoController);
          _startTimer(isVideo: true);
          setState(() {});
        } else {
          _loadStory();
        }
      } else {
        _startTimer();
        setState(() {});
      }
      _preloadPrevious();
    }
    Future.delayed(const Duration(milliseconds: 300), () {
      _isTransitioning = false;
    });
  }

  bool _sendingStoryMessage = false;

  // إشعار نتيجة الرد لا يتحول إلى نجاح إلا بعد تأكيد حفظ الرسالة.
  void _showStorySendFailure(ChatFailureReason? reason) {
    if (!mounted) return;
    TiniMessagingNotice.showFailure(
      ScaffoldMessenger.maybeOf(context), reason,
      action: 'إرسال الرد',
    );
  }

  void _showStorySendSuccess() {
    if (!mounted) return;
    TiniMessagingNotice.showSuccess(
      ScaffoldMessenger.maybeOf(context), 'تم إرسال الرد');
  }

  // ✅ إرسال رد - مع بريفيو الستوري
  Future<void> _sendReply() async {
    if (!_canViewStory || _sendingStoryMessage) return;
    final text = _replyController.text.trim();
    if (text.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _sendingStoryMessage = true;
    try {
      final storyId = widget.stories[currentIndex].id;
      final story = widget.stories[currentIndex].data() as Map<String, dynamic>;
      final provider = Provider.of<ChatProvider>(context, listen: false);
      final isActuallyFriend = await provider.checkIfFriend(uid, widget.ownerUid);
      if (!mounted || !_canViewStory || uid != FirebaseAuth.instance.currentUser?.uid) return;
      // ابدأ الشات
      final startResult = await provider.startChatWithReason(
        viewedUid: widget.ownerUid,
        displayFullName: story['fullName']?? '',
        displayProfileImg: story['profileImg']?? '',
        isFriend: isActuallyFriend,
      );
      if (!mounted || !_canViewStory || uid != FirebaseAuth.instance.currentUser?.uid) return;
      if (!startResult.isSuccess || startResult.value == null) {
        _showStorySendFailure(startResult.failureReason);
        return;
      }

      // ابعت الرسالة مع replyTo = الستوري
      final result = await provider.sendMessageWithReason(
        roomId: startResult.value!,
        senderId: uid,
        receiverId: widget.ownerUid,
        type: 'text',
        text: text,
        isFriend: isActuallyFriend,
        replyTo: {
          'messageId': storyId,
          'sourceType': 'story',
          'sourceOwnerUid': widget.ownerUid,
          'sourceStoryId': storyId,
          'text': '',
          'type': story['type'],
          'senderId': widget.ownerUid,
          'mediaUrl': story['mediaUrl'],
        },
      );
      if (!mounted || uid != FirebaseAuth.instance.currentUser?.uid) return;
      if (!result.isSuccess) {
        _showStorySendFailure(result.failureReason);
        return;
      }
      if (_replyController.text.trim() == text) _replyController.clear();
      _showStorySendSuccess();
    } catch (e) {
      if (mounted) _showStorySendFailure(ChatFailureReason.technicalError);
    } finally {
      _sendingStoryMessage = false;
    }
  }

  // ✅ NEW: إرسال إيموجي كـ رد
  Future<void> _sendEmojiReaction(String emoji) async {
    if (!_canViewStory || _sendingStoryMessage) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _sendingStoryMessage = true;
    try {
      final storyId = widget.stories[currentIndex].id;
      final story = widget.stories[currentIndex].data() as Map<String, dynamic>;
      final provider = Provider.of<ChatProvider>(context, listen: false);
      final isActuallyFriend = await provider.checkIfFriend(uid, widget.ownerUid);
      if (!mounted || !_canViewStory || uid != FirebaseAuth.instance.currentUser?.uid) return;
      final startResult = await provider.startChatWithReason(
        viewedUid: widget.ownerUid,
        displayFullName: story['fullName']?? '',
        displayProfileImg: story['profileImg']?? '',
        isFriend: isActuallyFriend,
      );
      if (!mounted || !_canViewStory || uid != FirebaseAuth.instance.currentUser?.uid) return;
      if (!startResult.isSuccess || startResult.value == null) {
        _showStorySendFailure(startResult.failureReason);
        return;
      }
      final result = await provider.sendMessageWithReason(
        roomId: startResult.value!,
        senderId: uid,
        receiverId: widget.ownerUid,
        type: 'emoji',
        text: emoji,
        isFriend: isActuallyFriend,
        replyTo: {
          'messageId': storyId,
          'sourceType': 'story',
          'sourceOwnerUid': widget.ownerUid,
          'sourceStoryId': storyId,
          'text': '',
          'type': story['type'],
          'senderId': widget.ownerUid,
          'mediaUrl': story['mediaUrl'],
          'thumbnailUrl': story['thumbnailUrl']??'',
        },
      );
      if (!mounted || uid != FirebaseAuth.instance.currentUser?.uid) return;
      if (result.isSuccess) {
        _showStorySendSuccess();
      } else {
        _showStorySendFailure(result.failureReason);
      }
    } catch (e) {
      if (mounted) _showStorySendFailure(ChatFailureReason.technicalError);
    } finally {
      _sendingStoryMessage = false;
    }
  }

  void _triggerBurst(String emoji) {
    setState(() {
      _flyingEmojis = List.generate(10, (i) {
        final startX = _rnd.nextDouble() * MediaQuery.of(context).size.width;
        final endX = startX + (_rnd.nextDouble() * 100 - 50);
        return TweenAnimationBuilder(
          tween: Tween<double>(begin: 0, end: 1),
          duration: Duration(milliseconds: 1200 + _rnd.nextInt(400)),
          builder: (_, double v, __) {
            return Positioned(
              left: startX + (endX - startX) * v,
              bottom: 150 + (MediaQuery.of(context).size.height * 0.7 * v),
              child: Opacity(
                opacity: 1 - v,
                child: Text(emoji, style: TextStyle(fontSize: 32 + _rnd.nextInt(12).toDouble())),
              ),
            );
          },
        );
      });
    });
    Future.delayed(const Duration(seconds: 2), () { if (mounted) setState(() => _flyingEmojis.clear()); });
  }

  void _onQuickEmoji(String emoji) {
    _triggerBurst(emoji);
    _sendEmojiReaction(emoji);
  }

  // ✅ لايك - ينحفظ في stories likes - مع حذف
  void _toggleLike() {
    if (!_canViewStory) return;
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final storyId = widget.stories[currentIndex].id;
    final ref = FirebaseFirestore.instance.collection('stories').doc(widget.ownerUid).collection('items').doc(storyId).collection('likes').doc(uid);
    final storyRef = FirebaseFirestore.instance.collection('stories').doc(widget.ownerUid).collection('items').doc(storyId);

    setState(() => _isLiked =!_isLiked);
    _likesCache[storyId] = _isLiked;

    if (_isLiked) {
      ref.set({'ts': FieldValue.serverTimestamp()});
      storyRef.update({'likesCount': FieldValue.increment(1)});
    } else {
      ref.delete();
      storyRef.update({'likesCount': FieldValue.increment(-1)});
    }
  }

  Future<void> _shareStory() async {
  if (!_canViewStory) return;
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  final story = widget.stories[currentIndex].data() as Map<String, dynamic>;

  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1A222C),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => ShareStorySheet(story: {...story,
      'sourceStoryId': widget.stories[currentIndex].id,
      'sourceOwnerUid': widget.ownerUid,
      'sourceType': 'story'}, currentUid: uid),
  );
}

  Future<void> _deleteStory() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid!= widget.ownerUid) return;

    final storyId = widget.stories[currentIndex].id;
    final bool isLastStory = widget.stories.length == 1;
    // ✅ FIX 4: احذف أولاً ثم pop
    await Provider.of<StoryProvider>(context, listen: false).deleteStory(storyId);
    if (isLastStory && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    VideoPlaybackRegistry.unwatch(this);
    AudienceAccess.instance.removeListener(_onAudienceChanged);
    _storyGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    if (_videoListener!= null) _videoController?.removeListener(_videoListener!);
    _videoController?.dispose();
    _nextController?.dispose();
    _prevController?.dispose();
    _replyController.dispose();
    _replyFocus.dispose(); // ✅ NEW
    progressNotifier.dispose(); // ✅
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.stories.isEmpty || !_canViewStory) {
      return const Scaffold(backgroundColor: kBg);
    }

    final data = widget.stories[currentIndex].data() as Map<String, dynamic>;

    return Scaffold(
      backgroundColor: kBg,
      body: GestureDetector(
        onLongPressStart: (_) {
          setState(() => _isPaused = true);
          _videoController?.pause();
        },
        onLongPressEnd: (_) {
          if (!_canViewStory) return;
          setState(() => _isPaused = false);
          if (_videoController?.value.isInitialized == true) {
            _playAuthorizedStory(_videoController);
          }
        },
        onTapDown: (d) {
          final w = MediaQuery.of(context).size.width;
          final h = MediaQuery.of(context).size.height;
          // ✅ تجاهل الضغط في المنطقة السفلية (الأزرار)
          if (d.globalPosition.dy > h - 120) return;

          if (d.globalPosition.dx < w / 3) {
            _previousStory();
          } else if (d.globalPosition.dx > w * 2 / 3) {
            _nextStory();
          }
        },
        onVerticalDragUpdate: (details) {
          if (details.delta.dy > 10 && mounted) Navigator.pop(context);
        },
        child: Stack(
          children: [
            Center(child: _buildMedia(data)),
            // ✅ NEW: الإيموجي الطائرة
            EmojiBurstOverlay(flyingEmojis: _flyingEmojis),
            // ✅ أيقونة pause
            if (_isPaused)
              const Center(child: Icon(Icons.pause_circle_filled, size: 80, color: Colors.white54)),
            // ✅ NEW: لوحة الإيموجي عند فتح الكيبورد
            if (_replyFocus.hasFocus)
              EmojiPicker(
                emojis: expandedEmojis,
                onPick: (e) {
                  _sendEmojiReaction(e);
                  _replyFocus.unfocus();
                },
                onClose: () => _replyFocus.unfocus(),
              ),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: List.generate(widget.stories.length, (i) {
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            // ✅ FIX: ValueListenableBuilder
                            child: ValueListenableBuilder<double>(
                              valueListenable: progressNotifier,
                              builder: (_, val, __) => LinearProgressIndicator(
                                value: i == currentIndex? val : (i < currentIndex? 1.0 : 0.0),
                                backgroundColor: Colors.white30,
                                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                minHeight: 2,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Hero(
                          tag: 'profile_avatar_hero_${data['uid']}',
                          child: CircleAvatar(
                            radius: 18,
                            backgroundImage: CachedNetworkImageProvider(data['profileImg']?? ''),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                data['fullName']?? 'مستخدم جديد',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontFamily: 'Tajawal',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  shadows: [Shadow(blurRadius: 8, color: Colors.black54, offset: Offset(0, 1))],
                                ),
                              ),
                              Text(
                                '@${data['username']?? 'user'}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontFamily: 'Tajawal',
                                  fontSize: 12,
                                  shadows: [Shadow(blurRadius: 8, color: Colors.black54, offset: Offset(0, 1))],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (FirebaseAuth.instance.currentUser?.uid == widget.ownerUid)
                          StreamBuilder<DocumentSnapshot>(
                            stream: FirebaseFirestore.instance.collection('stories').doc(widget.ownerUid).collection('items').doc(widget.stories[currentIndex].id).snapshots(),
                            builder: (context, snap) {
                              final dataMap = snap.data?.data() as Map<String, dynamic>?;
                              final views = (dataMap?['views'] as List?)?.length ?? dataMap?['viewsCount'] ?? 0;
                              final likes = dataMap?['likesCount'] ?? 0;
                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.visibility_outlined, color: Colors.white70, size: 16),
                                  const SizedBox(width: 3),
                                  Text('$views', style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Tajawal')),
                                  const SizedBox(width: 10),
                                  const Icon(Icons.favorite_border, color: Colors.white70, size: 16),
                                  const SizedBox(width: 3),
                                  Text('$likes', style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Tajawal')),
                                  const SizedBox(width: 8),
                                ],
                              );
                            },
                          ),
                        if (FirebaseAuth.instance.currentUser?.uid == widget.ownerUid)
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: kErrorRed, shadows: [Shadow(blurRadius: 8, color: Colors.black87, offset: Offset(0, 1))]),
                            onPressed: _deleteStory,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ✅ NEW - حماية الردود على القصص - FIXED
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: FutureBuilder<DocumentSnapshot>(
                future: UserDocuments.readable(FirebaseFirestore.instance, widget.ownerUid).get(),
                builder: (context, ownerSnap) {
                  if (!ownerSnap.hasData) return const SizedBox.shrink();
                  final ownerData = ownerSnap.data!.data() as Map<String, dynamic>? ?? {};
                  final String replyPrivacy = ownerData['storyReplyPrivacy'] ?? 'all_followers';
                  final String myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
                  final bool isOwner = myUid == widget.ownerUid;

                  // صاحب الستوري يشوف البار دايماً
                  if (isOwner) {
                    return StoryReplyBar(
                      onShare: _shareStory,
                      onLike: _toggleLike,
                      isLiked: _isLiked,
                      controller: _replyController,
                      focusNode: _replyFocus,
                      quickEmojis: quickEmojis,
                      onQuickEmoji: _onQuickEmoji,
                      onSend: _sendReply,
                      onChanged: () => setState(() {}),
                    );
                  }

                  // none = تم إيقاف الردود
                  if (replyPrivacy == 'none') {
                    return Container(
                      width: double.infinity,
                      color: kSurface.withOpacity(0.9),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                      child: const SafeArea(
                        top: false,
                        child: Center(child: Text('تم إيقاف الردود على هذه القصة', style: TextStyle(color: Colors.white54, fontFamily: 'Tajawal', fontSize: 14))),
                      ),
                    );
                  }

                  // mutual = بس الأصدقاء
                  if (replyPrivacy == 'mutual') {
                    return FutureBuilder<bool>(
                      future: Provider.of<ChatProvider>(context, listen: false).checkIfFriend(myUid, widget.ownerUid),
                      builder: (context, friendSnap) {
                        if (!friendSnap.hasData) return const SizedBox.shrink();
                        if (friendSnap.data == true) {
                          return StoryReplyBar(
                            onShare: _shareStory,
                            onLike: _toggleLike,
                            isLiked: _isLiked,
                            controller: _replyController,
                            focusNode: _replyFocus,
                            quickEmojis: quickEmojis,
                            onQuickEmoji: _onQuickEmoji,
                            onSend: _sendReply,
                            onChanged: () => setState(() {}),
                          );
                        }
                        return Container(
                          width: double.infinity,
                          color: kSurface.withOpacity(0.9),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                          child: const SafeArea(
                            top: false,
                            child: Center(child: Text('تم إيقاف الردود على هذه القصة', style: TextStyle(color: Colors.white54, fontFamily: 'Tajawal', fontSize: 14))),
                          ),
                        );
                      },
                    );
                  }

                  // all_followers = الكل
                  return StoryReplyBar(
                    onShare: _shareStory,
                    onLike: _toggleLike,
                    isLiked: _isLiked,
                    controller: _replyController,
                    focusNode: _replyFocus,
                    quickEmojis: quickEmojis,
                    onQuickEmoji: _onQuickEmoji,
                    onSend: _sendReply,
                    onChanged: () => setState(() {}),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMedia(Map<String, dynamic> data) {
    if (!_canViewStory) return const SizedBox.shrink();
    final url = data['mediaUrl']?? '';
    final thumb = data['thumbnailUrl']?? '';

    if (data['type'] == 'video') {
      // ✅ عرض مثل انستغرام - thumbnail أولاً
      return Stack(
        fit: StackFit.expand,
        children: [
          if (thumb.isNotEmpty)
            CachedNetworkImage(
              imageUrl: thumb,
              fit: BoxFit.contain,
              placeholder: (c, u) => Container(color: Colors.black),
              errorWidget: (c, e, s) => Container(color: Colors.black),
            )
          else
            Container(color: Colors.black),

          if (_videoController!= null && _videoController!.value.isInitialized)
            Center(
              child: AspectRatio(
                aspectRatio: _videoController!.value.aspectRatio,
                child: VideoPlayer(_videoController!),
              ),
            ),
        ],
      );
    }

    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.contain,
      placeholder: (c, u) => const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF), strokeWidth: 2)),
      errorWidget: (c, e, s) => const Icon(Icons.broken_image, color: Colors.white54, size: 50),
    );
  }
}