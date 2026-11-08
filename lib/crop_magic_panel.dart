import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'crop_magic_effects.dart';

/// Lightweight, animated Magic samples. Reuses already generated timeline
/// thumbnails; no extra video decoders or FFmpeg encoding jobs are started.
/// All visible tiles animate independently from the *same* small frame pool.
class CropMagicPanel extends StatefulWidget {
  final String sourcePath;
  final Duration sourceStart;
  final Duration sourceEnd;
  final Duration sourceDuration;
  final List<Uint8List> previewFrames;
  final String? initialEffect;
  final ValueChanged<String?> onPreview;
  final ValueChanged<String?> onConfirm;
  final VoidCallback onCancel;

  const CropMagicPanel({
    super.key,
    required this.sourcePath,
    required this.sourceStart,
    required this.sourceEnd,
    this.sourceDuration = Duration.zero,
    this.previewFrames = const [],
    required this.initialEffect,
    required this.onPreview,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<CropMagicPanel> createState() => _CropMagicPanelState();
}

class _CropMagicPanelState extends State<CropMagicPanel>
    with WidgetsBindingObserver {
  final ValueNotifier<int> _tick = ValueNotifier<int>(0);
  Timer? _timer;
  bool _frameTab = false;
  String? _chosen;
  List<Uint8List> _frames = const [];

  @override
  void initState() {
    super.initState();
    _chosen = widget.initialEffect;
    _frameTab = CropMagicEffects.find(_chosen)?.isFrame ?? false;
    _selectFrames();
    WidgetsBinding.instance.addObserver(this);
    _startAnimation();
  }

  @override
  void didUpdateWidget(CropMagicPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.previewFrames, widget.previewFrames) ||
        oldWidget.sourcePath != widget.sourcePath ||
        oldWidget.sourceStart != widget.sourceStart ||
        oldWidget.sourceEnd != widget.sourceEnd ||
        oldWidget.sourceDuration != widget.sourceDuration) {
      _selectFrames();
    }
  }

  void _selectFrames() {
    final frames = widget.previewFrames;
    if (frames.isEmpty) {
      _frames = const [];
      return;
    }
    final totalUs = widget.sourceDuration.inMicroseconds;
    if (totalUs <= 0) {
      _frames = List<Uint8List>.unmodifiable(
          List<Uint8List>.generate(math.min(frames.length, 12),
              (i) => frames[(i * frames.length / math.min(frames.length, 12)).floor()]));
      return;
    }
    final begin = (widget.sourceStart.inMicroseconds / totalUs)
        .clamp(0.0, 1.0);
    final end = (widget.sourceEnd.inMicroseconds / totalUs)
        .clamp(begin, 1.0);
    // Up to twelve stills sampled from the selected section. Image decoding is
    // shared via Flutter's image cache; every effect shows moving content.
    final count = math.min(12, frames.length);
    _frames = List<Uint8List>.unmodifiable(List<Uint8List>.generate(count, (i) {
      final fraction = begin + (end - begin) * (count == 1 ? 0 : i / (count - 1));
      final index = (fraction * (frames.length - 1)).round()
          .clamp(0, frames.length - 1);
      return frames[index];
    }));
  }

