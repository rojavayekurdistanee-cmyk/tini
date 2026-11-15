import 'video_playback_handoff.dart';
import 'banner_manager.dart';
import 'dart:ui';
import 'audience_access.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'auth_provider.dart' as custom;
import 'post_provider.dart';
import 'post_like_button.dart';
import 'post_comments_sheet.dart';
import 'package:detectable_text_field/detectable_text_field.dart';
import 'hashtag_service.dart';
import 'create_post_screen.dart';
import 'video_processor.dart';
import 'home_screen.dart';
import 'dart:math';

import 'user_profile_sheet.dart';
import 'profile_screen.dart'; // [Tini - Mention]: فتح البروفايل عند الضغط على @
import 'search_provider.dart';

import 'story_ring.dart';

import 'package:cloud_functions/cloud_functions.dart';
import 'people_you_may_know_carousel.dart';
import 'titi_video_player.dart';
import 'package:preload_page_view/preload_page_view.dart';
import 'titi_single_engine.dart';
import 'titi_profile_engine.dart';
import 'block_service.dart'; // [المركز]
import 'video_reactions_overlay.dart'; // [Tini - Owner Reactions Overlay]

class PostViewScreen extends StatefulWidget {
  final List<DocumentSnapshot> posts;
  final int initialIndex;
  final String? thumbnailUrl;
  final bool hideBars;
  final Function(bool)? onCommentsToggle;
  final bool openComments;
  final String? highlightCommentId;
  final bool showSearchBar;
  final String? searchQuery;
  final bool isFromTerminated;
  final bool isFromProfileGrid;
  // [Tini - Owner Reactions Overlay] - تفعيل صريح من شبكة فيديوهات صاحب الحساب فقط.
  final bool showOwnerReactionsOverlay;
  final Function(int)? onIndexChanged;
  final bool enablePeopleCarousel;
  // Retained home tabs may rebuild after audience changes while off screen.
  final bool isFeedActive;
  final bool isEmbeddedFeed;
  final bool isBannerNavigation;
  final bool playbackManagedByNavigation;

  const PostViewScreen({
    super.key,
    required this.posts,
    required this.initialIndex,
    this.thumbnailUrl,
    this.hideBars = false,
    this.onCommentsToggle,
    this.openComments = false,
    this.highlightCommentId,
    this.showSearchBar = false,
    this.searchQuery,
    this.isFromTerminated = false,
    this.isFromProfileGrid = false,
    this.showOwnerReactionsOverlay = false,
    this.onIndexChanged,
    this.enablePeopleCarousel = false,
    this.isFeedActive = true,
    this.isEmbeddedFeed = false,
    this.isBannerNavigation = false,
    this.playbackManagedByNavigation = false,
  });

  @override
  State<PostViewScreen> createState() => _PostViewScreenState();
}

class _PostViewScreenState extends State<PostViewScreen> {
  late PreloadPageController _pageController;
  int _currentIndex = 0;
  ModalRoute<dynamic>? _playbackRoute;
  bool get _navigationOwnsPlayback => widget.playbackManagedByNavigation ||
      (widget.isBannerNavigation && widget.isFromTerminated);
  bool get _playbackVisible => mounted && widget.isFeedActive && (_playbackRoute?.isCurrent ?? true);
  late List<DocumentSnapshot> _stablePosts;
  bool _isCommentsOpen = false;
  bool _initialCommentsHandled = false;
  bool _commentsMuted = false;
  double _volumeBeforeComments = 100;
  String? _highlightCommentInPanel;
  bool _highlightTemporarilyInPanel = false;
  // [Tini - Owner Reactions Overlay] - تعطيل حركة الفقاعات أثناء فتح بروفايل كامل.
  bool _isOverlayProfileOpen = false;
  Set<String> _viewedInSession = {};
  Timer? _viewTimer;

  // [Fix] دالة موحدة تجيب أفضل رابط - hls أولاً ثم videoUrl
  String _getBestUrl(dynamic post) {
    final doc = post is DocumentSnapshot ? post : null;
    final data = doc != null
        ? doc.data() as Map<String, dynamic>?
        : post as Map<String, dynamic>?;
    if (data == null || !_audience.canViewPost(data, postId: doc?.id)) return '';
    final hls = (data['hlsPath'] as String?)?.trim()?? "";
    if (hls.isNotEmpty) return hls;
    return (data['videoUrl'] as String?)?? "";
  }

  bool get _isNotificationMode =>
      widget.posts.length == 1 && widget.openComments;

  late int _carouselPos;
  bool _showCarousel = true;

  // [AUDIENCE CONTROL - ADDITION] - صمام أمان ثاني احتياط فقط
  final _audience = AudienceAccess.instance;

  bool _canViewPost(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    return data != null && data['isDeleted'] != true &&
        _audience.canViewPost(data, postId: doc.id);
  }

  void _stopRestrictedSelection(DocumentSnapshot doc, {bool lock = false}) {
    if (!widget.isFeedActive) return;
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final currentUrl = widget.isFromProfileGrid
        ? TitiProfileEngine().currentUrl : TitiSingleEngine().currentUrl;
    if (currentUrl.isEmpty || ![data['hlsPath'], data['videoUrl'], data['hlsUrl']].contains(currentUrl)) return;
    if (widget.isFromProfileGrid) {
      if (lock) { TitiProfileEngine().stop(); } else { TitiProfileEngine().pause(); }
    } else {
      if (lock) { TitiSingleEngine().stop(); } else { TitiSingleEngine().pause(); }
    }
  }

  void _onAudienceChanged() {
    if (!mounted) return;
    if (_stablePosts.isNotEmpty && _currentIndex < _stablePosts.length &&
        !_canViewPost(_stablePosts[_currentIndex])) {
      _viewTimer?.cancel();
      _stopRestrictedSelection(_stablePosts[_currentIndex]);
      if (_isCommentsOpen) _closeCommentsSheet();
    }
    if (widget.isFeedActive && _stablePosts.isNotEmpty &&
        _currentIndex < _stablePosts.length && _canViewPost(_stablePosts[_currentIndex])) {
      if (_viewTimer?.isActive != true) _scheduleSmartView(_stablePosts[_currentIndex].id);
      if (widget.openComments && !_initialCommentsHandled) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _tryInitialComments());
      }
    }
    setState(() {});
  }

  void _tryInitialComments() {
    if (!mounted || !widget.isFeedActive || _initialCommentsHandled ||
        !widget.openComments || _stablePosts.isEmpty ||
        _currentIndex >= _stablePosts.length || !_canViewPost(_stablePosts[_currentIndex])) return;
    _initialCommentsHandled = true;
    _showCommentsSheet(highlightCommentId: widget.highlightCommentId);
  }

  void removePostInstantly(String ownerId) {
    if (!mounted) return;
    if (widget.isFromProfileGrid) {
      TitiProfileEngine().stop();
    } else {
      TitiSingleEngine().stop();
    }
    setState(() {
      _stablePosts.removeWhere((p) {
        final data = p.data() as Map<String, dynamic>;
        return data['uid'] == ownerId;
      });
      if (_stablePosts.isEmpty) {
        _currentIndex = 0;
      } else {
        if (_currentIndex >= _stablePosts.length) {
          _currentIndex = _stablePosts.length - 1;
        }
        final nextUrl = _getBestUrl(_stablePosts[_currentIndex]);
        if (nextUrl.isNotEmpty) {
          if (widget.isFromProfileGrid) {
            TitiProfileEngine().playSingleUrl(nextUrl);
          } else {
            TitiSingleEngine().playUrl(nextUrl);
          }
        }
        _pageController.jumpToPage(_currentIndex);
      }
    });
  }

