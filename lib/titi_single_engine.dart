import 'video_playback_handoff.dart';
import 'dart:async';
import 'audience_access.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TitiCacheService {
  static final _cache = DefaultCacheManager();
  static Future<String?> getCachedPath(String url) async {
    if (url.isEmpty) return null;
    try {
      final info = await _cache.getFileFromCache(url);
      if (info!= null && await info.file.exists()) {
        if (await info.file.length() > 100 * 1024) return info.file.path;
      }
      return null;
    } catch (_) { return null; }
  }
  static void precacheNext(List<String> urls) { return; }
}

class TitiSingleEngine {
  static final TitiSingleEngine _instance = TitiSingleEngine._internal();
  factory TitiSingleEngine() => _instance;
  TitiSingleEngine._internal() { _listenAudience(); }

  bool _audienceListening = false;
  void _listenAudience() {
    if (_audienceListening) return;
    _audienceListening = true;
    AudienceAccess.instance.addListener(_onAudienceChanged);
  }

  // A delayed resume or preload must recheck the current viewer and owner.
  void _onAudienceChanged() {
    var changed = false;
    if (_currentUrl.isNotEmpty && !AudienceAccess.instance.canPlayUrl(_currentUrl)) {
      _playGeneration++;
      _audioGeneration++;
      _watchTimer?.cancel();
      _currentUrl = "";
      changed = true;
    }
    for (int i = 0; i < _players.length; i++) {
      if (_playerUrls[i].isEmpty || AudienceAccess.instance.canPlayUrl(_playerUrls[i])) continue;
      unawaited(_players[i].setVolume(0));
      unawaited(_players[i].pause());
      _playerUrls[i] = "";
      _firstFrameReady[i] = false;
      changed = true;
    }
    // Counter updates do not need to rebuild video slots/controllers.
    if (changed) {
      playerUrlsNotifier.value = List.from(_playerUrls);
      firstFrameReadyNotifier.value = List.from(_firstFrameReady);
    }
  }

  final List<Player> _players = [];
  final List<VideoController> _controllers = [];
  final List<String> _playerUrls = ["", "", "", "", "", ""];
  final List<bool> _firstFrameReady = [false, false, false, false, false, false];
  int _activeIndex = 2;

  String _currentUrl = "";
  String _lastUrl = "";
  bool _isOpening = false;
  int _playGeneration = 0; // [Fix]: أحدث طلب تشغيل فقط يملك حق تبديل الفيديو النشط.
  Future<void> _playQueue = Future<void>.value();
  Future<void> _audioQueue = Future<void>.value();
  int _audioGeneration = 0;
  final Map<int, Future<void>> _preloadTasks = {};
  Timer? _watchTimer;
  String? _lastTrackedPostId;

  bool _userPaused = false;
  bool _isLocked = false;

  final ValueNotifier<int> activeIndexNotifier = ValueNotifier<int>(2);
  final ValueNotifier<List<String>> playerUrlsNotifier = ValueNotifier<List<String>>(["", "", "", "", "", ""]);
  final ValueNotifier<List<bool>> firstFrameReadyNotifier = ValueNotifier<List<bool>>([false, false, false, false, false, false]);

  Player get player { _ensurePlayers(); return _players[_activeIndex]; }
  VideoController get videoController { _ensurePlayers(); return _controllers[_activeIndex]; }
  VideoController get activeController => videoController;
  VideoController getControllerByIndex(int index) { _ensurePlayers(); return _controllers[index.clamp(0, 5)]; }
  Player getPlayerByIndex(int index) { _ensurePlayers(); return _players[index.clamp(0, 5)]; }
  String get currentUrl => _currentUrl;
  bool get isInitialized => _players.isNotEmpty;
  int get activeIndex => _activeIndex;
  bool get isUserPaused => _userPaused;
  List<String> get playerUrls => _playerUrls;
  List<bool> get firstFrameReady => _firstFrameReady;
  bool isFirstFrameReady(int index) => _firstFrameReady[index.clamp(0, 5)];
  void ensureInitialized() => _ensurePlayers();
  Future<void> warmup() async { _ensurePlayers(); await Future.delayed(const Duration(milliseconds: 600)); }

