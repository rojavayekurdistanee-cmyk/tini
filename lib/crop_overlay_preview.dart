import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'crop_overlay_model.dart';

/// A media layer follows the project's clock. It never runs a separate loop,
/// and videos are silent so they cannot disturb the editor's audio mixer.
class CropOverlayVisual extends StatefulWidget {
  final CropOverlay overlay;
  final int positionMs;
  final bool playing;
  const CropOverlayVisual({
    super.key,
    required this.overlay,
    required this.positionMs,
    required this.playing,
  });
  @override
  State<CropOverlayVisual> createState() => _CropOverlayVisualState();
}

class _CropOverlayVisualState extends State<CropOverlayVisual> {
  VideoPlayerController? _controller;
  bool _syncing = false, _again = false, _failed = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didUpdateWidget(CropOverlayVisual oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.overlay.path != widget.overlay.path ||
        oldWidget.overlay.isVideo != widget.overlay.isVideo) {
      _open();
    } else {
      _sync();
    }
  }

  Future<void> _open() async {
    final generation = ++_generation;
    final previous = _controller;
    _controller = null;
    _failed = false;
    if (previous != null) await previous.dispose();
    if (!mounted || generation != _generation || !widget.overlay.isVideo) {
      return;
    }
    final controller = VideoPlayerController.file(
      File(widget.overlay.path),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted || generation != _generation) return;
      await controller.setVolume(0);
      if (!mounted || generation != _generation) return;
      setState(() {});
      _sync();
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _failed = true);
    }
  }

  Future<void> _sync() async {
    _again = true;
    if (_syncing) return;
    _syncing = true;
    try {
      while (mounted && _again) {
        _again = false;
        final c = _controller;
        if (c == null || !c.value.isInitialized) break;
        final target = widget.overlay
            .sourcePosition(widget.positionMs)
            .clamp(0, (c.value.duration.inMilliseconds - 1).clamp(0, 1 << 31));
        final play =
            widget.playing &&
            widget.overlay.visible(widget.positionMs) &&
            target < c.value.duration.inMilliseconds - 40;
        if ((c.value.position.inMilliseconds - target).abs() >
            (play ? 120 : 25)) {
          await c.seekTo(Duration(milliseconds: target));
        }
        if (!mounted || c != _controller) break;
        if (play && !c.value.isPlaying) await c.play();
        if (!play && c.value.isPlaying) await c.pause();
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      _syncing = false;
    }
  }

  @override
  void dispose() {
    ++_generation;
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.overlay.isVideo) {
      return Image.file(
        File(widget.overlay.path),
        fit: BoxFit.fill,
        gaplessPlayback: true,
        errorBuilder: (_, error, stack) => const Center(
          child: Icon(Icons.broken_image, color: Colors.white70),
        ),
      );
    }
    final c = _controller;
    if (_failed) {
      return const Center(
        child: Icon(Icons.error_outline, color: Colors.white70),
      );
    }
    if (c == null || !c.value.isInitialized) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return VideoPlayer(c);
  }
}

class CropOverlayCanvas extends StatelessWidget {
  final List<CropOverlay> overlays;
  final int positionMs;
  final bool playing;
  final String? selectedId;
  final ValueChanged<String>? onSelect;
  final void Function(CropOverlay, ScaleStartDetails)? onGestureStart;
  final void Function(CropOverlay, ScaleUpdateDetails, Size)? onGestureUpdate;
  final VoidCallback? onGestureEnd;
  const CropOverlayCanvas({
    super.key,
    required this.overlays,
    required this.positionMs,
    required this.playing,
    this.selectedId,
    this.onSelect,
    this.onGestureStart,
    this.onGestureUpdate,
    this.onGestureEnd,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final size = bounds.biggest;
      if (size.isEmpty) return const SizedBox.shrink();
      return ClipRect(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final o in overlays.where((o) => o.visible(positionMs)))
              Positioned(
                key: ValueKey(o.id),
                left: size.width * (o.centerX - o.width / 2),
                top:
                    size.height * o.centerY -
                    size.width * o.width / o.aspectRatio / 2,
                width: size.width * o.width,
                height: size.width * o.width / o.aspectRatio,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onSelect == null ? null : () => onSelect!(o.id),
                  onScaleStart: onGestureStart == null
                      ? null
                      : (d) => onGestureStart!(o, d),
                  onScaleUpdate: onGestureUpdate == null
                      ? null
                      : (d) => onGestureUpdate!(o, d, size),
                  onScaleEnd: onGestureEnd == null
                      ? null
                      : (_) => onGestureEnd!(),
                  child: DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                      border: selectedId == o.id
                          ? Border.all(color: Colors.white, width: 1.5)
                          : null,
                    ),
                    child: CropOverlayVisual(
                      overlay: o,
                      positionMs: positionMs,
                      playing: playing,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