@override
void initState() {
  super.initState();
  _currentIndex = widget.initialIndex;
  _pageController = PreloadPageController(
    initialPage: widget.initialIndex,
  );
  _stablePosts = List.from(widget.posts);
  BannerManager.instance.watchVisiblePost(this, () {
    if (!mounted || !widget.isFeedActive || ModalRoute.of(context)?.isCurrent != true ||
        _currentIndex < 0 || _currentIndex >= _stablePosts.length) { return null; }
    return _stablePosts[_currentIndex].id;
  });
  VideoPlaybackRegistry.watch(this, () {
    if (!_playbackVisible || _stablePosts.isEmpty || _currentIndex >= _stablePosts.length) return null;
    final doc = _stablePosts[_currentIndex];
    final url = _getBestUrl(doc);
    if (url.isEmpty || !_canViewPost(doc)) return null;
    final id = doc.id;
    return VideoPlaybackOrigin(
      engine: widget.isFromProfileGrid ? VideoPlaybackEngine.profile : VideoPlaybackEngine.home,
      url: url, postId: id,
      isVisible: () => _playbackVisible && _currentIndex < _stablePosts.length &&
        _stablePosts[_currentIndex].id == id && _canViewPost(_stablePosts[_currentIndex]),
    );
  });
  // [TRASH FILTER - ADDITION] - فلترة المحذوفات أولاً
  _stablePosts = _stablePosts.where((doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) return false;
    if (data['isDeleted'] == true) return false;
    return true;
  }).toList();
  // [AUDIENCE CONTROL] - فلترة فورية: اذا المشاهد تحت 18 احذف فيديوهات 18+ قبل التشغيل - FIXED V2
  _audience.addListener(_onAudienceChanged);
  for (final doc in _stablePosts) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data != null) _audience.trackPost(data, postId: doc.id);
  }

    // [HARD BLOCK - مركزي من AuthProvider + BlockService - Two Way]
  try {
    final authBlock = Provider.of<custom.AuthProvider>(context, listen: false);
    final blockedSet = authBlock.blockedUsersSet; // [المركز] Set لحظي
    final blockedBySet = authBlock.blockedBySet; // [Two-Way] ناس حاظريني
    if (blockedSet.isNotEmpty || blockedBySet.isNotEmpty) {
      _stablePosts = _stablePosts.where((doc) {
        final data = doc.data() as Map<String, dynamic>?;
        final uid = data?['uid']?.toString()?? '';
        if (uid.isEmpty) return true;
        if (blockedSet.contains(uid)) return false;
        if (blockedBySet.contains(uid)) return false; // [Two-Way] اذا هو حاظرني لا تطلع فيديوهاتي عنده ابدا
        return true;
      }).toList();
      if (_currentIndex >= _stablePosts.length) {
        _currentIndex = _stablePosts.isEmpty? 0 : _stablePosts.length - 1;
      }
    }
  } catch (_) {}

  _showCarousel = widget.enablePeopleCarousel;
  if (_showCarousel) {
    if (_stablePosts.length < 4) {
      // اذا أقل من 4 فيديوهات لا تظهره أبداً مشان ما يخرب الترتيب
      _showCarousel = false;
      _carouselPos = -1;
    } else {
      final random = Random().nextInt(1000);
      const int minPos = 2; // بعد تاني فيديو
      // -2 بيضمن يضل فيديوهين بعده، و 20 هو الحد الأقصى
      final int maxPos = (_stablePosts.length - 2).clamp(minPos, 20).toInt();
      _carouselPos = (minPos + (random % (maxPos - minPos + 1))).toInt();
    }
  } else {
    _carouselPos = -1;
  }

    // بروفايل فقط: شغل فوري قبل البناء
    if (widget.isFromProfileGrid && widget.isFeedActive) {
      try {
        if (_stablePosts.isNotEmpty && _currentIndex < _stablePosts.length) {
          _scheduleSmartView(_stablePosts[_currentIndex].id);
          final url = _getBestUrl(_stablePosts[_currentIndex]);
          if (!_canViewPost(_stablePosts[_currentIndex])) {
            TitiProfileEngine().pause();
          } else if (url.isNotEmpty) {
            String? prevUrl, prevPrevUrl, nextUrl, nextNextUrl, nextNextNextUrl;
            if (_currentIndex > 0) prevUrl = _getBestUrl(_stablePosts[_currentIndex - 1]);
            if (_currentIndex > 1) prevPrevUrl = _getBestUrl(_stablePosts[_currentIndex - 2]);
            if (_currentIndex < _stablePosts.length - 1) nextUrl = _getBestUrl(_stablePosts[_currentIndex + 1]);
            if (_currentIndex < _stablePosts.length - 2) nextNextUrl = _getBestUrl(_stablePosts[_currentIndex + 2]);
            if (_currentIndex < _stablePosts.length - 3) nextNextNextUrl = _getBestUrl(_stablePosts[_currentIndex + 3]);
            TitiProfileEngine().playSingleUrl(url, prevUrl: prevUrl, prevPrevUrl: prevPrevUrl, nextUrl: nextUrl, nextNextUrl: nextNextUrl, nextNextNextUrl: nextNextNextUrl);
          }
        }
      } catch (_) {}
    }

    // Managed notification playback is started once by the navigation handoff.
    // هوم - شغل فوري بدون انتظار فريم
    if (!widget.isFromProfileGrid && widget.isFeedActive) {
      try {
        if (_stablePosts.isNotEmpty && _currentIndex < _stablePosts.length) {
          _scheduleSmartView(_stablePosts[_currentIndex].id);
          final url = _getBestUrl(_stablePosts[_currentIndex]);
          if (!_canViewPost(_stablePosts[_currentIndex])) {
            TitiSingleEngine().pause();
          } else if (url.isNotEmpty &&
              !_navigationOwnsPlayback) {
            String? prevUrl, prevPrevUrl, nextUrl, nextNextUrl, nextNextNextUrl;
            if (_currentIndex > 0) prevUrl = _getBestUrl(_stablePosts[_currentIndex - 1]);
            if (_currentIndex > 1) prevPrevUrl = _getBestUrl(_stablePosts[_currentIndex - 2]);
            if (_currentIndex < _stablePosts.length - 1) nextUrl = _getBestUrl(_stablePosts[_currentIndex + 1]);
            if (_currentIndex < _stablePosts.length - 2) nextNextUrl = _getBestUrl(_stablePosts[_currentIndex + 2]);
            if (_currentIndex < _stablePosts.length - 3) nextNextNextUrl = _getBestUrl(_stablePosts[_currentIndex + 3]);
            TitiSingleEngine().playUrl(url, prevUrl: prevUrl, prevPrevUrl: prevPrevUrl, nextUrl: nextUrl, nextNextUrl: nextNextUrl, nextNextNextUrl: nextNextNextUrl);
          }
        }
      } catch (_) {}
    }

    if (widget.openComments) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _tryInitialComments();
      });
    }

  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _playbackRoute = ModalRoute.of(context);
    // الاعتماد على إشعارات سياسة الجمهور الحية بدلاً من عمر محفوظ في الشاشة.
  }

  @override
  void didUpdateWidget(covariant PostViewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isFeedActive) _viewTimer?.cancel();
    if (widget.isFeedActive && !oldWidget.isFeedActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.isFeedActive && _currentIndex < _stablePosts.length) {
          _handlePageChange(_currentIndex);
          _tryInitialComments();
        }
      });
    }
    if (widget.posts.isEmpty) {
      if (_stablePosts.isNotEmpty && _currentIndex < _stablePosts.length) {
        _stopRestrictedSelection(_stablePosts[_currentIndex]);
      }
      _stablePosts = [];
      _currentIndex = 0;
      _carouselPos = -1;
      _showCarousel = false;
      setState(() {});
      return;
    }
    final bool postsChanged = oldWidget.posts.length!= widget.posts.length ||
        List.generate(widget.posts.length, (i) => i).any((i) =>
            oldWidget.posts[i].id!= widget.posts[i].id ||
            !mapEquals(oldWidget.posts[i].data() as Map<String, dynamic>?, widget.posts[i].data() as Map<String, dynamic>?) ||
            _getBestUrl(oldWidget.posts[i])!=
            _getBestUrl(widget.posts[i]));
    if (postsChanged) {
      final String? currentId =
          _stablePosts.isNotEmpty && _currentIndex < _stablePosts.length
           ? _stablePosts[_currentIndex].id
              : null;
      final bool currentStillExists =
          currentId!= null && widget.posts.any((p) => p.id == currentId);
      _stablePosts = List.from(widget.posts);
      // [TRASH FILTER - ADDITION]
      _stablePosts = _stablePosts.where((doc) {
        final d = doc.data() as Map<String, dynamic>?;
        if (d == null) return false;
        if (d['isDeleted'] == true) return false;
        return true;
      }).toList();

      try {
        final authBlock = Provider.of<custom.AuthProvider>(context, listen: false);
        final blockedSet = authBlock.blockedUsersSet;
        final blockedBySet = authBlock.blockedBySet;
        if (blockedSet.isNotEmpty || blockedBySet.isNotEmpty) {
          _stablePosts = _stablePosts.where((doc) {
            final d = doc.data() as Map<String, dynamic>?;
            final uid = d?['uid']?.toString()?? '';
            if (uid.isEmpty) return true;
            if (blockedSet.contains(uid)) return false;
            if (blockedBySet.contains(uid)) return false; // [Two-Way]
            return true;
          }).toList();
        }
      } catch (_) {}

      // [FIX NEW POST SCROLL - إضافة فقط - ما بتمس أي ميزة]
      bool isNewUpload = false;
      try {
        final postProv = Provider.of<PostProvider>(context, listen: false);
        final newPostId = postProv.lastUploadedPost?.id;
        if (newPostId!= null && _stablePosts.isNotEmpty && _stablePosts[0].id == newPostId) {
          if (oldWidget.posts.isEmpty || oldWidget.posts[0].id!= newPostId) {
            isNewUpload = true;
            _currentIndex = 0;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                if (_stablePosts.isEmpty || _stablePosts[0].id!= newPostId) return;
                _pageController.jumpToPage(0);
                _handlePageChange(0);
              }
            });
          }
        }
      } catch (_) {}

      if (!isNewUpload) {
        final int previousIndex = _currentIndex;
        final int updatedIndex = currentStillExists
            ? _stablePosts.indexWhere((p) => p.id == currentId)
            : (_stablePosts.isEmpty? 0 : _currentIndex.clamp(0, _stablePosts.length - 1).toInt());
        _currentIndex = updatedIndex;
        if (_stablePosts.isNotEmpty && (previousIndex!= updatedIndex || !currentStillExists)) {
          final String selectedId = _stablePosts[updatedIndex].id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _currentIndex < _stablePosts.length && _stablePosts[_currentIndex].id == selectedId) {
              final int pageIndex = _showCarousel && _carouselPos >= 0 && _currentIndex >= _carouselPos
                  ? _currentIndex + 1 : _currentIndex;
              _pageController.jumpToPage(pageIndex);
              if (!currentStillExists) _handlePageChange(_currentIndex);
            }
          });
        }
      }
      setState(() {});
    }
  }

  void _scheduleSmartView(String postId) {
    if (!widget.isFeedActive) return;
    final selected = _stablePosts.where((doc) => doc.id == postId);
    if (selected.isEmpty || !_canViewPost(selected.first)) return;
    if (_viewedInSession.contains(postId)) return;
    _viewTimer?.cancel();

    int idx = _stablePosts.indexWhere((p) => p.id == postId);
    if (idx == -1) return;
    final map = _stablePosts[idx].data() as Map<String, dynamic>;
    int seconds = (map['duration'] as int?)?? TitiSingleEngine().player.state.duration.inSeconds;

    if (seconds == 0) seconds = 5;

    int waitSeconds;
    if (seconds <= 2) waitSeconds = 1;
    else if (seconds <= 6) waitSeconds = 2;
    else waitSeconds = 5;

    debugPrint("👁 VIDEO $seconds sec -> WAIT $waitSeconds");

    _viewTimer = Timer(Duration(seconds: waitSeconds), () {
      if (!mounted || !widget.isFeedActive) return;
      if (_stablePosts.isEmpty || _currentIndex < 0 || _currentIndex >= _stablePosts.length) return;
      if (_stablePosts[_currentIndex].id!= postId) return;
      if (_viewedInSession.contains(postId) || !_canViewPost(_stablePosts[_currentIndex])) return;
      _viewedInSession.add(postId);
      Provider.of<PostProvider>(context, listen: false).incrementView(postId);
    });
  }

    void _handlePageChange(int index) {
    if (!widget.isFeedActive) return;
    if (index < 0 || index >= _stablePosts.length) return;
    _viewTimer?.cancel();
    setState(() {
      _currentIndex = index;
    });
    _scheduleSmartView(_stablePosts[index].id);
    if (_playbackVisible) {
    try {
      if (!_canViewPost(_stablePosts[index])) {
        TitiProfileEngine().pause();
        TitiSingleEngine().pause();
        return;
      }
      final url = _getBestUrl(_stablePosts[index]);
      if (url.isNotEmpty) {
        // جيب الجيران قبل ما تنادي المحرك
        String? prevUrl, prevPrevUrl, nextUrl, nextNextUrl, nextNextNextUrl;
        if (index > 0) prevUrl = _getBestUrl(_stablePosts[index - 1]);
        if (index > 1) prevPrevUrl = _getBestUrl(_stablePosts[index - 2]);
        if (index < _stablePosts.length - 1) nextUrl = _getBestUrl(_stablePosts[index + 1]);
        if (index < _stablePosts.length - 2) nextNextUrl = _getBestUrl(_stablePosts[index + 2]);
        if (index < _stablePosts.length - 3) nextNextNextUrl = _getBestUrl(_stablePosts[index + 3]);

        if (widget.isFromProfileGrid) {
          TitiProfileEngine().playSingleUrl(url, prevUrl: prevUrl, prevPrevUrl: prevPrevUrl, nextUrl: nextUrl, nextNextUrl: nextNextUrl, nextNextNextUrl: nextNextNextUrl);
        } else {
          TitiSingleEngine().playUrl(url, prevUrl: prevUrl, prevPrevUrl: prevPrevUrl, nextUrl: nextUrl, nextNextUrl: nextNextUrl, nextNextNextUrl: nextNextNextUrl);
        }
      }
      // شلنا الـ Future.delayed 400ms و precache - هو كان سبب التأخير
    } catch (_) {}
    }
    if (widget.onIndexChanged!= null) {
      widget.onIndexChanged!(index);
    }
    if (widget.showSearchBar && index >= _stablePosts.length - 5) {
      final searchProvider = Provider.of<SearchProvider>(context, listen: false);
      if (searchProvider.hasMorePosts &&!searchProvider.isLoadingMore) {
        searchProvider.loadMorePosts().then((_) {
          _loadMorePostsToView(searchProvider);
        });
      }
    }
  }

  Future<void> _loadMorePostsToView(SearchProvider searchProvider) async {
    final viewerUid = _audience.viewerUid;
    try {
      final newPostIds = searchProvider.posts
         .skip(_stablePosts.length)
         .map((p) => p['postId'] as String)
         .toList();
      if (newPostIds.isEmpty) return;
      final newDocs = await Future.wait(
        newPostIds.map(
          (id) => FirebaseFirestore.instance.collection('posts').doc(id).get(),
        ),
      );
      if (!mounted || viewerUid != _audience.viewerUid) return;
      final validNewDocs = newDocs.where((d) => d.exists).toList();
      for (final doc in validNewDocs) {
        final data = doc.data();
        if (data != null) _audience.trackPost(data, postId: doc.id);
      }
      if (validNewDocs.isNotEmpty && mounted) {
        setState(() {
          _stablePosts.addAll(validNewDocs);
        });
      }
    } catch (e) {
      debugPrint('Load more to view error: $e');
    }
  }

  // [Tini - Owner Reactions Overlay] - نفس التنقل الكامل الموجود للمناشن، بدون UserProfileSheet.
  Future<void> _openOverlayProfile(String uid) async {
    if (!mounted || uid.isEmpty || _isOverlayProfileOpen) return;

    // [Tini - Overlay Profile Audio] - حفظ حالة فيديو البروفايل قبل التنقل.
    final profileEngine = TitiProfileEngine();
    final originalPlayer = profileEngine.player;
    final wasPlaying = originalPlayer.state.playing;
    final previousVolume = originalPlayer.state.volume;
    final previousUrl = profileEngine.currentUrl;
    final previousPosition = originalPlayer.state.position;

    setState(() => _isOverlayProfileOpen = true);
    try {
      // اكتم الصوت فوراً وأوقف الفيديو بالخلفية قبل فتح البروفايل الكامل.
      await originalPlayer.setVolume(0);
      await profileEngine.pause();
      await profileEngine.lock();
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ProfileScreen(userId: uid)),
      );
    } finally {
      if (mounted) {
        try {
          // الرجوع من ProfileScreen يقفل محرك الفيديو؛ نفك القفل هنا فقط.
          await profileEngine.unlock();

          // لو المستخدم فتح فيديو آخر من البروفايل، نعيد الفيديو السابق وموضعه.
          if (previousUrl.isNotEmpty && profileEngine.currentUrl != previousUrl) {
            await profileEngine.playUrl(previousUrl, autoPlay: false);
            await profileEngine.player.seek(previousPosition);
          }

          // lock() يكتم المشغلات الستة؛ unlock() يعيد صوت النشط فقط.
          // إعادة صوت المشغلات الاحتياطية مع إبقائها متوقفة تمنع كتم الفيديو التالي عند السحب.
          for (int i = 0; i < 6; i++) {
            if (i == profileEngine.activeIndex) continue;
            final inactivePlayer = profileEngine.getPlayerByIndex(i);
            await inactivePlayer.pause();
            await inactivePlayer.setVolume(100);
          }

          // استعادة مستوى الصوت وحالة التشغيل السابقة، حتى لو كان الفيديو مكتوماً أصلاً.
          await profileEngine.player.setVolume(previousVolume);
          if (wasPlaying && _currentIndex < _stablePosts.length && _canViewPost(_stablePosts[_currentIndex])) {
            await profileEngine.play();
          } else {
            await profileEngine.pause();
          }
        } catch (error) {
          debugPrint('[Tini Overlay] Failed to restore profile audio: $error');
        } finally {
          if (mounted) setState(() => _isOverlayProfileOpen = false);
        }
      }
    }
  }

  void _openOverlayComment(String commentId) {
    if (!mounted || commentId.isEmpty || _isCommentsOpen) return;
    _showCommentsSheet(highlightCommentId: commentId, highlightTemporarily: true);
  }

  void _showCommentsSheet({String? highlightCommentId, bool highlightTemporarily = false}) {
    if (!widget.isFeedActive || _stablePosts.isEmpty || _isCommentsOpen || !_canViewPost(_stablePosts[_currentIndex])) return;
    // [Tini - Compact Comments Video] - نفس محرك الفيديو ونفس شاشة التعليقات الأصلية.
    final player = widget.isFromProfileGrid ? TitiProfileEngine().player : TitiSingleEngine().player;
    _volumeBeforeComments = player.state.volume;
    setState(() {
      _isCommentsOpen = true;
      _commentsMuted = _volumeBeforeComments == 0;
      _highlightCommentInPanel = highlightCommentId;
      _highlightTemporarilyInPanel = highlightTemporarily;
    });
    widget.onCommentsToggle?.call(true);
  }

  void _closeCommentsSheet() {
    if (!_isCommentsOpen) return;
    setState(() {
      _isCommentsOpen = false;
      _highlightCommentInPanel = null;
    });
    widget.onCommentsToggle?.call(false);
  }

  Future<void> _toggleCommentsMute() async {
    final player = widget.isFromProfileGrid ? TitiProfileEngine().player : TitiSingleEngine().player;
    if (!_commentsMuted) {
      _volumeBeforeComments = player.state.volume;
      await player.setVolume(0);
    } else {
      await player.setVolume(_volumeBeforeComments > 0 ? _volumeBeforeComments : 100);
    }
    if (mounted) setState(() => _commentsMuted = !_commentsMuted);
  }

