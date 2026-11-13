import 'dart:async';

enum VideoPlaybackEngine { home, profile, external }

class VideoPlaybackOrigin {
  const VideoPlaybackOrigin({
    required this.engine,
    required this.url,
    required this.postId,
    required this.isVisible,
    this.suspendExternal,
    this.resumeExternal,
  });
  final VideoPlaybackEngine engine;
  final String url;
  final String postId;
  final bool Function() isVisible;
  final Future<void> Function()? suspendExternal;
  final Future<void> Function()? resumeExternal;
}

class VideoPlaybackBookmarks {
  const VideoPlaybackBookmarks({this.homeUrl, this.profileUrl});
  final String? homeUrl;
  final String? profileUrl;
}

class VideoPlaybackSnapshot {
  const VideoPlaybackSnapshot({
    required this.engine,
    required this.url,
    this.position = Duration.zero,
    this.volume = 100,
    this.playing = true,
  });
  final VideoPlaybackEngine engine;
  final String url;
  final Duration position;
  final double volume;
  final bool playing;
  VideoPlaybackSnapshot withPlaying(bool value) => VideoPlaybackSnapshot(
    engine: engine,
    url: url,
    position: position,
    volume: volume,
    playing: value,
  );
}

class VideoPlaybackLease {
  VideoPlaybackLease(this.url, this.isVisible, {this.onRestored});
  final String url;
  final bool Function() isVisible;
  final void Function()? onRestored;
}

/// Only foreground banner routes constrain background autoplay. A route opened
/// above a banner (profile, share sheet, etc.) keeps its normal playback rules.
class VideoPlaybackRegistry {
  static final Map<Object, VideoPlaybackOrigin? Function()> _origins = {};
  static final List<VideoPlaybackLease> _leases = [];
  static void watch(Object owner, VideoPlaybackOrigin? Function() origin) =>
      _origins[owner] = origin;
  static void unwatch(Object owner) => _origins.remove(owner);
  static VideoPlaybackOrigin? get visibleOrigin {
    for (final capture in _origins.values.toList().reversed) {
      final value = capture();
      if (value != null && value.isVisible()) return value;
    }
    return null;
  }

  static void add(VideoPlaybackLease lease) => _leases.add(lease);
  static void remove(VideoPlaybackLease lease) => _leases.remove(lease);
  static bool isTop(VideoPlaybackLease lease) =>
      _leases.isNotEmpty && identical(_leases.last, lease);
  static VideoPlaybackLease? get foregroundBanner {
    for (final lease in _leases.reversed) {
      if (lease.isVisible()) return lease;
    }
    return null;
  }

  static bool allowsHome(String url) =>
      foregroundBanner == null || foregroundBanner!.url == url;
  static bool get allowsProfile => foregroundBanner == null;
  static bool get allowsLegacyResume => foregroundBanner == null;
}

abstract class VideoPlaybackPort {
  Future<void> silence();
  Future<void> open(VideoPlaybackSnapshot snapshot, bool Function() stillValid);
}

/// Serial ownership changes prevent a slow open/seek from racing a back press
/// or a second banner. Every async stage rechecks route/account visibility.
class VideoPlaybackQueue {
  Future<void> _tail = Future.value();
  Future<void> run(Future<void> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.catchError((Object _) {});
    return next;
  }
}

class VideoPlaybackHandoff {
  VideoPlaybackHandoff(this.port, this.queue);
  final VideoPlaybackPort port;
  final VideoPlaybackQueue queue;
  Future<void> activate(
    VideoPlaybackSnapshot snapshot,
    bool Function() valid,
  ) => queue.run(() async {
    if (!valid()) return;
    await port.silence();
    if (!valid()) return;
    await port.open(snapshot, valid);
  });
  Future<void> restore(
    VideoPlaybackSnapshot? snapshot,
    bool Function() valid,
  ) => queue.run(() async {
    await port.silence();
    if (snapshot == null || !valid()) return;
    await port.open(snapshot, valid);
  });
}
