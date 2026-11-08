import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class VoiceMessageBubble extends StatefulWidget {
  final String audioUrl;
  final String profileImgUrl;
  final bool isMe;
  final Duration duration;
  final String timeText;
  final bool isSeen;
  final String chatId;
  final List<int>? waveform;
  final DateTime? sortTime;

  const VoiceMessageBubble({
    super.key,
    required this.audioUrl,
    required this.profileImgUrl,
    required this.isMe,
    required this.duration,
    required this.timeText,
    this.isSeen = false,
    this.chatId = 'default',
    this.waveform,
    this.sortTime,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  // --- Player واحد مشترك لكل الفقاعات ---
  static final ap.AudioPlayer _globalPlayer = ap.AudioPlayer();
  static String? _currentlyPlayingUrl;
  static String? _currentChatId;
  static bool _isGlobalInitialized = false;
  static final Map<String, Duration> _savedPositions = {};
  // قائمة منفصلة لكل شات
  static final Map<String, List<String>> _playlists = {};
  static final Map<String, DateTime> _times = {};
  static final Map<String, String> _fileCache = {};

  bool _isPlaying = false;
  Duration _position = Duration.zero;

  // نخزن الاشتراكات عشان نلغيها بالـ dispose
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    final list = _playlists.putIfAbsent(widget.chatId, () => []);
    if (widget.sortTime != null) {
      _times[widget.audioUrl] = widget.sortTime!;
    } else {
      _times.putIfAbsent(widget.audioUrl, () => DateTime.now());
    }
    if (!list.contains(widget.audioUrl)) {
      list.add(widget.audioUrl);
    }
    // الأحدث أولاً، عشان currentIndex - 1 يروح للأحدث
    list.sort((a, b) => _times[b]!.compareTo(_times[a]!));
    if (_savedPositions.containsKey(widget.audioUrl)) {
      _position = _savedPositions[widget.audioUrl]!;
    }
    _initGlobalPlayer();
    _listenToPlayer();
  }

  static Future<String> _getCachedFile(String url) async {
    if (_fileCache.containsKey(url)) {
      final f = File(_fileCache[url]!);
      if (await f.exists()) return _fileCache[url]!;
    }
    final dir = await getTemporaryDirectory();
    final file = File("${dir.path}/${url.hashCode}.m4a");
    if (await file.exists()) {
      _fileCache[url] = file.path;
      return file.path;
    }
    final res = await http.get(Uri.parse(url));
    await file.writeAsBytes(res.bodyBytes);
    _fileCache[url] = file.path;
    return file.path;
  }

  // مرة وحدة لكامل التطبيق: التشغيل التلقائي للفويس التالي
  void _initGlobalPlayer() {
    if (_isGlobalInitialized) return;
    _isGlobalInitialized = true;

    _globalPlayer.onPlayerComplete.listen((_) async {
      if (_currentlyPlayingUrl != null) {
        _savedPositions.remove(_currentlyPlayingUrl);
        final list = _playlists[_currentChatId] ?? const <String>[];
        final currentIndex = list.indexOf(_currentlyPlayingUrl!);
        if (currentIndex > 0) {
          final nextUrl = list[currentIndex - 1];
          _currentlyPlayingUrl = nextUrl;
          final path = await _getCachedFile(nextUrl);
          _globalPlayer.play(ap.DeviceFileSource(path));
        } else {
          _currentlyPlayingUrl = null;
        }
      }
    });
  }

  // اشتراكات الفقاعة (مرة وحدة، وبتنلغي بالـ dispose)
  void _listenToPlayer() {
    _subs.add(_globalPlayer.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      final isThisOne = _currentlyPlayingUrl == widget.audioUrl;
      if (isThisOne) {
        setState(() => _isPlaying = s == ap.PlayerState.playing);
      } else {
        if (_isPlaying) {
          setState(() => _isPlaying = false);
        }
      }
    }));

    _subs.add(_globalPlayer.onPositionChanged.listen((p) {
      if (!mounted) return;
      if (_currentlyPlayingUrl == widget.audioUrl) {
        setState(() {
          _position = p;
          _savedPositions[widget.audioUrl] = p;
        });
      }
    }));

    _subs.add(_globalPlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;
      if (_currentlyPlayingUrl == widget.audioUrl) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      }
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    // لا تعمل dispose للـ _globalPlayer لأنه مشترك!
    // بس وقف اذا كانت هاي الفقاعة هي اللي شغالة
    if (_currentlyPlayingUrl == widget.audioUrl) {
      _globalPlayer.stop();
      _currentlyPlayingUrl = null;
    }
    super.dispose();
  }

  Future<void> _handlePlayPause() async {
    if (_isPlaying && _currentlyPlayingUrl == widget.audioUrl) {
      await _globalPlayer.pause();
      _savedPositions[widget.audioUrl] = _position;
      return;
    }

    // اذا في فويس ثاني شغال، وقفه قبل ما تشغل الجديد
    if (_currentlyPlayingUrl != null && _currentlyPlayingUrl != widget.audioUrl) {
      final oldPos = await _globalPlayer.getCurrentPosition();
      if (oldPos != null && _currentlyPlayingUrl != null) {
        _savedPositions[_currentlyPlayingUrl!] = oldPos;
      }
      await _globalPlayer.stop();
    }

    _currentlyPlayingUrl = widget.audioUrl;
    _currentChatId = widget.chatId;
    final savedPos = _savedPositions[widget.audioUrl] ?? _position;
    final path = await _getCachedFile(widget.audioUrl);

    if (savedPos > Duration.zero &&
        savedPos.inMilliseconds < widget.duration.inMilliseconds) {
      await _globalPlayer.play(ap.DeviceFileSource(path));
      await _globalPlayer.seek(savedPos);
    } else {
      _currentlyPlayingUrl = widget.audioUrl;
      await _globalPlayer.play(ap.DeviceFileSource(path));
    }
  }

  void _seekTo(double percent) {
    if (widget.duration.inMilliseconds == 0) return;
    final newPos = Duration(
      milliseconds: (widget.duration.inMilliseconds * percent).toInt(),
    );
    setState(() {
      _position = newPos;
    });
    _savedPositions[widget.audioUrl] = newPos;
    if (_currentlyPlayingUrl == widget.audioUrl) {
      _globalPlayer.seek(newPos);
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _buildProfile(Color bubbleColor) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: 22,
          backgroundImage: widget.profileImgUrl.isNotEmpty
              ? NetworkImage(widget.profileImgUrl)
              : null,
          backgroundColor: const Color(0xFF2A3942),
          child: widget.profileImgUrl.isEmpty
              ? const Icon(Icons.person, size: 22, color: Colors.white54)
              : null,
        ),
        Positioned(
          bottom: -3,
          right: widget.isMe ? null : -3,
          left: widget.isMe ? -3 : null,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: bubbleColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: widget.isMe ? Colors.white : const Color(0xFF53BDEB),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.mic,
                  size: 10,
                  color: widget.isMe ? const Color(0xFF0F5A4E) : Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color bubbleColor =
        widget.isMe ? const Color(0xFF0F5A4E) : const Color(0xFF232D35);

    final Color waveActive =
        widget.isMe ? Colors.white : const Color(0xFF53BDEB);

    final Color waveInactive = widget.isMe
        ? const Color(0xFF4AA395).withOpacity(0.7)
        : const Color(0xFF4A5660);

    final Color timeColor =
        widget.isMe ? const Color(0xFF7ABDB2) : const Color(0xFF8696A0);

    return Container(
      margin: EdgeInsets.only(
        left: widget.isMe ? 40 : 8,
        right: widget.isMe ? 8 : 40,
        top: 4,
        bottom: 4,
      ),
      child: Row(
        mainAxisAlignment:
            widget.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              constraints: const BoxConstraints(
                maxWidth: 340,
                minWidth: 270,
              ),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(widget.isMe ? 16 : 2),
                  bottomRight: Radius.circular(widget.isMe ? 2 : 16),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 1),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (!widget.isMe) _buildProfile(bubbleColor),
                      if (!widget.isMe) const SizedBox(width: 10),
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: widget.isMe
                              ? Colors.white
                              : const Color(0xFF53BDEB),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return GestureDetector(
                              onTapDown: (details) {
                                final percent = (details.localPosition.dx /
                                        constraints.maxWidth)
                                    .clamp(0.0, 1.0);
                                _seekTo(percent);
                              },
                              onHorizontalDragUpdate: (details) {
                                final percent = (details.localPosition.dx /
                                        constraints.maxWidth)
                                    .clamp(0.0, 1.0);
                                _seekTo(percent);
                              },
                              child: SizedBox(
                                height: 26,
                                child: CustomPaint(
                                  size: const Size(double.infinity, 26),
                                  painter: _TitiWavePainter(
                                    progress: widget.duration.inMilliseconds == 0
                                        ? 0
                                        : (_position.inMilliseconds /
                                                widget.duration.inMilliseconds)
                                            .clamp(0.0, 1.0),
                                    activeColor: waveActive,
                                    inactiveColor: waveInactive,
                                    waveform: widget.waveform,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _handlePlayPause,
                        child: Icon(
                          _isPlaying && _currentlyPlayingUrl == widget.audioUrl
                              ? Icons.pause
                              : Icons.play_arrow,
                          color: widget.isMe
                              ? Colors.white
                              : const Color(0xFF8A99A4),
                          size: 34,
                        ),
                      ),
                      if (widget.isMe) const SizedBox(width: 10),
                      if (widget.isMe) _buildProfile(bubbleColor),
                    ],
                  ),
                  const SizedBox(height: 1),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (!widget.isMe) const SizedBox(width: 44),
                      if (!widget.isMe) const SizedBox(width: 10),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                widget.timeText,
                                style: TextStyle(
                                  color: timeColor,
                                  fontSize: 10,
                                  height: 1,
                                  fontFamily: 'Tajawal',
                                ),
                              ),
                              if (widget.isMe) const SizedBox(width: 3),
                              if (widget.isMe)
                                Icon(
                                  widget.isSeen ? Icons.done_all : Icons.done,
                                  size: 10,
                                  color: widget.isSeen
                                      ? const Color(0xFF53BDEB)
                                      : timeColor,
                                ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 34,
                        child: Center(
                          child: Text(
                            _isPlaying && _currentlyPlayingUrl == widget.audioUrl
                                ? _fmt(_position)
                                : _fmt(widget.duration),
                            style: TextStyle(
                              color: timeColor,
                              fontSize: 10,
                              height: 1,
                              fontFamily: 'Tajawal',
                            ),
                          ),
                        ),
                      ),
                      if (widget.isMe) const SizedBox(width: 10),
                      if (widget.isMe) const SizedBox(width: 44),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TitiWavePainter extends CustomPainter {
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final List<int>? waveform;

  _TitiWavePainter({
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    this.waveform,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final List<double> pattern = (waveform != null && waveform!.isNotEmpty)
        ? waveform!.map((e) => (e / 100).clamp(0.0, 1.0).toDouble()).toList()
        : [
    ];
    final double gap = size.width / pattern.length;
    for (int i = 0; i < pattern.length; i++) {
      final double x = i * gap + gap / 2;
      final bool isActive = (i / pattern.length) <= progress;
      final paint = Paint()
        ..color = isActive ? activeColor : inactiveColor
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2.2;
      final double h = pattern[i];
      if (h == 0.0) {
        canvas.drawCircle(Offset(x, size.height / 2), 1.1, paint);
      } else {
        final double barH = h * size.height * 0.85;
        canvas.drawLine(
          Offset(x, size.height / 2 - barH / 2),
          Offset(x, size.height / 2 + barH / 2),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TitiWavePainter old) => old.progress != progress;
}