import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'audience_access.dart';
import 'titi_single_engine.dart';
import 'titi_profile_engine.dart';
import 'video_playback_handoff.dart';

abstract class BannerVideoPlaybackDriver implements VideoPlaybackPort {
  VideoPlaybackQueue get operations;
  VideoPlaybackBookmarks captureBookmarks();
  Future<void> restoreBookmarks(
    VideoPlaybackBookmarks bookmarks, {
    required bool sameViewer,
  });
  String? get viewer;
  bool canPlay(String url);
  VideoPlaybackSnapshot? capture(VideoPlaybackOrigin origin);
  Future<void> silenceHome();
}

class _EnginePlaybackPort implements BannerVideoPlaybackDriver {
  static final _operations = VideoPlaybackQueue();
  @override
  VideoPlaybackQueue get operations => _operations;
  @override
  VideoPlaybackBookmarks captureBookmarks() => VideoPlaybackBookmarks(
    homeUrl: TitiSingleEngine().isInitialized
        ? TitiSingleEngine().currentUrl
        : null,
    profileUrl: TitiProfileEngine().isInitialized
        ? TitiProfileEngine().currentUrl
        : null,
  );
  @override
  Future<void> restoreBookmarks(
    VideoPlaybackBookmarks bookmarks, {
    required bool sameViewer,
  }) async {
    if (TitiSingleEngine().isInitialized) {
      TitiSingleEngine().restoreNavigationBookmark(
        sameViewer ? bookmarks.homeUrl ?? '' : '',
      );
    }
    if (TitiProfileEngine().isInitialized) {
      TitiProfileEngine().restoreNavigationBookmark(
        sameViewer ? bookmarks.profileUrl ?? '' : '',
      );
    }
  }

  @override
  String? get viewer => FirebaseAuth.instance.currentUser?.uid;
  @override
  bool canPlay(String url) => AudienceAccess.instance.canPlayUrl(url);
  @override
  Future<void> silenceHome() async {
    final single = TitiSingleEngine();
    if (!single.isInitialized) return;
    await Future.wait([
      single.player.setVolume(0),
      single.pause(),
      single.lock(),
    ]);
  }

  @override
  Future<void> silence() async {
    final single = TitiSingleEngine();
    final profile = TitiProfileEngine();
    final jobs = <Future<void>>[];
    if (single.isInitialized) {
      jobs.add(single.player.setVolume(0));
      jobs.add(single.pause());
      jobs.add(single.lock());
    }
    if (profile.isInitialized) {
      jobs.add(profile.player.setVolume(0));
      jobs.add(profile.pause());
      jobs.add(profile.lock());
    }
    await Future.wait(
      jobs.map(
        (job) => job.catchError(
          (Object error) => debugPrint('Banner video stop: $error'),
        ),
      ),
    );
  }

  @override
  VideoPlaybackSnapshot? capture(VideoPlaybackOrigin origin) {
    if (origin.engine == VideoPlaybackEngine.external) return null;
    final profile = origin.engine == VideoPlaybackEngine.profile;
    final initialized = profile
        ? TitiProfileEngine().isInitialized
        : TitiSingleEngine().isInitialized;
    if (!initialized) {
      return VideoPlaybackSnapshot(engine: origin.engine, url: origin.url);
    }
    final player = profile
        ? TitiProfileEngine().player
        : TitiSingleEngine().player;
    final currentUrl = profile
        ? TitiProfileEngine().currentUrl
        : TitiSingleEngine().currentUrl;
    final mapped = profile
        ? TitiProfileEngine().playerUrlsNotifier.value[TitiProfileEngine()
              .activeIndex]
        : TitiSingleEngine().playerUrls[TitiSingleEngine().activeIndex];
    final matches = currentUrl == origin.url && mapped == origin.url;
    return VideoPlaybackSnapshot(
      engine: origin.engine,
      url: origin.url,
      position: matches ? player.state.position : Duration.zero,
      volume: matches ? player.state.volume : 100,
      playing: matches && player.state.playing,
    );
  }

