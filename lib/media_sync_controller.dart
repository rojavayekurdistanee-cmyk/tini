import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/foundation.dart';

class MediaSyncController {
  final AudioPlayer audio;
  final List<VideoPlayerController> videos;
  bool _isSyncing = false;

  MediaSyncController({required this.audio, required this.videos});

  Future<void> playAll() async {
    if (_isSyncing) return;
    _isSyncing = true;

    // 1. وقف الكل أول
    await Future.wait([
      ...videos.map((v) => v.pause()),
      audio.pause(),
    ]);

    // 2. تأكد إن الفيديوهات جاهزة
    for (var v in videos) {
      if (!v.value.isInitialized) {
        await v.initialize();
      }
    }

    // 3. رجّع الكل للثانية 0 ← هذا السطر اللي ناقص عندك
    await Future.wait([
      ...videos.map((v) => v.seekTo(Duration.zero)),
      audio.seek(Duration.zero),
    ]);

    // 4. شغّل الكل سوا
    final futures = <Future>[];
    for (var v in videos) {
      futures.add(v.play());
    }
    futures.add(audio.resume());
    
    await Future.wait(futures);
    _isSyncing = false;
  }

  Future<void> pauseAll() async {
    if (_isSyncing) return;
    _isSyncing = true;

    final futures = <Future>[];
    for (var v in videos) {
      futures.add(v.pause());
    }
    futures.add(audio.pause());
    
    await Future.wait(futures);
    _isSyncing = false;
  }

  void dispose() {}
}