  Future<void> _playIfAllowed(Player target) async {
    final url = _currentUrl;
    final request = _playGeneration;
    final index = _players.indexOf(target);
    bool allowed() => index >= 0 && index < _playerUrls.length &&
        !_isLocked && request == _playGeneration && _currentUrl == url && VideoPlaybackRegistry.allowsHome(url) &&
        _playerUrls[index] == url && AudienceAccess.instance.canPlayUrl(url);
    if (!allowed()) return;
    await target.play();
    if (!allowed()) {
      await target.setVolume(0);
      await target.pause();
    }
  }

  void _ensurePlayers() {
    _listenAudience();
    if (_players.length == 6) return;
    for (int i = 0; i < 6; i++) {
      final p = _createPlayer();
      _players.add(p);
      _controllers.add(VideoController(p));
      final int idx = i;
      void tryMarkReady() {
        final st = p.state;
        if (st.width!= null && st.width! > 0 && st.height!= null && st.height! > 0) {
          if (!_firstFrameReady[idx]) {
            _firstFrameReady[idx] = true;
            firstFrameReadyNotifier.value = List.from(_firstFrameReady);
          }
        }
      }
      p.stream.videoParams.listen((_) => tryMarkReady());
      p.stream.width.listen((_) => tryMarkReady());
      p.stream.height.listen((_) => tryMarkReady());
      p.stream.error.listen((_) { _firstFrameReady[idx] = false; firstFrameReadyNotifier.value = List.from(_firstFrameReady); });
    }
  }

  // [Fix]: مشغّل واحد فقط يملك حق إخراج الصوت؛ البقية صامتة ومتوقفة.
  Future<void> _focusAudio(int? audibleIndex, {double volume = 100}) {
    final int generation = ++_audioGeneration;
    final Future<void> action = _audioQueue.then<void>((_) async {
      if (generation!= _audioGeneration) return;
      if (_players.isEmpty) return;
      // [Fix]: لا تنتظر إيقاف المشغّلات الستة بالتتابع؛ أحدها قد يتأخر بعد الرفع.
      final List<Future<void>> silencing = [];
      for (int i = 0; i < _players.length; i++) {
        if (generation!= _audioGeneration) return;
        if (i == audibleIndex && !_isLocked && AudienceAccess.instance.canPlayUrl(_playerUrls[i])) continue;
        final p = _players[i];
        silencing.add(() async {
          try {
            await p.setVolume(0).timeout(const Duration(seconds: 2));
            if (generation!= _audioGeneration) return;
            if (p.state.playing) await p.pause().timeout(const Duration(seconds: 2));
          } catch (_) {}
        }());
      }
      await Future.wait(silencing);
      if (generation!= _audioGeneration || _isLocked || audibleIndex == null || !AudienceAccess.instance.canPlayUrl(_playerUrls[audibleIndex])) return;
      try { await _players[audibleIndex].setVolume(volume.clamp(0, 100).toDouble()).timeout(const Duration(seconds: 2)); } catch (_) {}
    });
    _audioQueue = action.catchError((_) {});
    return action;
  }