  @override
  Future<void> open(
    VideoPlaybackSnapshot snapshot,
    bool Function() stillValid,
  ) async {
    if (snapshot.engine == VideoPlaybackEngine.external) return;
    if (!stillValid() || !AudienceAccess.instance.canPlayUrl(snapshot.url)) {
      return;
    }
    final profile = snapshot.engine == VideoPlaybackEngine.profile;
    if (profile) {
      await TitiProfileEngine().unlockForNavigation();
    } else {
      await TitiSingleEngine().unlockForNavigation();
    }
    if (!stillValid()) return;
    if (profile) {
      await TitiProfileEngine().playUrl(snapshot.url, autoPlay: false);
    } else {
      await TitiSingleEngine().playUrl(snapshot.url, autoPlay: false);
    }
    if (!stillValid()) return;
    final mapped = profile
        ? TitiProfileEngine().playerUrlsNotifier.value[TitiProfileEngine()
              .activeIndex]
        : TitiSingleEngine().playerUrls[TitiSingleEngine().activeIndex];
    if (mapped != snapshot.url) return;
    final player = profile
        ? TitiProfileEngine().player
        : TitiSingleEngine().player;
    final duration = player.state.duration;
    final position = duration > Duration.zero && snapshot.position >= duration
        ? Duration.zero
        : snapshot.position;
    await player.seek(position);
    if (!stillValid() || !AudienceAccess.instance.canPlayUrl(snapshot.url)) {
      return;
    }
    if (!snapshot.playing) {
      await player.setVolume(snapshot.volume);
      return;
    }
    if (profile) {
      await TitiProfileEngine().play(volume: snapshot.volume);
    } else {
      await TitiSingleEngine().play(volume: snapshot.volume);
    }
  }
}

class BannerVideoNavigation {
  static Future<void> open({
    required NavigatorState navigator,
    required String url,
    required Widget child,
    required VoidCallback onPushed,
    BannerVideoPlaybackDriver? playback,
  }) async {
    final origin = VideoPlaybackRegistry.visibleOrigin;
    final port = playback ?? _EnginePlaybackPort();
    final queue = port.operations;
    final viewer = port.viewer;
    final bookmarks = port.captureBookmarks();
    final original = origin == null
        ? null
        : port.capture(origin)?.withPlaying(true);
    final handoff = VideoPlaybackHandoff(port, queue);
    final session = _BannerPlaybackSession(url, viewer, port, handoff);
    VideoPlaybackRegistry.add(session.lease);
    MaterialPageRoute<void>? route;
    try {
      await queue.run(() async {
        await origin?.suspendExternal?.call();
        await port.silence();
      });
      if (viewer == null || port.viewer != viewer || !navigator.mounted) return;
      route = MaterialPageRoute<void>(
        builder: (_) => _BannerPlaybackScope(session: session, child: child),
      );
      final popped = navigator.push<void>(route);
      onPushed(); // Banners remain available while this video is being watched.
      await popped;
      session.close();
      await route.completed; // Wait for the outgoing video widget to dispose.
      await WidgetsBinding.instance.endOfFrame;
    } finally {
      session.close();
      await session.stopped;
      VideoPlaybackRegistry.remove(session.lease);
      await queue.run(
        () => port.restoreBookmarks(
          bookmarks,
          sameViewer: viewer != null && port.viewer == viewer,
        ),
      );
      final currentOrigin = origin?.isVisible() == true
          ? origin
          : VideoPlaybackRegistry.visibleOrigin;
      final snapshot = identical(currentOrigin, origin)
          ? original
          : (currentOrigin == null ? null : port.capture(currentOrigin));
      bool canRestore() =>
          viewer != null &&
          port.viewer == viewer &&
          currentOrigin != null &&
          currentOrigin.isVisible() &&
          (WidgetsBinding.instance.lifecycleState == null ||
              WidgetsBinding.instance.lifecycleState ==
                  AppLifecycleState.resumed) &&
          (currentOrigin.engine == VideoPlaybackEngine.external ||
              port.canPlay(currentOrigin.url));
      await handoff.restore(snapshot, canRestore);
      if (snapshot != null && canRestore()) {
        final resumedLease = VideoPlaybackRegistry.foregroundBanner;
        if (resumedLease?.url == snapshot.url) resumedLease?.onRestored?.call();
      }
      if (currentOrigin?.resumeExternal != null) {
        await queue.run(() async {
          if (canRestore()) await currentOrigin!.resumeExternal!();
        });
      }
    }
  }
}

