import 'dart:ui';
import 'audience_access.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'post_provider.dart';
import 'titi_single_engine.dart';
import 'titi_profile_engine.dart';

class TitiVideoPlayer extends StatefulWidget {
  final dynamic postDoc;
  final int index;
  final int currentIndex;
  final PostProvider postProvider;
  final double screenWidth;
  final double screenHeight;
  final double topBarHeight;
  final double bottomBarHeight;
  final String? thumbnailUrl;
  final bool hideBars;
  final int initialIndex;
  final bool isFromProfileGrid;
  final bool showSearchBar;
  final bool isSinglePost;
  final bool isFromTerminated;
  final bool showComments;
  final bool isClearMode;
  final VoidCallback onTogglePlayButton;
  final VoidCallback onToggleComments;
  final VoidCallback onExitClearMode;
  final bool isFeedActive;
  final bool playbackManagedExternally;

  const TitiVideoPlayer({
    super.key,
    required this.postDoc,
    required this.index,
    required this.currentIndex,
    required this.postProvider,
    required this.screenWidth,
    required this.screenHeight,
    required this.topBarHeight,
    required this.bottomBarHeight,
    this.thumbnailUrl,
    required this.hideBars,
    required this.initialIndex,
    required this.isFromProfileGrid,
    required this.showSearchBar,
    required this.isSinglePost,
    required this.isFromTerminated,
    required this.showComments,
    required this.isClearMode,
    required this.onTogglePlayButton,
    required this.onToggleComments,
    required this.onExitClearMode,
    this.isFeedActive = true,
    this.playbackManagedExternally = false,
  });

  @override
  State<TitiVideoPlayer> createState() => _TitiVideoPlayerState();
}

class _TitiVideoPlayerState extends State<TitiVideoPlayer> {
  bool _ready = true;
  final _audience = AudienceAccess.instance;
  bool _wasAllowed = false;
  bool _dependenciesReady = false;
  bool _wasRouteVisible = false;
  bool get _routeVisible => _dependenciesReady && (ModalRoute.of(context)?.isCurrent ?? true);

  bool get _isAllowed {
    final data = widget.postDoc.data() as Map<String, dynamic>?;
    return data != null && _audience.canViewPost(data, postId: widget.postDoc.id);
  }