  Player _createPlayer() {
    final config = PlayerConfiguration(bufferSize: 15 * 1024 * 1024, title: "TitiSingleEngine");
    final p = Player(configuration: config);
    if (p.platform is NativePlayer) {
      final native = (p.platform as NativePlayer);
      native.setProperty("hwdec", "auto"); native.setProperty("framedrop", "vo");
      native.setProperty("cache", "yes"); native.setProperty("cache-pause", "no");
      native.setProperty("demuxer-max-bytes", "32M"); native.setProperty("demuxer-readahead-secs", "2");
      native.setProperty("cache-secs", "10");
      native.setProperty("demuxer-lavf-o", "reconnect=1,reconnect_streamed=1,reconnect_delay_max=2");
      native.setProperty("probesize", "32K"); native.setProperty("analyzeduration", "0");
      native.setProperty("vd-lavc-threads", "4"); native.setProperty("network-timeout", "5");
      native.setProperty("keep-open", "yes"); native.setProperty("keep-open-pause", "no");
      native.setProperty("background", "#000000"); native.setProperty("fps", "30");
      native.setProperty("video-sync", "audio"); native.setProperty("vd-lavc-skiploopfilter", "all");
    }
    p.setPlaylistMode(PlaylistMode.single); p.setVolume(0); return p;
  }

  Future<void> playUrl(String url, {bool autoPlay = true, String? prevUrl, String? prevPrevUrl, String? nextUrl, String? nextNextUrl, String? nextNextNextUrl, String? postId, List<String>? hashtags}) {
    if (url.isEmpty || _isLocked || !VideoPlaybackRegistry.allowsHome(url) || !AudienceAccess.instance.canPlayUrl(url)) return Future<void>.value();
    final int request = ++_playGeneration;
    final Future<void> action = _playQueue.then<void>((_) async {
      if (_isLocked || request!= _playGeneration || !AudienceAccess.instance.canPlayUrl(url)) return;
      await _playUrlNow(url, autoPlay: autoPlay, prevUrl: prevUrl, prevPrevUrl: prevPrevUrl,
          nextUrl: nextUrl, nextNextUrl: nextNextUrl, nextNextNextUrl: nextNextNextUrl,
          postId: postId, hashtags: hashtags, request: request);
    });
    _playQueue = action.catchError((_) {});
    return action;
  }

