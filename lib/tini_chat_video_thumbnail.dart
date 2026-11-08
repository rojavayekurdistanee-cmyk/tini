import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as video_thumb;

/// Shows a cached still frame without creating a long-lived VideoPlayer.
/// Video decoding is limited to two simultaneous native tasks to protect
/// scrolling performance in chats with many videos.
class TiniChatVideoThumbnail extends StatelessWidget {
  const TiniChatVideoThumbnail({super.key, required this.videoUrl});

  final String videoUrl;

  static final Map<String, Future<Uint8List?>> _inFlight = {};
  static const int _maxInMemoryEntries = 80;
  static const int _maxSimultaneousDecodes = 2;
  static int _activeDecodes = 0;
  static final Queue<Completer<void>> _waitingDecodes = Queue();

  static Future<T> _withDecodeSlot<T>(Future<T> Function() action) async {
    if (_activeDecodes >= _maxSimultaneousDecodes) {
      final gate = Completer<void>();
      _waitingDecodes.addLast(gate);
      await gate.future;
    }
    _activeDecodes++;
    try {
      return await action();
    } finally {
      _activeDecodes--;
      if (_waitingDecodes.isNotEmpty) {
        _waitingDecodes.removeFirst().complete();
      }
    }
  }

  static Future<Uint8List?> _thumbnail(String url) {
    final cached = _inFlight[url];
    if (cached != null) return cached;
    if (_inFlight.length >= _maxInMemoryEntries) {
      _inFlight.remove(_inFlight.keys.first);
    }
    final pending = _withDecodeSlot(() => _loadThumbnail(url));
    _inFlight[url] = pending;
    pending.then((bytes) {
      // A transient network error should not permanently poison this URL.
      if (bytes == null && identical(_inFlight[url], pending)) {
        _inFlight.remove(url);
      }
    });
    return pending;
  }

  static Future<Uint8List?> _loadThumbnail(String url) async {
    try {
      final dir = await getTemporaryDirectory();
      final hash = sha256.convert(utf8.encode(url));
      final file = File('${dir.path}/tini_chat_thumb_$hash.jpg');
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) return bytes;
      }
      final bytes = await video_thumb.VideoThumbnail.thumbnailData(
        video: url,
        imageFormat: video_thumb.ImageFormat.JPEG,
        maxWidth: 320,
        timeMs: 0,
        quality: 60,
      );
      if (bytes == null || bytes.isEmpty) return null;
      try {
        await file.writeAsBytes(bytes);
      } catch (_) {
        // A valid thumbnail should still render if disk caching fails.
      }
      return bytes;
    } catch (error) {
      debugPrint('Chat thumbnail unavailable: $error');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _thumbnail(videoUrl),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return const ColoredBox(
            color: Color(0xFF1A222C),
            child: Center(
              child: Icon(Icons.videocam_outlined,
                  color: Colors.white54, size: 36),
            ),
          );
        }
        return Image.memory(
          data,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => const ColoredBox(
            color: Color(0xFF1A222C),
            child: Center(
              child: Icon(Icons.videocam_outlined,
                  color: Colors.white54, size: 36),
            ),
          ),
        );
      },
    );
  }
}