  void _onAudienceChanged() {
    if (!mounted) return;
    final allowed = _isAllowed;
    if (_routeVisible && widget.isFeedActive && widget.index == widget.currentIndex && allowed != _wasAllowed) {
      if (!allowed) {
        final data = widget.postDoc.data() as Map<String, dynamic>? ?? {};
        final currentUrl = widget.isFromProfileGrid
            ? TitiProfileEngine().currentUrl : TitiSingleEngine().currentUrl;
        if ([data['hlsPath'], data['videoUrl'], data['hlsUrl']].contains(currentUrl)) {
          if (widget.isFromProfileGrid) {
            TitiProfileEngine().pause();
          } else {
            TitiSingleEngine().pause();
          }
        }
      } else if (widget.isFromProfileGrid) {
        _playProfileWithNeighbors();
      } else {
        _playHomeWithNeighbors();
      }
    }
    if (allowed != _wasAllowed) {
      _wasAllowed = allowed;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _audience.removeListener(_onAudienceChanged);
    super.dispose();
  }

  String _getVideoUrl(dynamic doc) {
    try {
      final data = doc.data() as Map<String, dynamic>;
      if (!_audience.canViewPost(data, postId: doc.id)) return "";
      final String hls = (data['hlsPath'] as String?)?.trim()?? "";
      if (hls.isNotEmpty) return hls;
      return (data['videoUrl'] as String?)?? "";
    } catch (_) {
      return "";
    }
  }

  void _playProfileWithNeighbors() {
    if (!widget.isFeedActive || !_routeVisible) return;
    final String vUrl = _getVideoUrl(widget.postDoc);
    if (vUrl.isEmpty) return;
    try {
      final List posts = (widget.postProvider as dynamic).profilePosts?? [];
      String? prev, prevPrev, next, nextNext, nextNextNext;
      int idx = widget.index;
      if (posts.isNotEmpty) {
        if (idx - 1 >= 0) prev = _getVideoUrl(posts[idx - 1]);
        if (idx - 2 >= 0) prevPrev = _getVideoUrl(posts[idx - 2]);
        if (idx + 1 < posts.length) next = _getVideoUrl(posts[idx + 1]);
        if (idx + 2 < posts.length) nextNext = _getVideoUrl(posts[idx + 2]);
        if (idx + 3 < posts.length) nextNextNext = _getVideoUrl(posts[idx + 3]);
      }
      TitiProfileEngine().playSingleUrl(vUrl, prevUrl: prev, prevPrevUrl: prevPrev, nextUrl: next, nextNextUrl: nextNext, nextNextNextUrl: nextNextNext);
    } catch (_) {
      TitiProfileEngine().playSingleUrl(vUrl);
    }
  }

void _playHomeWithNeighbors() {
    if (!widget.isFeedActive || !_routeVisible) return;
    final String vUrl = _getVideoUrl(widget.postDoc);
    if (vUrl.isEmpty) return;
    try {
      final Map<String, dynamic> data = widget.postDoc.data() as Map<String, dynamic>;
      final String postId = (data['postId'] ?? data['id'] ?? '').toString();
      final List<String> hashtags = List<String>.from(data['hashtags'] ?? data['tags'] ?? []);

      final List posts = (widget.postProvider as dynamic).posts?? [];
      String? prev, prevPrev, next, nextNext, nextNextNext;
      int idx = widget.index;
      if (posts.isNotEmpty) {
        if (idx - 1 >= 0) prev = _getVideoUrl(posts[idx - 1]);
        if (idx - 2 >= 0) prevPrev = _getVideoUrl(posts[idx - 2]);
        if (idx + 1 < posts.length) next = _getVideoUrl(posts[idx + 1]);
        if (idx + 2 < posts.length) nextNext = _getVideoUrl(posts[idx + 2]);
        if (idx + 3 < posts.length) nextNextNext = _getVideoUrl(posts[idx + 3]);
      }
      TitiSingleEngine().playUrl(vUrl, prevUrl: prev, prevPrevUrl: prevPrev, nextUrl: next, nextNextUrl: nextNext, nextNextNextUrl: nextNextNext, postId: postId, hashtags: hashtags);
    } catch (_) {
      try {
        final Map<String, dynamic> data = widget.postDoc.data() as Map<String, dynamic>;
        final String postId = (data['postId'] ?? data['id'] ?? '').toString();
        final List<String> hashtags = List<String>.from(data['hashtags'] ?? data['tags'] ?? []);
        TitiSingleEngine().playUrl(vUrl, postId: postId, hashtags: hashtags);
      } catch (_) {
        TitiSingleEngine().playUrl(vUrl);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _ready = true;
    _audience.addListener(_onAudienceChanged);
    _wasAllowed = _isAllowed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final first = !_dependenciesReady;
    _dependenciesReady = true;
    final visible = _routeVisible;
    if (!widget.playbackManagedExternally && visible && (first || !_wasRouteVisible) && widget.isFeedActive && widget.index == widget.currentIndex) {
      if (widget.isFromProfileGrid) {
        if (!TitiProfileEngine().isUserPaused) _playProfileWithNeighbors();
      } else {
        if (!TitiSingleEngine().isUserPaused) _playHomeWithNeighbors();
      }
    }
    _wasRouteVisible = visible;
  }

  @override
  void didUpdateWidget(TitiVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Fix ذهاب واياب بين التبويبات: الشرط القديم كان يعمل فقط عند السحب داخل نفس التبويب
    // لأن currentIndex يبقى 0 عند الرجوع من تبويب لتبويب
    final bool isMeVisible = widget.isFeedActive && widget.index == widget.currentIndex;
    final bool becameActive = widget.isFeedActive && !oldWidget.isFeedActive;
    final bool wasNotMeBefore = oldWidget.currentIndex!= widget.currentIndex;
    // A new Firestore snapshot is not a new video: view/follow/like counter
    // updates must not seek or recreate the same active media player.
    Map<String, dynamic> postFields(dynamic doc) {
      try {
        return (doc.data() as Map<String, dynamic>?) ?? {};
      } catch (_) {
        return {};
      }
    }
    final previousPost = postFields(oldWidget.postDoc);
    final currentPost = postFields(widget.postDoc);
    final bool postChanged = oldWidget.postDoc.id != widget.postDoc.id ||
        previousPost['videoUrl'] != currentPost['videoUrl'] ||
        previousPost['hlsPath'] != currentPost['hlsPath'] ||
        previousPost['hlsUrl'] != currentPost['hlsUrl'];
    final bool indexChanged = oldWidget.index != widget.index ||
        oldWidget.isFromProfileGrid != widget.isFromProfileGrid;

    if (!widget.playbackManagedExternally && isMeVisible && (becameActive || wasNotMeBefore || postChanged || indexChanged)) {
      if (widget.isFromProfileGrid) {
        if (TitiProfileEngine().isUserPaused) return;
        _playProfileWithNeighbors();
      } else {
        if (TitiSingleEngine().isUserPaused) return;
        _playHomeWithNeighbors();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final postData = widget.postDoc.data() as Map<String, dynamic>;
    if (!_isAllowed) return const ColoredBox(color: Colors.black);
    const Color titiDarkBG = Color(0xFF000000);

    const double audioBarHeight = 45;
    double topFix = -1;
    double bottomFix = -4;
    // [Profile Bottom Layout] - ينتهي الفيديو مباشرة عند بداية شريط الصوت على كل شاشة.
    const double profileViewsBarHeight = 32;
    final double profileBottomInset = widget.isFromProfileGrid ? MediaQuery.of(context).padding.bottom : 0;
    double videoHeight = widget.showComments
      ? widget.screenHeight * 0.40
        : widget.isFromProfileGrid && widget.bottomBarHeight > 0
          ? widget.screenHeight - audioBarHeight - profileViewsBarHeight - profileBottomInset
        : (widget.isFromProfileGrid || widget.showSearchBar ||
                widget.isSinglePost)
          ? widget.screenHeight -
                widget.topBarHeight -
                widget.bottomBarHeight -
                audioBarHeight -
                bottomFix
            : widget.screenHeight -
                widget.topBarHeight -
                widget.bottomBarHeight -
                audioBarHeight +
                3.2;

    final BoxFit videoFit = BoxFit.contain;
    final String thumbUrl = postData['thumbnailUrl']?? widget.thumbnailUrl?? '';

    return Transform.translate(
      offset: Offset(
          0,
          (widget.isFromProfileGrid ||
                  widget.showSearchBar ||
                  widget.isSinglePost)
            ? (widget.isFromProfileGrid && widget.bottomBarHeight > 0 ? 0 : widget.topBarHeight + topFix)
              : 0),
      child: SizedBox(
        height: videoHeight,
        width: widget.screenWidth,
        child: Container(
          color: titiDarkBG,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_ready)
                Positioned.fill(
                  child: Builder(
                    builder: (context) {
                      final String myUrl = _getVideoUrl(widget.postDoc);
                      if (widget.isFromProfileGrid) {
                        return ValueListenableBuilder<List<String>>(
                          valueListenable: TitiProfileEngine().playerUrlsNotifier,
                          builder: (context, playerUrls, __) {
                            final int myIdx = playerUrls.indexOf(myUrl);
                            return ValueListenableBuilder<List<bool>>(
                              valueListenable: TitiProfileEngine().firstFrameReadyNotifier,
                              builder: (context, firstFrameReady, ___) {
                                final bool hasPlayer = myIdx!= -1 && myIdx < firstFrameReady.length;
                                final bool ready = hasPlayer && firstFrameReady[myIdx];
                                return Stack(
                                  children: [
                                    Positioned.fill(
                                      child: thumbUrl.isNotEmpty
                                        ? CachedNetworkImage(imageUrl: thumbUrl, fit: videoFit, width: widget.screenWidth, height: videoHeight, fadeInDuration: Duration.zero)
                                          : Container(color: titiDarkBG),
                                    ),
                                    if (hasPlayer)
                                      Positioned.fill(
                                        child: AnimatedOpacity(
                                          opacity: ready? 1 : 0,
                                          duration: Duration.zero,
                                          child: Video(controller: TitiProfileEngine().getControllerByIndex(myIdx), fit: videoFit, fill: Colors.transparent, controls: (s) => const SizedBox.shrink()),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            );
                          },
                        );
                      } else {
                        return ValueListenableBuilder<List<String>>(
                          valueListenable: TitiSingleEngine().playerUrlsNotifier,
                          builder: (context, playerUrls, __) {
                            final int myIdx = playerUrls.indexOf(myUrl);
                            return ValueListenableBuilder<List<bool>>(
                              valueListenable: TitiSingleEngine().firstFrameReadyNotifier,
                              builder: (context, firstFrameReady, ___) {
                                final bool hasPlayer = myIdx!= -1 && myIdx < firstFrameReady.length;
                                final bool ready = hasPlayer && firstFrameReady[myIdx];
                                return Stack(
                                  children: [
                                    Positioned.fill(
                                      child: thumbUrl.isNotEmpty
                                        ? CachedNetworkImage(imageUrl: thumbUrl, fit: videoFit, width: widget.screenWidth, height: videoHeight, fadeInDuration: Duration.zero)
                                          : Container(color: titiDarkBG),
                                    ),
                                    if (hasPlayer)
                                      Positioned.fill(
                                        child: AnimatedOpacity(
                                          opacity: ready? 1 : 0,
                                          duration: Duration.zero,
                                          child: Video(controller: TitiSingleEngine().getControllerByIndex(myIdx), fit: videoFit, fill: Colors.transparent, controls: (s) => const SizedBox.shrink()),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            );
                          },
                        );
                      }
                    },
                  ),
                ),
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  if (widget.isClearMode) {
                    widget.onExitClearMode();
                    return;
                  }
                  if (widget.showComments) {
                    widget.onToggleComments();
                  } else {
                    widget.onTogglePlayButton();
                  }
                },
                child: Container(color: Colors.transparent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}