  void _startAnimation() {
    // Eight frames a second for small preview cards, with no decoder load.
    _timer ??= Timer.periodic(const Duration(milliseconds: 125), (_) {
      if (mounted) _tick.value += 1;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startAnimation();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final choices = CropMagicEffects.all
        .where((e) => e.isFrame == _frameTab).toList();
    return Container(
      color: const Color(0xFF0F1720),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 5),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          IconButton(onPressed: widget.onCancel,
              icon: const Icon(Icons.close, color: Colors.white)),
          const SizedBox(width: 4),
          const Text('سحر', style: TextStyle(color: Colors.white,
              fontWeight: FontWeight.w700, fontSize: 15)),
          const Spacer(),
          IconButton(onPressed: () => widget.onConfirm(_chosen),
              icon: const Icon(Icons.check, color: Colors.teal, size: 27)),
        ]),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _tab('فيديو', false),
          const SizedBox(width: 12),
          _tab('إطار', true),
        ]),
        const SizedBox(height: 12),
        SizedBox(height: 115, child: ListView.builder(
          reverse: true,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          itemCount: choices.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) return _tile(null, 'بدون');
            final effect = choices[i - 1];
            return _tile(effect.id, effect.title);
          },
        )),
        const SizedBox(height: 6),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('كل معاينة متحركة وتتكرر تلقائياً • اختر مؤثراً لتجربته',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: Colors.white54)),
        ),
      ]),
    );
  }

  Widget _tab(String title, bool frame) {
    final active = _frameTab == frame;
    return GestureDetector(
      onTap: () => setState(() => _frameTab = frame),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF1A3232) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? Colors.teal : Colors.white12)),
        child: Text(title, style: TextStyle(
          color: active ? Colors.tealAccent : Colors.white70)),
      ),
    );
  }

  Widget _tile(String? id, String title) {
    final selected = _chosen == id;
    return GestureDetector(
      onTap: () {
        if (_chosen == id) return;
        setState(() => _chosen = id);
        widget.onPreview(id);
      },
      child: SizedBox(width: 91, child: Column(children: [
        Container(
          width: 80, height: 79,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFF1A222C),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? Colors.tealAccent : Colors.white24,
                width: selected ? 2.5 : 1)),
          child: id == null
              ? const Icon(Icons.block, color: Colors.white60, size: 28)
              : RepaintBoundary(child: ValueListenableBuilder<int>(
                  valueListenable: _tick,
                  builder: (context, tick, _) => _MagicDemoVisual(
                    id: id,
                    progress: (tick % 20) / 20.0,
                    frameIndex: tick,
                    frames: _frames,
                  ))),
        ),
        const SizedBox(height: 5),
        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center, style: TextStyle(
              fontSize: 10.5,
              color: selected ? Colors.tealAccent : Colors.white70)),
      ])),
    );
  }
}

class _MagicDemoVisual extends StatelessWidget {
  final String id;
  final double progress;
  final int frameIndex;
  final List<Uint8List> frames;

  const _MagicDemoVisual({required this.id, required this.progress,
      required this.frameIndex, required this.frames});

