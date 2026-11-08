import 'dart:async';
import 'audience_access.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'titi_single_engine.dart';

class TitiProfileCacheService {
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
}

class TitiProfileEngine {
  static final TitiProfileEngine _instance = TitiProfileEngine._internal();
  factory TitiProfileEngine() => _instance;
  TitiProfileEngine._internal() { _listenAudience(); }

  int _playGeneration = 0;
  bool _audienceListening = false;
  void _listenAudience() {
    if (_audienceListening) return;
    _audienceListening = true;
    AudienceAccess.instance.addListener(_onAudienceChanged);
  }

  void _onAudienceChanged() {
    var changed = false;
    if (_currentUrl.isNotEmpty && !AudienceAccess.instance.canPlayUrl(_currentUrl)) {
      _playGeneration++;
      _currentUrl = "";
      currentUrlNotifier.value = "";
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
  bool _userPaused = false;

  // بلوك القفل - اضافة فقط
  bool _isLocked = false;

  final ValueNotifier<int> activeIndexNotifier = ValueNotifier<int>(2);
  final ValueNotifier<List<String>> playerUrlsNotifier = ValueNotifier<List<String>>(["", "", "", "", "", ""]);
  final ValueNotifier<List<bool>> firstFrameReadyNotifier = ValueNotifier<List<bool>>([false, false, false, false, false, false]);
  final ValueNotifier<String> currentUrlNotifier = ValueNotifier<String>("");

  Player get player { _ensurePlayers(); return _players[_activeIndex]; }
  VideoController get videoController { _ensurePlayers(); return _controllers[_activeIndex]; }
  VideoController get activeController => videoController;
  VideoController getControllerByIndex(int index) { _ensurePlayers(); return _controllers[index.clamp(0, 5)]; }
  Player getPlayerByIndex(int index) { _ensurePlayers(); return _players[index.clamp(0, 5)]; }
  String get currentUrl => _currentUrl;
  bool get isInitialized => _players.isNotEmpty;
  int get activeIndex => _activeIndex;
  bool get isUserPaused => _userPaused;

  Future<void> _playIfAllowed(Player target) async {
    final url = _currentUrl;
    final request = _playGeneration;
    final index = _players.indexOf(target);
    bool allowed() => index >= 0 && index < _playerUrls.length &&
        !_isLocked && request == _playGeneration && _currentUrl == url &&
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
      p.stream.videoParams.listen((params) { if (params.w!= null && params.w! > 0 && params.h!= null && params.h! > 0) tryMarkReady(); });
      p.stream.playing.listen((playing) {
        if (playing) { tryMarkReady(); _userPaused = false; }
        else {
          if (_isLocked) return; // بلوك القفل
          if (!_userPaused && _playerUrls[idx] == _currentUrl && idx == _activeIndex) {
            final pos = p.state.position; final dur = p.state.duration;
            if (dur.inMilliseconds > 0 && pos < dur - const Duration(milliseconds: 800)) {
              Future.delayed(const Duration(milliseconds: 100), () { if (!_userPaused &&!_isLocked && _playerUrls[idx] == _currentUrl && AudienceAccess.instance.canPlayUrl(_currentUrl)) unawaited(_playIfAllowed(p)); });
            }
          }
        }
      });
      p.stream.error.listen((_) {
        _firstFrameReady[idx] = false; firstFrameReadyNotifier.value = List.from(_firstFrameReady); firstFrameReadyNotifier.notifyListeners();
        if (_isLocked) return; // بلوك القفل
        if (_playerUrls[idx] == _currentUrl && idx == _activeIndex &&!_userPaused) { Future.delayed(const Duration(milliseconds: 200), () { if (!_isLocked && idx == _activeIndex && _playerUrls[idx] == _currentUrl && AudienceAccess.instance.canPlayUrl(_currentUrl)) unawaited(_playIfAllowed(p)); }); }
      });
      p.stream.completed.listen((completed) {
        if (completed && idx == _activeIndex && _playerUrls[idx] == _currentUrl && !_isLocked && AudienceAccess.instance.canPlayUrl(_currentUrl)) {
          final pos = p.state.position; final dur = p.state.duration;
          if (dur.inMilliseconds > 0 && pos < dur - const Duration(seconds: 1)) { p.seek(pos); unawaited(_playIfAllowed(p)); }
        }
      });
    }
  }

  Player _createPlayer() {
    final config = PlayerConfiguration(bufferSize: 15 * 1024 * 1024, title: "TitiProfileEngine");
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
    p.setPlaylistMode(PlaylistMode.single); p.setVolume(100); return p;
  }

  Future<void> playSingleUrl(String url, {String? prevUrl, String? prevPrevUrl, String? nextUrl, String? nextNextUrl, String? nextNextNextUrl}) async {
    await playUrl(url, prevUrl: prevUrl, prevPrevUrl: prevPrevUrl, nextUrl: nextUrl, nextNextUrl: nextNextUrl, nextNextNextUrl: nextNextNextUrl);
  }

  Future<void> playUrl(String url, {bool autoPlay = true, String? prevUrl, String? prevPrevUrl, String? nextUrl, String? nextNextUrl, String? nextNextNextUrl}) async {
    if (url.isEmpty || !AudienceAccess.instance.canPlayUrl(url)) return;
    final request = ++_playGeneration;
    if (_isLocked) return; // بلوك القفل
    _ensurePlayers();
    if (_isOpening) _isOpening = false;
    _userPaused = false;
    try { await TitiSingleEngine().lock(); } catch (_) {}
    if (_isLocked || request != _playGeneration || !AudienceAccess.instance.canPlayUrl(url)) return;

    if (_currentUrl == url) {
      final curPlayer = _players[_activeIndex];
      if (curPlayer.state.playing && curPlayer.state.position < curPlayer.state.duration - const Duration(seconds: 1)) return;
      await curPlayer.seek(Duration.zero);
      if (!_isLocked && request == _playGeneration && AudienceAccess.instance.canPlayUrl(url) && !curPlayer.state.playing) await _playIfAllowed(curPlayer);
      return;
    }

    final existingIndex = _playerUrls.indexOf(url);
    if (existingIndex!= -1) {
      _activeIndex = existingIndex; activeIndexNotifier.value = _activeIndex;
      _currentUrl = url; _lastUrl = url; currentUrlNotifier.value = url;
      for (int i = 0; i < 6; i++) {
        if (i!= _activeIndex) {
          try { await _players[i].setVolume(0); await _players[i].pause(); } catch (_) {}
        } else {
          try { await _players[i].setVolume(100); } catch (_) {}
        }
      }
      try { await _players[_activeIndex].seek(Duration.zero); } catch (_) {}
      if (_isLocked || request != _playGeneration || !AudienceAccess.instance.canPlayUrl(url)) return;
      await _playIfAllowed(_players[_activeIndex]);
      _preloadNeighbors(prevUrl, prevPrevUrl, nextUrl, nextNextUrl, nextNextNextUrl);
      return;
    }

    _isOpening = true; _currentUrl = url; _lastUrl = url; currentUrlNotifier.value = url;
    try {
      bool isFirstEver = _playerUrls.every((e) => e.isEmpty);
      int targetIndex = isFirstEver? _activeIndex : (_activeIndex + 1) % 6;
      if (!isFirstEver && nextUrl!= null && _playerUrls[targetIndex] == nextUrl) targetIndex = (_activeIndex + 2) % 6;

      final cachedPath = await TitiProfileCacheService.getCachedPath(url);
      if (_isLocked || request != _playGeneration || !AudienceAccess.instance.canPlayUrl(url)) return;
      final String playPath = cachedPath?? url;

      _firstFrameReady[targetIndex] = false; firstFrameReadyNotifier.value = List.from(_firstFrameReady); firstFrameReadyNotifier.notifyListeners();

      await _players[targetIndex].open(Media(playPath), play: false);
      if (_isLocked || request != _playGeneration || !AudienceAccess.instance.canPlayUrl(url)) { await _players[targetIndex].pause(); return; }
      _playerUrls[targetIndex] = url; playerUrlsNotifier.value = List.from(_playerUrls);
      await _players[targetIndex].seek(Duration.zero);
      if (_isLocked || request != _playGeneration || !AudienceAccess.instance.canPlayUrl(url)) return;
      await _players[targetIndex].setVolume(100);
      if (autoPlay) await _playIfAllowed(_players[targetIndex]);
      if (_isLocked || request != _playGeneration || !AudienceAccess.instance.canPlayUrl(url)) { await _players[targetIndex].pause(); return; }

      _activeIndex = targetIndex; activeIndexNotifier.value = _activeIndex;
      for (int i = 0; i < 6; i++) if (i!= targetIndex) _players[i].pause();

      _preloadNeighbors(prevUrl, prevPrevUrl, nextUrl, nextNextUrl, nextNextNextUrl);
    } catch (e) { debugPrint("❌ [TitiProfileEngine Error]: $e"); } finally { _isOpening = false; }
  }

  void _preloadNeighbors(String? prevUrl, String? prevPrevUrl, String? nextUrl, String? nextNextUrl, String? nextNextNextUrl) {
    final request = _playGeneration;
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_isLocked || request != _playGeneration) return;
      final List<String?> all = [prevPrevUrl, prevUrl, nextUrl, nextNextUrl, nextNextNextUrl];
      for (String? u in all) {
        if (u == null || u.isEmpty || !AudienceAccess.instance.canPlayUrl(u) || _playerUrls.contains(u) || u == _currentUrl) continue;
        int idx = -1;
        for (int i = 0; i < 6; i++) { if (_playerUrls[i].isEmpty && i!= _activeIndex) { idx = i; break; } }
        if (idx == -1) { idx = (_activeIndex + 3) % 6; if (_playerUrls[idx] == _currentUrl) idx = (_activeIndex + 4) % 6; }
        if (idx == _activeIndex || idx == -1) continue;
        if (_playerUrls[idx] == _currentUrl) continue;
        _firstFrameReady[idx] = false;
        firstFrameReadyNotifier.value = List.from(_firstFrameReady);
        _playerUrls[idx] = u;
        playerUrlsNotifier.value = List.from(_playerUrls);
        TitiProfileCacheService.getCachedPath(u).then((cached) {
          if (_isLocked || request != _playGeneration || !AudienceAccess.instance.canPlayUrl(u) || _playerUrls[idx]!= u) return;
          _players[idx].open(Media(cached?? u), play: false).then((_) {
            _players[idx].pause();
          }).catchError((_) {});
        });
      }
    });
  }

  Future<void> pause() async { try { _userPaused = true; await _players[_activeIndex].pause(); } catch (_) {} }
  Future<void> play() async { if (_isLocked || !AudienceAccess.instance.canPlayUrl(_currentUrl)) return; try { _userPaused = false; await _playIfAllowed(_players[_activeIndex]); } catch (_) {} }
  Future<void> stop() async { _playGeneration++; try { _isOpening = false; _userPaused = true; _isLocked = true; for (var p in _players) await p.pause(); _currentUrl = ""; currentUrlNotifier.value = ""; } catch (_) { _isOpening = false; _isLocked = true; } }
  // بلوك القفل - دوال جديدة
  Future<void> lock() async { _playGeneration++; try { _isOpening = false; _userPaused = true; _isLocked = true; if (_currentUrl.isNotEmpty) _lastUrl = _currentUrl; for (int i = 0; i < _players.length; i++) { try { await _players[i].setVolume(0); if (i!= _activeIndex) await _players[i].pause(); } catch (_) {} } } catch (_) { _isLocked = true; } }
  Future<void> unlock() async { _isLocked = false; _userPaused = false; try { if (AudienceAccess.instance.canPlayUrl(_currentUrl)) await _players[_activeIndex].setVolume(100); } catch (_) {} }
  void dispose() {
    _playGeneration++;
    AudienceAccess.instance.removeListener(_onAudienceChanged);
    _audienceListening = false;
    try {
      for (var p in _players) p.dispose();
      _players.clear(); _controllers.clear();
      _playerUrls.fillRange(0, 6, ""); playerUrlsNotifier.value = List.from(_playerUrls);
      _firstFrameReady.fillRange(0, 6, false); firstFrameReadyNotifier.value = List.from(_firstFrameReady);
      _currentUrl = ""; currentUrlNotifier.value = "";
    } catch (_) {}
  }
}