class _BannerPlaybackSession {
  _BannerPlaybackSession(this.url, this.viewer, this.port, this.handoff) {
    lease = VideoPlaybackLease(
      url,
      () => visible && foreground && !closed && sameViewer,
      onRestored: () => _suspended = false,
    );
  }
  final String url;
  final String? viewer;
  final BannerVideoPlaybackDriver port;
  final VideoPlaybackHandoff handoff;
  late final VideoPlaybackLease lease;
  bool visible = false;
  bool foreground = true;
  bool closed = false;
  bool get sameViewer => viewer != null && port.viewer == viewer;
  VideoPlaybackSnapshot? coveredSnapshot;
  Future<void> stopped = Future.value();
  bool _suspended = false;
  Future<void> activate() async {
    bool valid() =>
        visible &&
        foreground &&
        !closed &&
        sameViewer &&
        VideoPlaybackRegistry.isTop(lease);
    await handoff.activate(
      coveredSnapshot ??
          VideoPlaybackSnapshot(engine: VideoPlaybackEngine.home, url: url),
      valid,
    );
    if (valid()) _suspended = false;
  }

  void cover({bool preservePause = false}) {
    if (closed || _suspended) return;
    _suspended = true;
    coveredSnapshot = port.capture(
      VideoPlaybackOrigin(
        engine: VideoPlaybackEngine.home,
        url: url,
        postId: '',
        isVisible: () => false,
      ),
    );
    if (!preservePause) coveredSnapshot = coveredSnapshot?.withPlaying(true);
    // The route above may use another engine; stop only this video's engine.
    unawaited(
      port.silenceHome().catchError(
        (Object error) => debugPrint('Banner video cover: $error'),
      ),
    );
  }

  void close() {
    if (closed) return;
    closed = true;
    visible = false;
    stopped = port.silence().catchError(
      (Object error) => debugPrint('Banner video close: $error'),
    );
  }
}

class _BannerPlaybackScope extends StatefulWidget {
  const _BannerPlaybackScope({required this.session, required this.child});
  final _BannerPlaybackSession session;
  final Widget child;
  @override
  State<_BannerPlaybackScope> createState() => _BannerPlaybackScopeState();
}

class _BannerPlaybackScopeState extends State<_BannerPlaybackScope>
    with WidgetsBindingObserver {
  bool _wasVisible = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    final visible = route?.isCurrent == true;
    widget.session.visible = visible;
    if (visible && !_wasVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            ModalRoute.of(context)?.isCurrent == true &&
            (WidgetsBinding.instance.lifecycleState == null ||
                WidgetsBinding.instance.lifecycleState ==
                    AppLifecycleState.resumed)) {
          unawaited(
            widget.session.activate().catchError(
              (Object error) => debugPrint('Banner video start: $error'),
            ),
          );
        }
      });
    } else if (!visible && _wasVisible) {
      widget.session.cover();
    }
    _wasVisible = visible;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.session.foreground = state == AppLifecycleState.resumed;
    if (state != AppLifecycleState.resumed) {
      widget.session.cover(preservePause: true);
    } else if (mounted && ModalRoute.of(context)?.isCurrent == true) {
      unawaited(
        widget.session.activate().catchError(
          (Object error) => debugPrint('Banner video resume: $error'),
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.session.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) widget.session.close();
    },
    child: widget.child,
  );
}