@override
void dispose() {
  BannerManager.instance.unwatchVisiblePost(this);
  VideoPlaybackRegistry.unwatch(this);
  _audience.removeListener(_onAudienceChanged);
  _viewTimer?.cancel();
  _pageController.dispose();
  // Retained feed pages share one engine. A replaced page must not lock the
  // engine already selected by its replacement; route/tab owners handle it.
  if (widget.isEmbeddedFeed || widget.isBannerNavigation) {
    super.dispose();
    return;
  }
  if (widget.isFromProfileGrid) {
    if (_stablePosts.isNotEmpty && _currentIndex < _stablePosts.length) {
      _stopRestrictedSelection(_stablePosts[_currentIndex], lock: _canViewPost(_stablePosts[_currentIndex]));
    }
  } else {
    if (widget.isFeedActive && (widget.posts.length == 1 || widget.isFromTerminated)) {
      // لا تعمل stop هون - بس فك القفل، الهوم بيرجع لحاله
      try { TitiSingleEngine().unlockForHome(); } catch (_) {}
    } else if (_stablePosts.isNotEmpty && _currentIndex < _stablePosts.length) {
      _stopRestrictedSelection(_stablePosts[_currentIndex], lock: _canViewPost(_stablePosts[_currentIndex]));
    }
  }
  super.dispose();
}

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<custom.AuthProvider>(context, listen: true);
    final postProvider = Provider.of<PostProvider>(context, listen: false);
    final double screenWidth = MediaQuery.of(context).size.width;
    const Color titiDarkBG = Color(0xFF000000);

    // FIX: نكتشف اذا نحن بالهوم فيد - بالهوم ما بدنا شريط البوست فيو السفلي لانو شريط الهوم موجود لحالو
    final bool isSingle = _stablePosts.length == 1;
    final bool isHomeFeed = widget.hideBars &&
        !widget.isFromProfileGrid &&
        !widget.showSearchBar &&
        !widget.isFromTerminated &&
        context.findAncestorStateOfType<HomeScreenState>() != null;

    return LayoutBuilder(
      builder: (context, viewport) {
        // [Home Video Scroll] - الاعتماد على الارتفاع الفعلي لصفحة السكرول فقط داخل الهوم.
        final double screenHeight = isHomeFeed && viewport.hasBoundedHeight
            ? viewport.maxHeight
            : MediaQuery.of(context).size.height;
        final double topBarHeight = widget.isFromProfileGrid
            ? MediaQuery.of(context).size.height * 0.034
            : screenHeight * 0.032;
        final double bottomBarHeight = screenHeight * 0.0775;
        final double effectiveBottomBarHeight = isHomeFeed? 0 : bottomBarHeight;

        return Scaffold(
      backgroundColor: titiDarkBG,
      body: RepaintBoundary(
        child: LayoutBuilder(builder: (context, bodyConstraints) {
          // Scaffold has already removed the keyboard from these constraints.
          final visibleHeight = bodyConstraints.maxHeight;
          final scaledLine = MediaQuery.textScalerOf(context).scale(16) * 1.5;
          final minimumSheetHeight = scaledLine * 2 + 171;
          final commentsTop = (visibleHeight * 0.395).clamp(
            0.0, (visibleHeight - minimumSheetHeight).clamp(0.0, visibleHeight));
          final commentsVideoHeight = (commentsTop -
              MediaQuery.viewPaddingOf(context).top - 10).clamp(0.0, screenHeight * 0.355);
          final commentsHandleHeight = visibleHeight.clamp(0.0, 25.0);
          return Stack(
          children: [
            PreloadPageView.builder(
              controller: _pageController,
              preloadPagesCount: 1,
              scrollDirection: Axis.vertical,
              physics: _isNotificationMode || _isCommentsOpen
              ? const NeverScrollableScrollPhysics()
                  : const QuickerScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
              itemCount: _showCarousel
              ? (_stablePosts.isEmpty? 0 : _stablePosts.length + 1)
                  : _stablePosts.length,
              onPageChanged: (index) {
                if (_showCarousel && index == _carouselPos) {
                  if (widget.isFeedActive) TitiSingleEngine().pause();
                  return;
                }
                final realIndex = _showCarousel && index > _carouselPos? index - 1 : index;
                if (realIndex < 0 || realIndex >= _stablePosts.length) return;
                _handlePageChange(realIndex);
              },
              itemBuilder: (context, index) {
                if (_showCarousel && index == _carouselPos) {
                  return PeopleYouMayKnowCarousel(
                    onEmpty: () {
                      if (!mounted) return;
                      setState(() {
                        _showCarousel = false;
                        _carouselPos = -1;
                      });
                    },
                  );
                }
                final realIndex = _showCarousel && index > _carouselPos? index - 1 : index;
                if (realIndex < 0 || realIndex >= _stablePosts.length) {
                  return const SizedBox.shrink();
                }
                final postDoc = _stablePosts[realIndex];
                final dataCheck = postDoc.data() as Map<String, dynamic>;
                if (!_canViewPost(postDoc)) {
                  final audiencePending = _audience.isPostPending(
                    dataCheck,
                    postId: postDoc.id,
                  );
                  final ageRestricted = !audiencePending &&
                      _audience.isPostAgeRestricted(dataCheck, postId: postDoc.id);
                  if (realIndex == _currentIndex) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted || realIndex != _currentIndex || _canViewPost(postDoc)) return;
                      _stopRestrictedSelection(postDoc);
                    });
                  }
                  return Container(
                    color: Colors.black,
                    width: double.infinity,
                    height: double.infinity,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(22),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.lock_outline_rounded, color: Colors.white, size: 55),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              audiencePending ? "جارٍ التحقق من إتاحة الفيديو" : "المحتوى غير متاح",
                              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              audiencePending
                                  ? "لم يكتمل التحقق من صلاحية المشاهدة بعد."
                                  : ageRestricted
                                      ? "هذا الفيديو محظور على بعض الفئات العمرية\nيتطلب مشاهدته أن يكون عمرك 18 سنة أو أكثر"
                                      : "هذا الفيديو غير متاح حالياً.",
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.6),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () {
                                if (Navigator.canPop(context)) Navigator.pop(context);
                              },
                              child: const Text("رجوع", style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                final bool isFirstVideo = widget.isFromProfileGrid && realIndex == widget.initialIndex;

                return Stack(
                  children: [
                    // [Tini - Compact Comments Video] - نغيّر القياسات فقط، دون إنشاء مشغّل جديد.
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeInOut,
                      top: _isCommentsOpen ? MediaQuery.of(context).viewPadding.top + 2 : 0,
                      left: _isCommentsOpen ? screenWidth * 0.225 : 0,
                      width: _isCommentsOpen ? screenWidth * 0.55 : screenWidth,
                      height: _isCommentsOpen ? commentsVideoHeight : screenHeight,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(_isCommentsOpen ? 10 : 0),
                        child: TitiVideoPlayer(
                      playbackManagedExternally: _navigationOwnsPlayback,
                      isFeedActive: widget.isFeedActive,
                      key: ValueKey("video_${postDoc.id}_${_currentIndex}"),
                      postDoc: postDoc,
                      index: realIndex,
                      currentIndex: _currentIndex,
                      initialIndex: widget.initialIndex,
                      postProvider: postProvider,
                      screenWidth: _isCommentsOpen ? screenWidth * 0.55 : screenWidth,
                      screenHeight: _isCommentsOpen ? commentsVideoHeight + 45 : screenHeight,
                      topBarHeight: _isCommentsOpen || isHomeFeed ? 0 : topBarHeight,
                      bottomBarHeight: _isCommentsOpen ? 0 : effectiveBottomBarHeight,
                      thumbnailUrl: isFirstVideo? widget.thumbnailUrl : (postDoc.data() as Map<String, dynamic>)['thumbnailUrl'] as String?,
                      hideBars: true,
                      isFromProfileGrid: widget.isFromProfileGrid,
                      showSearchBar: widget.showSearchBar,
                      isSinglePost: isSingle && !isHomeFeed,
                      isFromTerminated: widget.isFromTerminated,
                      showComments: false,
                      isClearMode: false,
                      onTogglePlayButton: () {},
                      onToggleComments: () {},
                      onExitClearMode: () {},
                        ),
                      ),
                    ),

                    IgnorePointer(
                      ignoring: _isCommentsOpen,
                      child: Opacity(
                        opacity: _isCommentsOpen ? 0 : 1,
                        child: PostItemContent(
                      isFeedActive: widget.isFeedActive,
                      key: ValueKey("post_${postDoc.id}"),
                      postDoc: postDoc,
                      index: realIndex,
                      currentIndex: _currentIndex,
                      initialIndex: widget.initialIndex,
                      postProvider: postProvider,
                      auth: auth,
                      screenWidth: screenWidth,
                      screenHeight: screenHeight,
                      topBarHeight: topBarHeight,
                      bottomBarHeight: effectiveBottomBarHeight,
                      thumbnailUrl: isFirstVideo? widget.thumbnailUrl : (postDoc.data() as Map<String, dynamic>)['thumbnailUrl'] as String?,
                      hideBars: widget.hideBars,
                      isFromProfileGrid: widget.isFromProfileGrid,
                      showSearchBar: widget.showSearchBar,
                      isSinglePost: isSingle && !isHomeFeed,
                      onRemovePost: removePostInstantly,
                      onOpenComments: _showCommentsSheet,
                      onCommentsStateChanged: (isOpen) {
                        if (isOpen) {
                          _showCommentsSheet();
                        } else {
                          _closeCommentsSheet();
                        }
                      },
                        ),
                      ),
                    ),
                    // [Tini - Owner Reactions Overlay] - خارج بقية التبويبات، وبدون اعتراض لمس الفيديو.
                    if (widget.isFromProfileGrid &&
                        widget.showOwnerReactionsOverlay &&
                        auth.uid.isNotEmpty &&
                        dataCheck['uid'] == auth.uid)
                      Positioned.fill(
                        child: VideoReactionsOverlay(
                          key: ValueKey('owner_reactions_${postDoc.id}'),
                          postId: postDoc.id,
                          isActive: realIndex == _currentIndex &&
                              !_isCommentsOpen && !_isOverlayProfileOpen,
                          onProfileTap: _openOverlayProfile,
                          onCommentTap: _openOverlayComment,
                        ),
                      ),
                  ],
                );
              },
            ),
            // [Tini - Compact Comments Video] - التعليقات الأصلية بدون تغيير شكلها أو منطقها.
            if (_isCommentsOpen && _stablePosts.isNotEmpty) ...[
              Positioned(
                top: commentsTop,
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFF1A1A1E),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                  ),
                  child: Column(
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragEnd: (details) {
                          if ((details.primaryVelocity ?? 0) > 150) _closeCommentsSheet();
                        },
                        child: SizedBox(
                          height: commentsHandleHeight,
                          width: double.infinity,
                          child: Center(
                            child: Container(
                              width: 34,
                              height: 4,
                              decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: PostCommentsSheet(
                          key: ValueKey('compact_comments_${_stablePosts[_currentIndex].id}'),
                          postId: _stablePosts[_currentIndex].id,
                          postOwnerId: (_stablePosts[_currentIndex].data() as Map<String, dynamic>)['uid'] ?? '',
                          highlightCommentId: _highlightCommentInPanel,
                          highlightTemporarily: _highlightTemporarilyInPanel,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: commentsTop,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _closeCommentsSheet,
                      ),
                    ),
                    Positioned(
                      left: 12,
                      bottom: 12,
                      child: IconButton(
                        onPressed: _toggleCommentsMute,
                        icon: Icon(_commentsMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: Colors.white, size: 17),
                        style: IconButton.styleFrom(backgroundColor: Colors.black54, minimumSize: const Size(32, 32), padding: EdgeInsets.zero),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (widget.showSearchBar &&!_isCommentsOpen)
              Positioned(
                top: topBarHeight + 10,
                left: 60,
                right: 60,
                child: GestureDetector(
                  onTap: () {
                    TitiSingleEngine().player.pause();
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      children: [
                        const Icon(Icons.search, color: Colors.white70, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.searchQuery!= null && widget.searchQuery!.isNotEmpty
                            ? 'البحث عن "${widget.searchQuery}"'
                                : 'العثور على محتوى ذي صلة',
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.close, color: Colors.white54, size: 16),
                      ],
                    ),
                  ),
                ),
              ),
            if (!widget.hideBars)
              Positioned(
                top: MediaQuery.of(context).padding.top + 5,
                left: 10,
                child: SafeArea(
                  top: !widget.isFromProfileGrid,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                    onPressed: () {
                      if (widget.isBannerNavigation) {
                        Navigator.of(context).maybePop();
                        return;
                      }
                      if (widget.isFromProfileGrid) {
                        TitiProfileEngine().stop();
                      } else {
                        if (widget.posts.length == 1 || widget.isFromTerminated) {
                          TitiSingleEngine().player.pause();
                          TitiSingleEngine().unlockForHome();
                          // شغل الهوم بعد الرجوع بشوي
                          Future.delayed(const Duration(milliseconds: 150), () {
                            try {
                              TitiSingleEngine().forceResumeForTab();
                              TitiSingleEngine().play();
                            } catch (_) {}
                          });
                        } else {
                          TitiSingleEngine().stop();
                        }
                      }
                      if (Navigator.canPop(context)) {
                        Navigator.pop(context);
                      } else {
                        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const HomeScreen()), (r) => false);
                      }
                    },
                  ),
                ),
              ),
          ],
        );
        }),
      ),
    );
      },
    );
  }
  }