  Future<void> _playUrlNow(String url, {required int request, bool autoPlay = true, String? prevUrl, String? prevPrevUrl, String? nextUrl, String? nextNextUrl, String? nextNextNextUrl, String? postId, List<String>? hashtags}) async {
    if (_isLocked || request!= _playGeneration || !VideoPlaybackRegistry.allowsHome(url) || !AudienceAccess.instance.canPlayUrl(url)) return;
    _ensurePlayers();
    _userPaused = !autoPlay;

    if (_currentUrl == url && _playerUrls[_activeIndex] == url) {
      if (!autoPlay) {
        _userPaused = true;
        await _focusAudio(null);
        return;
      }
      final curPlayer = _players[_activeIndex];
      if (curPlayer.state.playing && curPlayer.state.position < curPlayer.state.duration - const Duration(seconds: 1)) {
        _startWatchTracker(postId, hashtags);
        await _focusAudio(_activeIndex);
        if (_isLocked || request!= _playGeneration || !AudienceAccess.instance.canPlayUrl(url)) return;
        _preloadNeighbors(prevUrl, prevPrevUrl, nextUrl, nextNextUrl, nextNextNextUrl);
        return;
      }
      await _focusAudio(_activeIndex);
      if (_isLocked || request!= _playGeneration || !AudienceAccess.instance.canPlayUrl(url)) return;
      try {
        if (!curPlayer.state.playing) {
          await _playIfAllowed(curPlayer);
        } else {
          await curPlayer.seek(Duration.zero);
          await _playIfAllowed(curPlayer);
        }
      } catch (_) {
        await _playIfAllowed(curPlayer);
      }
      if (_isLocked || request!= _playGeneration || !AudienceAccess.instance.canPlayUrl(url)) return;
      _startWatchTracker(postId, hashtags);
      _preloadNeighbors(prevUrl, prevPrevUrl, nextUrl, nextNextUrl, nextNextNextUrl);
      return;
    }

    int existingIndex = _playerUrls.indexOf(url);
    if (existingIndex!= -1 && _preloadTasks.containsKey(existingIndex)) {
      // [Fix]: إذا لم يكتمل التحميل المسبق افتح الفيديو بمشغّل حرّ بدل تعليق السكرول.
      existingIndex = -1;
    }
    if (existingIndex!= -1) {
      _activeIndex = existingIndex;
      activeIndexNotifier.value = _activeIndex;
      _currentUrl = url; _lastUrl = url;
      await _focusAudio(_activeIndex);
      if (_isLocked || request!= _playGeneration || !AudienceAccess.instance.canPlayUrl(url)) return;
      try { await _players[_activeIndex].seek(Duration.zero); } catch (_) {}
      if (_isLocked || request!= _playGeneration || !AudienceAccess.instance.canPlayUrl(url)) return;
      if (autoPlay) await _playIfAllowed(_players[_activeIndex]);
      _preloadNeighbors(prevUrl, prevPrevUrl, nextUrl, nextNextUrl, nextNextNextUrl);
      _startWatchTracker(postId, hashtags);
      return;
    }

    _isOpening = true; _currentUrl = url; _lastUrl = url;
    try {
      // [Fix]: كتم القديم أثناء تجهيز الفيديو الجديد يمنع سماع صوت لا تطابقه الصورة.
      await _focusAudio(null);
      if (_isLocked || request!= _playGeneration || !AudienceAccess.instance.canPlayUrl(url)) return;
      bool isFirstEver = _playerUrls.every((e) => e.isEmpty);
      int targetIndex = isFirstEver? _activeIndex : (_activeIndex + 1) % 6;
      if (!isFirstEver && nextUrl!= null && _playerUrls[targetIndex] == nextUrl) targetIndex = (_activeIndex + 2) % 6;
      if (_preloadTasks.containsKey(targetIndex)) {
        for (int i = 0; i < 6; i++) {
          final candidate = (_activeIndex + 1 + i) % 6;
          if (candidate!= _activeIndex && !_preloadTasks.containsKey(candidate)) {
            targetIndex = candidate;
            break;
          }
        }
      }
      if (_preloadTasks.containsKey(targetIndex)) {
        // [Fix]: لا تستخدم مشغّلاً ما زال يفتح ملفاً آخر ولا تنتظر كل التحميلات المسبقة.
        return;
      }
      if (_isLocked || request!= _playGeneration || !AudienceAccess.instance.canPlayUrl(url)) return;
      final cachedPath = await TitiCacheService.getCachedPath(url);
      if (_isLocked || request!= _playGeneration || !AudienceAccess.instance.canPlayUrl(url)) return;
      final String playPath = cachedPath?? url;

      _firstFrameReady[targetIndex] = false;
      firstFrameReadyNotifier.value = List.from(_firstFrameReady);
      // [Fix]: أزل ربط الفيديو السابق بهذا المشغّل قبل استبدال الملف المرئي.
      _playerUrls[targetIndex] = "";
      playerUrlsNotifier.value = List.from(_playerUrls);

      await _players[targetIndex].open(Media(playPath), play: false);
      if (_isLocked || request!= _playGeneration || !AudienceAccess.instance.canPlayUrl(url)) {
        _firstFrameReady[targetIndex] = false;
        firstFrameReadyNotifier.value = List.from(_firstFrameReady);
        return;
      }
      _playerUrls[targetIndex] = url;
      playerUrlsNotifier.value = List.from(_playerUrls);
      await _players[targetIndex].seek(Duration.zero);
      if (_isLocked || request!= _playGeneration || !AudienceAccess.instance.canPlayUrl(url)) return;
      // [Fix]: أوقف كل الأصوات السابقة قبل تشغيل صوت الفيديو الجديد.
      await _focusAudio(targetIndex);
      if (_isLocked || request!= _playGeneration || !AudienceAccess.instance.canPlayUrl(url)) return;
      if (autoPlay) await _playIfAllowed(_players[targetIndex]);
      if (_isLocked || request!= _playGeneration || !AudienceAccess.instance.canPlayUrl(url)) {
        try { await _players[targetIndex].pause(); } catch (_) {}
        return;
      }

      _activeIndex = targetIndex;
      activeIndexNotifier.value = _activeIndex;
      _preloadNeighbors(prevUrl, prevPrevUrl, nextUrl, nextNextUrl, nextNextNextUrl);
      _startWatchTracker(postId, hashtags);
    } catch (e) { debugPrint("❌ [TitiSingleEngine Error]: $e"); } finally { _isOpening = false; }
  }