  @override
  Widget build(BuildContext context) {
    final t = progress * math.pi * 2;
    // Each tile receives its own moving image widget. Never share a
    // VideoPlayer texture between several video_player widgets.
    Widget content = frames.isNotEmpty
        ? Image.memory(frames[frameIndex % frames.length],
            fit: BoxFit.cover, width: 80, height: 80,
            gaplessPlayback: true, filterQuality: FilterQuality.low,
            cacheWidth: 160, cacheHeight: 160)
        : DecoratedBox(decoration: const BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF355B63), Color(0xFF122332)])),
          child: Align(alignment: Alignment(math.sin(t) * .7, math.cos(t) * .7),
            child: const Icon(Icons.auto_awesome, color: Colors.tealAccent, size: 29)));
    switch (id) {
      case 'cinematic_zoom':
        content = Transform.scale(scale: 1.03 + .29 * (1 + math.sin(t)) / 2,
            child: content);
        break;
      case 'whip_pan':
        content = Transform.translate(offset: Offset(math.sin(t) * 13, 0),
            child: Transform.scale(scale: 1.28, child: content));
        break;
      case 'impact_shake':
        content = Transform.translate(offset: Offset(math.sin(t * 11) * 4,
            math.sin(t * 13) * 4), child: Transform.scale(scale: 1.12, child: content));
        break;
      case 'motion_echo':
        // Separate coloured trailing copies remain visible above the image.
        content = Stack(fit: StackFit.expand, children: [
          content,
          Opacity(opacity: .46, child: Transform.translate(
            offset: Offset(-9 + 3 * math.sin(t), 0),
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Color(0xFF00D8DB), BlendMode.screen), child: content))),
          Opacity(opacity: .30, child: Transform.translate(
            offset: Offset(9 + 3 * math.sin(t - .7), 0),
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Color(0xFFFF397B), BlendMode.screen), child: content))),
        ]);
        break;
      case 'rgb_glitch':
        content = ColorFiltered(colorFilter: ColorFilter.mode(
            math.sin(t * 3) > 0 ? Colors.red.withOpacity(.30) :
            Colors.blue.withOpacity(.30), BlendMode.screen), child: content);
        break;
      case 'flash_beat':
        content = Stack(fit: StackFit.expand, children: [content,
          ColoredBox(color: Colors.white.withOpacity(
              (.12 * (1 + math.sin(t * 4))).clamp(0.0, .24).toDouble()))]);
        break;
      case 'freeze_focus':
        content = Transform.scale(scale: progress > .35 && progress < .6 ? 1.2 : 1.0,
            child: content);
        break;
      case 'kaleidoscope':
        content = Row(children: [
          Expanded(child: ClipRect(child: Align(alignment: Alignment.centerLeft,
              widthFactor: .5, child: content))),
          Expanded(child: Transform.flip(flipX: true, child: ClipRect(
              child: Align(alignment: Alignment.centerLeft,
                widthFactor: .5, child: content)))),
        ]);
        break;
      case 'dynamic_split':
        content = GridView.count(physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2, padding: EdgeInsets.zero, children: [
            content, Transform.flip(flipX: true, child: content),
            Transform.flip(flipY: true, child: content),
            Transform.flip(flipX: true, flipY: true, child: content)]);
        break;
      case 'vhs_retro':
        content = ColorFiltered(colorFilter: const ColorFilter.mode(
            Color(0x449099A3), BlendMode.srcATop), child: content);
        break;
      case 'light_leak':
        content = Stack(fit: StackFit.expand, children: [content,
          DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
            begin: Alignment(-1 + 2 * progress, -1),
            end: Alignment(1 - 2 * progress, 1),
            colors: const [Color(0x00FF4300), Color(0x99FF8F32), Color(0x00FFB800)])))]);
        break;
      case 'cinema_frame':
        // Match the live preview's visible 14% letterbox and edge lines.
        content = Stack(fit: StackFit.expand, children: [content,
          const Align(alignment: Alignment.topCenter,
              child: FractionallySizedBox(heightFactor: .14,
                  widthFactor: 1, child: ColoredBox(color: Colors.black))),
          const Align(alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(heightFactor: .14,
                  widthFactor: 1, child: ColoredBox(color: Colors.black))),
          Align(alignment: const Alignment(0, -.72),
              child: Container(height: 1.5, color: const Color(0xBBDCE1E6))),
          Align(alignment: const Alignment(0, .72),
              child: Container(height: 1.5, color: const Color(0xBBDCE1E6))),
        ]);
        break;
      case 'neon_frame':
        content = Stack(fit: StackFit.expand, children: [content,
          Container(margin: const EdgeInsets.all(5), decoration: BoxDecoration(
            border: Border.all(width: 2.5, color: Colors.tealAccent
                .withOpacity(.5 + .5 * ((1 + math.sin(t)) / 2))))) ]);
        break;
      case 'film_strip':
        content = Stack(fit: StackFit.expand, children: [content,
          const Align(alignment: Alignment.centerLeft,
            child: SizedBox(width: 9, child: ColoredBox(color: Colors.black))),
          const Align(alignment: Alignment.centerRight,
            child: SizedBox(width: 9, child: ColoredBox(color: Colors.black)))]);
        break;
      case 'floating_frame':
        content = Container(color: const Color(0xFF1A222C), alignment: Alignment.center,
          child: FractionallySizedBox(widthFactor: .78, heightFactor: .78,
            child: Transform.translate(offset: Offset(0, math.sin(t) * 3),
                child: ClipRRect(borderRadius: BorderRadius.circular(5), child: content))));
        break;
    }
    return ClipRect(child: SizedBox.expand(child: content));
  }
}