class QuickerScrollPhysics extends ScrollPhysics {
  const QuickerScrollPhysics({super.parent});

  @override
  QuickerScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return QuickerScrollPhysics(
      parent: buildParent(ancestor),
    );
  }

  @override
  double get minFlingVelocity => 10.0;
}

class PostItemContent extends StatefulWidget {
  final DocumentSnapshot postDoc;
  final int index;
  final int currentIndex;
  final int initialIndex;
  final PostProvider postProvider;
  final custom.AuthProvider auth;
  final double screenWidth;
  final double screenHeight;
  final double topBarHeight;
  final double bottomBarHeight;
  final String? thumbnailUrl;
  final bool hideBars;
  final Function(bool) onCommentsStateChanged;
  final VoidCallback onOpenComments;
  final bool isFromTerminated;
  final bool isFromProfileGrid;
  final bool showSearchBar;
  final bool isSinglePost;
  final Function(String) onRemovePost;
  final bool isFeedActive;

  const PostItemContent({
    super.key,
    required this.postDoc,
    required this.index,
    required this.currentIndex,
    required this.initialIndex,
    required this.postProvider,
    required this.auth,
    required this.screenWidth,
    required this.screenHeight,
    required this.topBarHeight,
    required this.bottomBarHeight,
    this.thumbnailUrl,
    required this.hideBars,
    required this.onCommentsStateChanged,
    required this.onOpenComments,
    this.isFromTerminated = false,
    this.isFromProfileGrid = false,
    this.showSearchBar = false,
    this.isSinglePost = false,
    required this.onRemovePost,
    this.isFeedActive = true,
  });