  void _startWatchTracker(String? postId, List<String>? hashtags) {
    _watchTimer?.cancel();
    if (postId == null || postId.isEmpty || hashtags == null || hashtags.isEmpty) return;
    if (_lastTrackedPostId == postId) return;
    _lastTrackedPostId = postId;
    _watchTimer = Timer(const Duration(seconds: 3), () async {
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) return;
        for (String tag in hashtags) {
          String cleanTag = tag.toLowerCase().trim();
          if (cleanTag.startsWith('#')) cleanTag = cleanTag.substring(1);
          if (cleanTag.isEmpty) continue;
          await FirebaseFirestore.instance.collection('users').doc(uid).collection('hashtagInterests').doc(cleanTag).set({
            'name': cleanTag,
            'count': FieldValue.increment(0.5),
            'lastWatched': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      } catch (_) {}
    });
  }

  void _preloadNeighbors(String? prevUrl, String? prevPrevUrl, String? nextUrl, String? nextNextUrl, String? nextNextNextUrl) {
    final int request = _playGeneration;
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_isLocked || request!= _playGeneration) return;
      final List<String?> all = [prevPrevUrl, prevUrl, nextUrl, nextNextUrl, nextNextNextUrl];
      for (String? u in all) {
        // [Fix]: احجز خانتين حرتين للتمرير السريع حتى لا تُشغل التحميلات كل المشغّلات.
        if (_preloadTasks.length >= 3) break;
        if (u == null || u.isEmpty || !AudienceAccess.instance.canPlayUrl(u) || _playerUrls.contains(u) || u == _currentUrl) continue;
        int idx = -1;
        for (int i = 0; i < 6; i++) {
          if (_playerUrls[i].isEmpty && i!= _activeIndex && !_preloadTasks.containsKey(i)) { idx = i; break; }
        }
        if (idx == -1) {
          for (int i = 3; i < 8; i++) {
            final candidate = (_activeIndex + i) % 6;
            if (candidate!= _activeIndex && !_preloadTasks.containsKey(candidate)) { idx = candidate; break; }
          }
        }
        if (idx == _activeIndex || idx == -1 || _playerUrls[idx] == _currentUrl) continue;
        _firstFrameReady[idx] = false;
        firstFrameReadyNotifier.value = List.from(_firstFrameReady);
        _playerUrls[idx] = u;
        playerUrlsNotifier.value = List.from(_playerUrls);
        final String preloadUrl = u;
        final int preloadIndex = idx;
        // [Fix]: احجز مشغّلاً منفصلاً لكل تحميل مسبق حتى لا تتداخل عمليات open.
        bool loaded = false;
        final Future<void> task = () async {
          try {
            final cached = await TitiCacheService.getCachedPath(preloadUrl);
            if (_isLocked || request!= _playGeneration || !AudienceAccess.instance.canPlayUrl(preloadUrl) || _playerUrls[preloadIndex]!= preloadUrl) return;
            // [Fix]: التحميل المسبق لا يحق له إخراج صوت، حتى لو كانت الخانة مستخدمة سابقاً.
            await _players[preloadIndex].setVolume(0);
            await _players[preloadIndex].pause();
            if (_isLocked || request!= _playGeneration || !AudienceAccess.instance.canPlayUrl(preloadUrl) || _playerUrls[preloadIndex]!= preloadUrl) return;
            await _players[preloadIndex].open(Media(cached?? preloadUrl), play: false);
            if (preloadIndex!= _activeIndex) {
              await _players[preloadIndex].setVolume(0);
              await _players[preloadIndex].pause();
            }
            if (_isLocked || request!= _playGeneration || !AudienceAccess.instance.canPlayUrl(preloadUrl) || _playerUrls[preloadIndex]!= preloadUrl) return;
            loaded = true;
          } catch (_) {} finally {
            if (!loaded && _playerUrls[preloadIndex] == preloadUrl) {
              _playerUrls[preloadIndex] = "";
              _firstFrameReady[preloadIndex] = false;
              playerUrlsNotifier.value = List.from(_playerUrls);
              firstFrameReadyNotifier.value = List.from(_firstFrameReady);
            }
          }
        }();
        _preloadTasks[preloadIndex] = task;
        task.whenComplete(() {
          if (identical(_preloadTasks[preloadIndex], task)) {
            _preloadTasks.remove(preloadIndex);
            // [Fix]: تابع تحميل بقية الجيران عند تحرير خانة، من دون تعطيل التشغيل.
            if (loaded && !_isLocked && request == _playGeneration) {
              _preloadNeighbors(prevUrl, prevPrevUrl, nextUrl, nextNextUrl, nextNextNextUrl);
            }
          }
        });
      }
    });
  }

  void precacheUpcoming(List<String> urls) { if (urls.isEmpty) return; final filtered = urls.where((u) => u.isNotEmpty && AudienceAccess.instance.canPlayUrl(u) && u!= _currentUrl).toList(); if (filtered.isEmpty) return; TitiCacheService.precacheNext(filtered); }
  Future<void> pause() async {
    try {
      _userPaused = true;
      await _players[_activeIndex].pause();
    } catch (e) {}
  }
  Future<void> play({double? volume}) async {
    try {
      if (_isLocked || !VideoPlaybackRegistry.allowsHome(_currentUrl) || !AudienceAccess.instance.canPlayUrl(_currentUrl)) return;
      _userPaused = false;
      await _focusAudio(_activeIndex, volume: volume ?? 100);
      final p = _players[_activeIndex];
      if (!p.state.playing) {
        await _playIfAllowed(p);
      }
    } catch (e) {}
  }
  Future<void> forceResumeForTab() async {
    if (!VideoPlaybackRegistry.allowsLegacyResume) return;
    try {
      if (_isLocked || !AudienceAccess.instance.canPlayUrl(_currentUrl.isNotEmpty ? _currentUrl : _lastUrl)) return; // مهم: لا ترجع تشتغل وانت بالبروفايل/رسائل
      _isOpening = false;
      _userPaused = false;
      final p = _players[_activeIndex];
      if (_currentUrl.isNotEmpty) {
        if (_playerUrls[_activeIndex] == _currentUrl) {
          await _focusAudio(_activeIndex);
          if (!p.state.playing) await _playIfAllowed(p);
        } else if (_lastUrl.isNotEmpty) {
          await playUrl(_lastUrl, autoPlay: true);
        }
        await _focusAudio(_activeIndex);
      } else if (_lastUrl.isNotEmpty) {
        await playUrl(_lastUrl, autoPlay: true);
      }
    } catch (_) {}
  }
  Future<void> resumeLast() async {
    if (!VideoPlaybackRegistry.allowsLegacyResume) return;
    try {
      if (_isLocked) return;
      if (_lastUrl.isEmpty || !AudienceAccess.instance.canPlayUrl(_lastUrl)) return;
      _userPaused = false;
      await _focusAudio(_activeIndex);
      final state = _players[_activeIndex].state;
      if (state.width == null || state.width == 0) { await playUrl(_lastUrl, autoPlay: true); }
      else { if (_currentUrl == _lastUrl) { await _playIfAllowed(_players[_activeIndex]); } else { await playUrl(_lastUrl, autoPlay: true); } }
    } catch (e) {}
  }
  Future<void> lock() async {
    try {
      _isLocked = true;
      _userPaused = true;
      _isOpening = false;
      _playGeneration++;
      if (_currentUrl.isNotEmpty) _lastUrl = _currentUrl;
      await _focusAudio(null);
    } catch (e) {
      _isLocked = true;
      _isOpening = false;
    }
  }


  Future<void> emergencyUnlock() async {
    if (!VideoPlaybackRegistry.allowsLegacyResume) return;
    try {
      _isLocked = false;
      _userPaused = false;
      _isOpening = false;
      if (!AudienceAccess.instance.canPlayUrl(_currentUrl.isNotEmpty ? _currentUrl : _lastUrl)) { await _focusAudio(null); return; }
      await _focusAudio(_activeIndex);
      final p = _players[_activeIndex];
      try {
        if (!p.state.playing) await _playIfAllowed(p);
      } catch (_) {}
    } catch (_) {
      _isLocked = false;
      _userPaused = false;
    }
  }
  
  // [Fix]: بعد اكتمال الرفع لا تشغل الفيديو القديم قبل ظهور الجديد على الشاشة.
  Future<void> unlockForNewUpload() async {
    if (!VideoPlaybackRegistry.allowsLegacyResume) return;
    _playGeneration++;
    _isLocked = false;
    _userPaused = false;
    _isOpening = false;
    _ensurePlayers();
    // [Fix]: لا تفك كتم أي مشغّل حتى تظهر صورة الفيديو الجديد.
    await _focusAudio(null);
  }

  // Restore the hidden page's selection without starting any audio.
  void restoreNavigationBookmark(String url) {
    _playGeneration++;
    _isLocked = true; _userPaused = true; _isOpening = false;
    _currentUrl = url; _lastUrl = url;
    final slot = _playerUrls.indexOf(url);
    if (url.isNotEmpty && slot >= 0) {
      _activeIndex = slot; activeIndexNotifier.value = slot;
    }
  }

  Future<void> unlockForNavigation() async {
    _playGeneration++;
    _isLocked = false; _userPaused = true; _isOpening = false;
    _ensurePlayers();
    await _focusAudio(null);
  }

  Future<void> unlockForHome() async {
    if (!VideoPlaybackRegistry.allowsLegacyResume) return;
    try {
      _isLocked = false;
      _userPaused = false;
      _isOpening = false;
      if (!AudienceAccess.instance.canPlayUrl(_currentUrl.isNotEmpty ? _currentUrl : _lastUrl)) { await _focusAudio(null); return; }
      await _focusAudio(_activeIndex);
      if (_currentUrl.isNotEmpty) {
        final p = _players[_activeIndex];
        if (_playerUrls[_activeIndex] == _currentUrl) {
          await _playIfAllowed(p);
          await _focusAudio(_activeIndex);
        } else if (_lastUrl.isNotEmpty) {
          await playUrl(_lastUrl, autoPlay: true);
        }
      } else if (_lastUrl.isNotEmpty) {
        await playUrl(_lastUrl, autoPlay: true);
      }
    } catch (_) {
      _isLocked = false;
      _userPaused = false;
    }
  }
  Future<void> stop() async { await lock(); }
  Future<void> setVolume(double volume) async { try { for (int i = 0; i < _players.length; i++) { await _players[i].setVolume(i == _activeIndex && !_isLocked && AudienceAccess.instance.canPlayUrl(_currentUrl)? volume : 0); } } catch (e) {} }
  Future<void> seek(Duration position) async { try { await _players[_activeIndex].seek(position); } catch (e) {} }
  void dispose() {
    AudienceAccess.instance.removeListener(_onAudienceChanged);
    _audienceListening = false;
    try {
      _watchTimer?.cancel();
      _playGeneration++;
      _audioGeneration++;
      _preloadTasks.clear();
      for (var p in _players) { p.dispose(); }
      _players.clear(); _controllers.clear();
      _playerUrls.fillRange(0, 6, ""); playerUrlsNotifier.value = List.from(_playerUrls);
      _firstFrameReady.fillRange(0, 6, false); firstFrameReadyNotifier.value = List.from(_firstFrameReady);
      _currentUrl = "";
    } catch (e) {}
  }
}