  @override
  State<PostItemContent> createState() => _PostItemContentState();
}

Widget _buildUserBadge(String? badgeType) {
  if (badgeType == null) return const SizedBox.shrink();
  IconData icon;
  Color color;
  switch (badgeType) {
    case 'bronze':
      icon = Icons.workspace_premium;
      color = const Color(0xFFCD7F32);
      break;
    case 'silver':
      icon = Icons.military_tech;
      color = const Color(0xFFE8E8E8);
      break;
    case 'gold':
      icon = Icons.emoji_events;
      color = const Color(0xFFFFD700);
      break;
    case 'diamond':
      icon = Icons.diamond;
      color = const Color(0xFF00D9FF);
      break;
    default:
      return const SizedBox.shrink();
  }
  return Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Icon(
      icon,
      size: 16,
      color: color,
    ),
  );
}

// [Tini - Follow Morph] - حركة زر المتابعة نحو صورة البروفايل دون تغيير أزرار الفيديو الأخرى.
class _TiniFollowMorphHeader extends StatefulWidget {
  final String ownerUid;
  final custom.AuthProvider auth;
  final Widget avatar;
  final Widget userName;

  const _TiniFollowMorphHeader({
    super.key,
    required this.ownerUid,
    required this.auth,
    required this.avatar,
    required this.userName,
  });

  @override
  State<_TiniFollowMorphHeader> createState() => _TiniFollowMorphHeaderState();
}

class _TiniFollowMorphHeaderState extends State<_TiniFollowMorphHeader>
    with TickerProviderStateMixin {
  static const double _pillWidth = 87;
  static const double _pillHeight = 27;
  static const _followColors = [
    Color(0xFF009688),
    Color(0xFFFF1744),
    Color(0xFFFFEB3B),
  ];

  final GlobalKey _avatarKey = GlobalKey();
  final GlobalKey _pillKey = GlobalKey();
  late final AnimationController _flightController;
  late final AnimationController _breathingController;
  OverlayEntry? _flightEntry;
  Rect? _flightStart;
  Offset? _flightDestination;
  bool _isFollowing = false;
  bool _isBusy = false;
  bool _isFlying = false;

  bool get _canFollow => widget.ownerUid.isNotEmpty &&
      widget.auth.uid.isNotEmpty && widget.auth.uid != widget.ownerUid;

  @override
  void initState() {
    super.initState();
    _isFollowing = widget.auth.isFollowingSync(widget.ownerUid);
    _flightController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    )..addListener(_rebuildFlight);
    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);
    widget.auth.addListener(_onFollowChanged);
    _verifyFollowing();
  }

  @override
  void didUpdateWidget(covariant _TiniFollowMorphHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.auth != widget.auth) {
      oldWidget.auth.removeListener(_onFollowChanged);
      widget.auth.addListener(_onFollowChanged);
    }
    if (oldWidget.ownerUid != widget.ownerUid || oldWidget.auth != widget.auth) {
      _stopFlight();
      _isBusy = false;
      _isFlying = false;
      _isFollowing = widget.auth.isFollowingSync(widget.ownerUid);
      _verifyFollowing();
    }
  }

  // تحديث شكل الزر أيضاً إذا تمت المتابعة أو أُلغيت من صفحة البروفايل.
  void _onFollowChanged() {
    if (!mounted || _isBusy || _isFlying || !_canFollow) return;
    final newValue = widget.auth.isFollowingSync(widget.ownerUid);
    if (newValue != _isFollowing) {
      setState(() => _isFollowing = newValue);
    }
  }

  Future<void> _verifyFollowing() async {
    if (!_canFollow) return;
    final ownerUid = widget.ownerUid;
    final myUid = widget.auth.uid;
    try {
      final document = await FirebaseFirestore.instance
          .collection('users').doc(myUid)
          .collection('following').doc(ownerUid).get();
      if (!mounted || _isBusy || _isFlying ||
          ownerUid != widget.ownerUid || myUid != widget.auth.uid) return;
      if (_isFollowing != document.exists) {
        setState(() => _isFollowing = document.exists);
      }
    } catch (_) {
      // عند عدم وجود اتصال نبقي حالة المتابعة المحفوظة في AuthProvider.
    }
  }

  void _rebuildFlight() => _flightEntry?.markNeedsBuild();

  void _stopFlight() {
    _flightEntry?.remove();
    _flightEntry?.dispose();
    _flightEntry = null;
    _flightStart = null;
    _flightDestination = null;
    _flightController.reset();
  }

  Widget _coloredPill({bool loading = false}) {
    return Container(
      width: _pillWidth,
      height: _pillHeight,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: _followColors,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 5)],
      ),
      child: Center(
        child: Opacity(
          opacity: loading ? 0.65 : 1,
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            textDirection: TextDirection.rtl,
            children: [
              Icon(Icons.add_rounded, size: 18, color: Colors.white),
              SizedBox(width: 2),
              Text(
                'متابعة',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 3)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFlight() {
    final start = _flightStart;
    final destination = _flightDestination;
    if (start == null || destination == null) return const SizedBox.shrink();
    final t = Curves.easeInOutCubic.transform(_flightController.value);
    final centre = Offset.lerp(start.center, destination, t)!;
    final width = lerpDouble(start.width, 18, t)!;
    final height = lerpDouble(start.height, 18, t)!;
    return Positioned(
      left: centre.dx - width / 2,
      top: centre.dy - height / 2,
      width: width,
      height: height,
      child: IgnorePointer(
        child: Opacity(
          opacity: (1 - t * 1.35).clamp(0.0, 1.0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: FittedBox(
              fit: BoxFit.fill,
              child: _coloredPill(),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _flyToProfile() async {
    final avatar = _avatarKey.currentContext?.findRenderObject();
    final pill = _pillKey.currentContext?.findRenderObject();
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final overlayBox = overlay?.context.findRenderObject();
    if (avatar is! RenderBox || pill is! RenderBox ||
        overlayBox is! RenderBox || !avatar.hasSize || !pill.hasSize) {
      setState(() { _isFollowing = true; _isBusy = false; });
      return;
    }

    _flightStart = pill.localToGlobal(Offset.zero, ancestor: overlayBox) & pill.size;
    _flightDestination = avatar.localToGlobal(
      avatar.size.center(Offset.zero), ancestor: overlayBox);
    _flightEntry = OverlayEntry(builder: (_) => _buildFlight());
    overlay!.insert(_flightEntry!);
    setState(() => _isFlying = true);
    await _flightController.forward(from: 0);
    if (!mounted) return;
    _stopFlight();
    setState(() {
      _isFollowing = true;
      _isFlying = false;
      _isBusy = false;
    });
  }

  Future<void> _follow() async {
    if (!_canFollow || _isBusy || _isFollowing) return;
    setState(() => _isBusy = true);
    try {
      // استعمال نظام المتابعة الأصلي: تحديث القوائم والعدادات والإشعارات.
      await widget.auth.toggleFollow(widget.ownerUid);
      final confirmed = await FirebaseFirestore.instance
          .collection('users').doc(widget.auth.uid)
          .collection('following').doc(widget.ownerUid).get();
      if (!mounted) return;
      if (!confirmed.exists) {
        setState(() => _isBusy = false);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('تعذّرت المتابعة، حاول مرة أخرى')),
        );
        return;
      }
      await _flyToProfile();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('تعذّرت المتابعة، تحقق من الاتصال')),
      );
    }
  }

  @override
  void dispose() {
    widget.auth.removeListener(_onFollowChanged);
    _stopFlight();
    _flightController.dispose();
    _breathingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showFollow = _canFollow && !_isFollowing && !_isFlying;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            KeyedSubtree(key: _avatarKey, child: widget.avatar),
            if (_canFollow)
              Positioned(
                right: -3,
                bottom: -3,
                child: IgnorePointer(
                  child: AnimatedScale(
                    scale: _isFollowing ? 1 : 0,
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutBack,
                    child: Container(
                      width: 19,
                      height: 19,
                      decoration: BoxDecoration(
                        color: const Color(0xFF009688),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF0F1720), width: 1.5),
                      ),
                      child: const Icon(Icons.check_rounded, size: 13, color: Colors.white),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 10),
        Flexible(child: widget.userName),
        if (_canFollow)
          AnimatedContainer(
            duration: const Duration(milliseconds: 540),
            curve: Curves.easeInOutCubic,
            width: showFollow ? _pillWidth + 7 : 0,
            height: _pillHeight,
            child: showFollow
                ? Padding(
                    padding: const EdgeInsets.only(left: 7),
                    child: GestureDetector(
                      key: _pillKey,
                      behavior: HitTestBehavior.opaque,
                      onTap: _follow,
                      child: AnimatedBuilder(
                        animation: _breathingController,
                        builder: (context, child) => Transform.scale(
                          scale: 0.95 + _breathingController.value * 0.10,
                          child: child,
                        ),
                        child: _coloredPill(loading: _isBusy),
                      ),
                    ),
                  )
                : null,
          ),
      ],
    );
  }
}

class _PostItemContentState extends State<PostItemContent>
    with SingleTickerProviderStateMixin {
  bool _showPlayButton = false;
  bool _showComments = false;
  bool _isClearMode = false;
  bool _isExpanded = false;
  late AnimationController _audioController;

  bool? _optimisticIsShared;
  bool? _optimisticIsFav;

  bool get _canInteract {
    final data = widget.postDoc.data() as Map<String, dynamic>?;
    return widget.isFeedActive && data != null && AudienceAccess.instance.canViewPost(data, postId: widget.postDoc.id);
  }

  @override
  void initState() {
    super.initState();
    _markBoxAsOpenedIfNeeded();
    _audioController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
  }

  @override
  void dispose() {
    _audioController.dispose();
    super.dispose();
  }

  void _markBoxAsOpenedIfNeeded() {
    if (!_canInteract || widget.index != widget.currentIndex) return;
    final postData = widget.postDoc.data() as Map<String, dynamic>;
    final bool isMysteryBox = postData['isMysteryBox']?? false;
    if (!isMysteryBox) return;
    final String? boxOwnedByUid = postData['boxOwnedByUid'];
    final String currentUid = widget.auth.uid;
    if (boxOwnedByUid!= currentUid) return;
    final dynamic boxOpenedAt = postData['boxOpenedAt'];
    if (boxOpenedAt!= null) return;
    debugPrint("📦 [Titi Box]: أول فتح للصندوق ${widget.postDoc.id}");
    widget.postProvider.markBoxAsOpened(widget.postDoc.id);
  }

  void _toggleComments(bool show) {
    setState(() {
      _showComments = show;
    });
    widget.onCommentsStateChanged(show);
  }

  // [Tini - Mention]: الضغط على @ يفتح الحساب، ولا يُنشئ إشعار ذكر خاطئاً.
  Future<void> _openMentionProfile(String text) async {
    final username = text.replaceFirst('@', '').toLowerCase().trim();
    if (username.isEmpty) return;
    try {
      final result = await FirebaseFirestore.instance.collection('public_profiles')
          .where('username_lowercase', isEqualTo: username)
          .limit(1).get();
      if (!mounted || result.docs.isEmpty) return;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ProfileScreen(userId: result.docs.first.id),
      ));
    } catch (_) { /* لا ننشئ إشعاراً عند فشل فتح الحساب. */ }
  }

  void _logActivity(
    String type,
    String text, {
    String? commentId,
    String? replyToCommentId,
  }) async {
    final currentUid = widget.auth.uid;
    final postData = widget.postDoc.data() as Map<String, dynamic>;
    final postOwnerId = postData['uid'];
    if (currentUid.isEmpty || currentUid == postOwnerId) return;
    final userName = widget.auth.fullName!= "مستخدم جديد"
       ? widget.auth.fullName
        : widget.auth.username;
    final docId = '${widget.postDoc.id}_${currentUid}_$type';
    await FirebaseFirestore.instance.collection('activities').doc(docId).set(
      {
        'toUid': postOwnerId,
        'fromUid': currentUid,
        'type': type,
        'text': '$userName $text',
        'postId': widget.postDoc.id,
        'commentId': commentId,
        'replyToCommentId': replyToCommentId,
        'timestamp': FieldValue.serverTimestamp(),
        'seen': false
      },
      SetOptions(merge: true),
    );
  }

void _confirmDelete(BuildContext context, String postId) {
    final rootNavigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A222C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        title: const Text(
          "نقل إلى المحذوفات؟",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        content: const Text(
          "سيتم نقل الفيديو إلى المحذوفات وسيبقى 30 يوماً يمكنك استعادته خلالها. بعد ذلك سيحذف نهائياً.",
          style: TextStyle(
            color: Colors.white70,
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              "تراجع",
              style: TextStyle(
                color: Colors.teal,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              Navigator.pop(dialogContext);
              await widget.postProvider.moveToTrash(postId);
              if (mounted) {
                rootNavigator.pop();
                messenger.showSnackBar(
                  const SnackBar(content: Text("تم نقل الفيديو إلى المحذوفات"), backgroundColor: Colors.teal),
                );
              }
            },
            child: const Text(
              "نقل للمحذوفات",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          )
        ],
      ),
    );
  }

void _showPostOptionsMenu(BuildContext context, Map<String, dynamic> postData) {
    final bool isOwner = widget.auth.uid == postData['uid'];
    const Color surfaceColor = Color(0xFF1A222C);
    const Color titiTeal = Colors.teal;

    bool isGoingToDuet = false;

    if (widget.isFromProfileGrid) {
      TitiProfileEngine().player.pause();
    } else {
      TitiSingleEngine().player.pause();
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 15),
              if (isOwner)...[
                _buildMenuOption(
                  Icons.delete_outline,
                  "حذف المنشور",
                  color: const Color(0xFFE53935),
                  onTap: () {
                    Navigator.pop(context);
                    _confirmDelete(context, widget.postDoc.id);
                  },
                ),
                _buildMenuOption(
                  Icons.edit_outlined,
                  "تعديل المنشور",
                  onTap: () {
                    Navigator.pop(context);
                  },
                )
              ],
              if (isOwner || (postData['allowDownload']?? true))
                _buildMenuOption(
                  Icons.download_for_offline_outlined,
                  "التنزيل",
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final postProvider = widget.postProvider;
                    Navigator.pop(context);
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text("جاري تنزيل الفيديو إلى المعرض..."),
                        backgroundColor: Colors.teal,
                        duration: Duration(seconds: 2),
                      ),
                    );
                    try {
                      await postProvider.downloadVideo(postData);
                      _logActivity('download', 'نزّل فيديوك');
                      if (!mounted) return;
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text("✅ تم حفظ الفيديو في الاستوديو بنجاح!"),
                          backgroundColor: Colors.green,
                        ),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text("🚨 فشل التنزيل، تأكد من الاتصال"),
                          backgroundColor: Color(0xFFE53935),
                        ),
                      );
                    }
                  },
                ),
              if (isOwner || (postData['allowDuet']?? true))
                _buildMenuOption(
                  Icons.duo_rounded,
                  "إنشاء ديو (Duet)",
                  onTap: () {
                    isGoingToDuet = true;
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CreatePostScreen(
                          duetVideoUrl: postData['videoUrl'],
                          isDuet: true,
                          originalAuthorName: postData['fullName'],
                          originalUsername: postData['username'],
                          originalOwnerId: postData['uid'],
                          selectedLayout: DuetLayout.sideBySide,
                        ),
                      ),
                    ).then((_) {
                      // [FIX] لما ترجع من الديو شغل تلقائيا مرة اخرى
                      if (!mounted || !_canInteract) return;
                      if (widget.isFromProfileGrid) {
                        TitiProfileEngine().play();
                      } else {
                        TitiSingleEngine().play();
                      }
                    });
                  },
                ),
              _buildMenuOption(
                Icons.visibility_off_outlined,
                "عدم اقتراح هذه القناة",
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final postId = widget.postDoc.id;
                  final ownerId = postData['uid'];
                  Navigator.pop(context);
                  final postProvider = Provider.of<PostProvider>(
                    context,
                    listen: false,
                  );
                  await postProvider.blockOwner(ownerId);
                  TitiSingleEngine().stop();
                  widget.onRemovePost(ownerId);
                  try {
                    final functions = FirebaseFunctions.instanceFor(
                      region: 'europe-west1',
                    );
                    final res = await functions.httpsCallable('logInteraction').call(
                      {
                        'postId': postId,
                        'type': 'notInterested',
                        'ownerId': ownerId
                      },
                    );
                    final reason = res.data['reason'];
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          reason == 'friend'
                             ? "هذا صديقك، أخفينا الفيديو فقط 😉"
                              : "تم حظر القناة، لن تظهر لك بعد الآن ✅",
                        ),
                        backgroundColor: Colors.teal,
                      ),
                    );
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text("فشل: $e"),
                      ),
                    );
                  }
                },
              ),
              _buildMenuOption(
                Icons.report_gmailerrorred_outlined,
                "إبلاغ",
                onTap: () {
                  Navigator.pop(context);
                },
              ),
              _buildMenuOption(
                Icons.fullscreen_exit_rounded,
                "وضع الشاشة الخالية",
                color: titiTeal,
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _isClearMode = true);
                },
              ),
              const SizedBox(height: 10)
            ],
          ),
        );
      },
    ).then((_) {
      if (!mounted) return;
      // Fix الصوت اللي بضل شغال: لا ترجع تشغل تلقائيا لما تسكر المنيو
      // اذا المستخدم طلع من الهوم، هاد كان يرجع يشغل الصوت غصب
      if (!isGoingToDuet) {
        // ما منشغل شي هون، المستخدم هو بيرجع بيكبس play اذا بدو
      }
    });
  }

  Widget _buildMenuOption(
    IconData icon,
    String title, {
    Color color = Colors.white,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: color,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: color,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    final postData = widget.postDoc.data() as Map<String, dynamic>;
    final String postId = widget.postDoc.id;
    final player = widget.isFromProfileGrid ? TitiProfileEngine().player : TitiSingleEngine().player;
    const Color titiDarkBG = Color(0xFF000000);
    const double audioBarHeight = 45;
    const double profileViewsBarHeight = 32;
    final double profileBottomInset = widget.isFromProfileGrid ? MediaQuery.of(context).padding.bottom : 0;
    // [Video Progress Alignment] - ربط التقدم بالحافة العليا لشريط الصوت في كل جهاز.
    final double audioBarBottom = widget.isFromProfileGrid ? profileBottomInset + profileViewsBarHeight : widget.bottomBarHeight == 0 ? 0 : widget.screenHeight * 0.075;
    final double progressBarBottom = audioBarBottom + audioBarHeight - kMinInteractiveDimension / 2;
    double videoHeight = widget.screenHeight;
    // [Tini Responsive Feed] - عدد الفيديوهات لا يغيّر مواضع أدوات التبويبات.
    // عند وجود فيديو واحد تبقى الصفحة جزءاً من الهوم، ولا تصبح شاشة منشور منفرد.
    final bool isHome = !widget.isFromProfileGrid && !widget.showSearchBar && !widget.isSinglePost;
    // [Home Views Counter] - مساحة مستقلة للعداد أسفل محتوى الصوت مع إبقاء شريط التقدم مكانه.
    final bool hasHomeBottomBar = isHome && widget.hideBars && widget.bottomBarHeight == 0;
    // [Tini Responsive Feed] - نسبة واحدة لكل التبويبات على الجهاز نفسه.
    // الاعتماد على ارتفاع الجهاز بدلاً من ارتفاع قائمة الفيديو المصغّر بسبب القصص.
    final double homeLayoutScale =
        (MediaQuery.sizeOf(context).height / 780.0).clamp(0.80, 1.0).toDouble();
    // مواضع الأزرار والبروفايل تُحسب من بداية شريط الصوت نفسها.
    final double sideActionsBottom = isHome
        ? audioBarBottom + audioBarHeight + 74.0 * homeLayoutScale
        : widget.bottomBarHeight + 60;
    final double authorInfoBottom = isHome
        ? audioBarBottom + audioBarHeight + 95.0 * homeLayoutScale
        : widget.bottomBarHeight + 75;
    final double sideActionsGap = 20.0 * homeLayoutScale;

    // حل 2: هذا الملف صار شفاف تماما بدون فيديو وبدون ثمبل
    return Container(
      color: Colors.transparent,
      height: videoHeight,
      width: widget.screenWidth,
      child: Stack(
        children: [
          // --- طبقة الضغط لاظهار واخفاء البلاي والسلايدر - المنطق الاصلي ---
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                setState(() {
                  _showPlayButton = !_showPlayButton;
                });
              },
            ),
          ),
          // 2. واجهة التعليقات
          if (_showComments)
            Positioned(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 0,
              right: 0,
              top: 100,
              child: Container(
                decoration: const BoxDecoration(
                  color: titiDarkBG,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black87,
                      blurRadius: 15,
                    )
                  ],
                ),
                child: Column(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragUpdate: (details) {
                        if (details.delta.dy > 8) {
                          _toggleComments(false);
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        height: 40,
                        color: Colors.transparent,
                        child: Center(
                          child: Container(
                            width: 45,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: PostCommentsSheet(
                        postId: postId,
                        postOwnerId: postData['uid']?? '',
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 3. الأزرار الجانبية والمعلومات - شفاف فوق طبقة الفيديو الثابتة
          if (!_showComments &&!_isClearMode)
            Stack(
              children: [
                // [Profile Bottom Layout] - سطح متصل أسفل الفيديو يحترم مساحة النظام دون تغيير الهوم.
                if (widget.isFromProfileGrid)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: profileBottomInset + profileViewsBarHeight + audioBarHeight,
                    child: const ColoredBox(color: Colors.black),
                  ),
                if (!widget.hideBars)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: widget.topBarHeight,
                      color: Colors.black,
                    ),
                  ),
                Positioned(
                  bottom: audioBarBottom,
                  left: 0,
                  right: 0,
                  child: Container(
                    color: Colors.black,
                    height: 45,
                    padding: EdgeInsets.fromLTRB(16, 0, 16, hasHomeBottomBar ? 20 : 0),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.music_note,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "${postData['songTitle']?? 'صوت أصلي'} - ${postData['username']?? 'مستخدم'}",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        RotationTransition(
                          turns: _audioController,
                          child: Container(
                            width: 25,
                            height: 25,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                            child: ClipOval(
                              child: CachedNetworkImage(
                                imageUrl: (postData['songSource'] == 'itunes' &&
                                        postData['songCover']!= null)
                                   ? postData['songCover']
                                    : (postData['profileImg']?? ''),
                                fit: BoxFit.cover,
                                errorWidget: (context, url, error) => const Icon(
                                  Icons.music_note,
                                  size: 15,
                                ),
                              ),
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                ),
                
                  Positioned(
                    bottom: widget.isFromProfileGrid ? profileBottomInset : (hasHomeBottomBar ? 0 : 30),
                    left: 0,
                    right: 0,
                    child: Container(
                      height: hasHomeBottomBar ? 20 : 32, 
                      color: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          const Spacer(),
                          Row(
                            children: [
                              const Icon(
                                Icons.remove_red_eye_outlined,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                (postData['views']?? 0).toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            ],
                          )
                        ],
                      ),
                    ),
                  ),
                if (_showPlayButton)
                  Center(
                    child: IconButton(
                      iconSize: 80,
                      icon: Icon(
                        player.state.playing
                           ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
onPressed: () async {
  if (!_canInteract) return;
  final isPlaying = widget.isFromProfileGrid 
      ? TitiProfileEngine().player.state.playing 
      : player.state.playing;
  
  if (isPlaying) {
    if (widget.isFromProfileGrid) {
      await TitiProfileEngine().pause();
    } else {
      await player.pause();
    }
  } else {
    if (widget.isFromProfileGrid) {
      await TitiProfileEngine().play();
    } else {
      await TitiSingleEngine().play();
    }
  }
  if (mounted) setState(() {});
},
                    ),
                  ),
                if (_showPlayButton)
                  Positioned(
                    bottom: progressBarBottom,
                    left: 0,
                    right: 0,
                    height: kMinInteractiveDimension,
                    child: StreamBuilder<Duration>(
                      stream: player.stream.position,
                      builder: (context, snap) {
                        final pos = snap.data?? Duration.zero;
                        final dur = player.state.duration;
                        return Row(
                          children: [
                            const SizedBox(width: 12),
                            Text(
                              _formatDuration(pos),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  Shadow(
                                    blurRadius: 5,
                                    color: Colors.black,
                                  )
                                ],
                              ),
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 1.8,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 4.0,
                                  ),
                                  activeTrackColor: const Color(0xFFE53935),
                                  inactiveTrackColor: Colors.white12,
                                  thumbColor: Colors.white,
                                  overlayShape: SliderComponentShape.noOverlay,
                                ),
                                child: Slider(
                                  value: pos.inMilliseconds.toDouble().clamp(
                                        0.0,
                                        dur.inMilliseconds.toDouble() + 1.0,
                                      ),
                                  max: dur.inMilliseconds.toDouble() + 1.0,
                                  onChanged: (v) => player.seek(
                                    Duration(milliseconds: v.toInt()),
                                  ),
                                ),
                              ),
                            ),
                            Text(
                              _formatDuration(dur),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                shadows: [
                                  Shadow(
                                    blurRadius: 5,
                                    color: Colors.black,
                                  )
                                ],
                              ),
                            ),
                            const SizedBox(width: 12)
                          ],
                        );
                      },
                    ),
                  ),
                Positioned(
                  right: 15,
                  bottom: sideActionsBottom,
                  child: StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance.collection('posts').doc(postId).snapshots(),
                    builder: (context, postSnap) {
                      final liveData = (postSnap.data?.data() as Map<String, dynamic>?)?? postData;
                      final int realLikes = liveData['likesCount']?? 0;
                      final int commentCount = liveData['comments']?? 0;
                      final int sharesCount = liveData['shares']?? 0;
                      final int favCount = liveData['favoritesCount']?? 0;
                      final String commentPrivacy = liveData['commentPrivacy'] ?? 'comment_everyone';
                      bool allowComments = true;
                      if (commentPrivacy == 'comment_nobody') {
                        allowComments = false;
                      } else if (commentPrivacy == 'comment_friends') {
                        final String currentUid = widget.auth.uid;
                        final String ownerUid = postData['uid'] ?? '';
                        final bool isOwner = currentUid == ownerUid;
                        final bool isFollowing = widget.auth.isFollowingSync(ownerUid) || widget.auth.followingList.contains(ownerUid);
                        allowComments = isOwner || isFollowing;
                      } else {
                        allowComments = true; // comment_everyone
                      }

                      return StreamBuilder<bool>(
                        stream: widget.postProvider.isFavoriteStream(postId),
                        builder: (context, favSnap) {
                          return StreamBuilder<bool>(
                            stream: widget.postProvider.isSharedStream(postId),
                            builder: (context, sharedSnap) {
                              final bool liveIsFav = favSnap.data?? false;
                              final bool liveIsShared = sharedSnap.data?? false;

                              final bool isFav = _optimisticIsFav?? liveIsFav;
                              final bool isShared = _optimisticIsShared?? liveIsShared;

                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (widget.auth.uid.isNotEmpty)
                                    PostLikeButton(
                                      key: ValueKey("like_live_$postId"),
                                      postId: postId,
                                      likesCount: realLikes,
                                      currentUserId: widget.auth.uid,
                                      postOwnerId: postData['uid']?? '',
                                    )
                                  else
                                    Column(
                                      children: [
                                        Icon(Icons.favorite_border, size: 38, color: Colors.white),
                                        SizedBox(height: 4),
                                        Text('$realLikes', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  SizedBox(height: sideActionsGap),
                                  GestureDetector(
                                    onTap: () {
                                      if (allowComments == false) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text("التعليقات مغلقة لهذا المنشور"),
                                            backgroundColor: Colors.teal,
                                          ),
                                        );
                                        _logActivity('comment_disabled', 'حاول التعليق ومنشورك مغلق');
                                      } else {
                                        widget.onOpenComments();
                                      }
                                    },
                                    child: _buildSideAction(
                                      allowComments == false? Icons.speaker_notes_off_outlined : Icons.chat_bubble_outline,
                                      commentCount.toString(),
                                    ),
                                  ),
                                  SizedBox(height: sideActionsGap),
                                  Column(
                                    children: [
                                      IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        icon: Icon(Icons.reply_all_rounded, size: 35, color: isShared? Colors.teal : Colors.white),
                                        onPressed: () async {
                                          setState(() => _optimisticIsShared =!isShared);
                                          await widget.postProvider.sharePost(postId);
                                          _logActivity('share', 'شارك منشورك');
                                        },
                                      ),
                                      const SizedBox(height: 4),
                                      Text(sharesCount.toString(), style: TextStyle(color: isShared? Colors.teal : Colors.white, fontSize: 12))
                                    ],
                                  ),
                                  SizedBox(height: sideActionsGap),
                                  GestureDetector(
                                    onTap: () {
                                      setState(() => _optimisticIsFav =!isFav);
                                      widget.postProvider.toggleFavorite(postId);
                                      _logActivity('favorite', 'حفظ منشورك');
                                    },
                                    child: _buildSideAction(
                                      isFav? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                                      favCount.toString(),
                                      color: isFav? const Color(0xFFFFEB3B) : Colors.white,
                                    ),
                                  ),
                                  SizedBox(height: sideActionsGap),
                                  if (!_isClearMode &&!_showComments)
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => _showPostOptionsMenu(context, postData),
                                      child: Container(
                                        color: Colors.transparent,
                                        padding: const EdgeInsets.all(12),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF009688), shape: BoxShape.circle)),
                                            const SizedBox(width: 4),
                                            Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFFFF1744), shape: BoxShape.circle)),
                                            const SizedBox(width: 4),
                                            Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFFFFEB3B), shape: BoxShape.circle)),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
                Positioned(
                  left: 15,
                  bottom: authorInfoBottom,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: widget.screenWidth * 0.78),
                        child: _TiniFollowMorphHeader(
                          key: ValueKey('follow_${postData['uid']}'),
                          ownerUid: (postData['uid'] ?? '').toString(),
                          auth: widget.auth,
                          avatar: GestureDetector(
  onTap: () async {
    try {
      await TitiSingleEngine().lock();
      await TitiProfileEngine().lock();
    } catch (_) {}
    final auth = Provider.of<custom.AuthProvider>(context, listen: false);
    final following = auth.isFollowingSync(postData['uid']);
    final wentToProfile = await UserProfileSheet.show(
      context,
      fullName: postData['fullName'] ?? 'User',
      username: postData['username'] ?? 'user',
      profileImg: postData['profileImg'] ?? '',
      uid: postData['uid'] ?? '',
      isFollowing: following,
      onFollowTap: () {
        auth.toggleFollow(postData['uid']);
        _logActivity('follow', 'تابعك');
      },
    );
    if (!mounted) return;
    if (wentToProfile == true) return; // راح عالبروفايل الموسع لا تشغل شي
    await TitiSingleEngine().unlockForHome();
  },
                            child: StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance
                                 .collection('stories')
                                 .doc(postData['uid'])
                                 .collection('items')
                                 .where(
                                    'expiresAt',
                                    isGreaterThan: Timestamp.now(),
                                  )
                                 .limit(10)
                                 .snapshots(),
                              builder: (context, snap) {
                                final docs = snap.data?.docs?? [];
                                final currentUid = widget.auth.uid;
                                final hasStories = docs.isNotEmpty;
                                final hasUnviewed = docs.any((d) {
                                  final viewedBy =
                                      List<String>.from(d['viewedBy']?? []);
                                  return!viewedBy.contains(currentUid);
                                });
                                final String img = postData['profileImg']?? '';
                                final String name = postData['fullName']?? 'User';
                                final bool hasImage = img.isNotEmpty;
                                final String initial = name.isNotEmpty
                                   ? name[0].toUpperCase()
                                    : '?';
                                if (hasStories) {
                                  return StoryRing(
                                    imageUrl: img,
                                    size: 44,
                                    hasStories: true,
                                    hasUnviewed: hasUnviewed,
                                    heroTag: 'post-${widget.postDoc.id}',
                                  );
                                } else if (hasImage) {
                                  return CircleAvatar(
                                    radius: 22,
                                    backgroundImage:
                                        CachedNetworkImageProvider(img),
                                  );
                                } else {
                                  return CircleAvatar(
                                    radius: 22,
                                    backgroundColor: const Color(0xFF1A222C),
                                    child: Text(
                                      initial,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                          userName: FutureBuilder<Map<String, dynamic>>(
                            future: widget.postProvider
                               .getUserBadge(postData['uid']),
                            builder: (context, snapshot) {
                              final badge = snapshot.data?['badge'];
                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                    "${postData['fullName']?? 'User'}",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      shadows: [
                                        Shadow(
                                          blurRadius: 10,
                                          color: Colors.black,
                                        )
                                      ],
                                    ),
                                  ),
                                  ),
                                  _buildUserBadge(badge)
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                      if (postData['isDuet'] == true &&
                          postData['originalAuthorName']!= null &&
                          postData['originalAuthorName']!= "")
                        Padding(
                          padding: const EdgeInsets.only(
                            top: 6,
                            bottom: 2,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.repeat,
                                color: Colors.white70,
                                size: 14,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                postData['fullName'] ==
                                        postData['originalAuthorName']
                                   ? "عمل ديو مع نفسه"
                                    : "ديو مع ${postData['originalAuthorName']}",
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  shadows: [
                                    Shadow(
                                      blurRadius: 5,
                                      color: Colors.black,
                                    )
                                  ],
                                ),
                              )
                            ],
                          ),
                        ),
                      const SizedBox(height: 10),
                      StatefulBuilder(
                        builder: (context, setInnerState) {
                          final String fullDesc = postData['description']?? '';
                          bool isLong = fullDesc.length > 60;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (postData['location']!= null &&
                                  postData['location'].toString().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.location_on,
                                        color: Colors.white70,
                                        size: 14,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        postData['location'],
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          shadows: [
                                            Shadow(
                                              blurRadius: 5,
                                              color: Colors.black,
                                            )
                                          ],
                                        ),
                                      )
                                    ],
                                  ),
                                ),
                              // [ADDITION] شارة الخصوصية - تظهر فقط إذا المنشور أصدقاء أو أنا فقط
                              if (postData['privacy'] == 'friends' || postData['privacy'] == 'only_me' || postData['privacy'] == 'private')
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.45),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.white24, width: 0.5),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          postData['privacy'] == 'friends' ? Icons.group : Icons.lock,
                                          color: Colors.white70,
                                          size: 12,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          postData['privacy'] == 'friends' ? "الأصدقاء فقط" : "أنا فقط",
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              SizedBox(
                                width: widget.screenWidth * 0.7,
                                child: GestureDetector(
                                  onTap: () {
                                    if (isLong) {
                                      setInnerState(() {
                                        _isExpanded =!_isExpanded;
                                      });
                                    }
                                  },
                                  child: DetectableText(
                                    text: _isExpanded
                                       ? fullDesc
                                        : (isLong
                                           ? "${fullDesc.substring(0, 60)}..."
                                            : fullDesc),
                                    detectionRegExp: RegExp(r'(#\w+|@\w+)', multiLine: true),
                                    maxLines: _isExpanded? null : 2,
                                    overflow: _isExpanded
                                       ? TextOverflow.visible
                                        : TextOverflow.ellipsis,
                                    detectedStyle: const TextStyle(
                                      color: Colors.teal,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                    basicStyle: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      shadows: [
                                        Shadow(
                                          blurRadius: 5,
                                          color: Colors.black,
                                        )
                                      ],
                                    ),
                                    onTap: (tappedText) {
                                      if (tappedText.startsWith('#')) {
                                        HashtagService().handleHashtagTap(
                                          context,
                                          tappedText,
                                        );
                                      } else if (tappedText.startsWith('@')) {
                                        _openMentionProfile(tappedText);
                                      }
                                    },
                                  ),
                                ),
                              ),
                              if (isLong)
                                GestureDetector(
                                  onTap: () {
                                    setInnerState(() {
                                      _isExpanded =!_isExpanded;
                                    });
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      _isExpanded? "عرض أقل" : "المزيد...",
                                      style: const TextStyle(
                                        color: Colors.teal,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                )
                            ],
                          );
                        },
                      ),
                      if (postData['mentions']!= null &&
                          (postData['mentions'] as List).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                            (postData['mentions'] as List)
                               .map((u) => "@$u")
                               .join(" "),
                            style: const TextStyle(
                              color: Colors.teal,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              shadows: [
                                Shadow(
                                  blurRadius: 5,
                                  color: Colors.black,
                                )
                              ],
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
    );
  }

  Widget _buildSideAction(
    IconData icon,
    String label, {
    Color color = Colors.white,
  }) {
    return Column(
      children: [
        Icon(
          icon,
          color: color,
          size: 28,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        )
      ],
    );
  }
}