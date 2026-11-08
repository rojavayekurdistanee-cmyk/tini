import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'crop_animation_model.dart';
import 'crop_animation_preview.dart';

/// The three-tab animation editor follows the provided TikTok reference:
/// RTL tabs, checkmark on the left, a rightmost "none" tile, white selection
/// frame, horizontally scrolling effect samples and a duration slider.
class CropAnimationPanel extends StatefulWidget {
  final CropAnimationSettings initial;
  final Duration clipDuration;
  final List<Uint8List> previewFrames;
  final ValueChanged<CropAnimationSettings> onPreview;
  final ValueChanged<CropAnimationSettings> onConfirm;
  final VoidCallback onCancel;

  const CropAnimationPanel({super.key, required this.initial,
    required this.clipDuration, required this.previewFrames,
    required this.onPreview, required this.onConfirm, required this.onCancel});

  @override
  State<CropAnimationPanel> createState() => _CropAnimationPanelState();
}

class _CropAnimationPanelState extends State<CropAnimationPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _samples;
  late CropAnimationSettings _current;
  CropAnimationTab _tab = CropAnimationTab.start;

  @override
  void initState() {
    super.initState();
    _current = widget.initial;
    _samples = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1500))..repeat();
  }

  @override
  void didUpdateWidget(covariant CropAnimationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Timeline resize gestures modify the selected preset's duration externally.
    if (widget.initial != oldWidget.initial && widget.initial != _current) {
      _current = widget.initial;
    }
  }

  @override
  void dispose() {
    _samples.dispose();
    super.dispose();
  }

  void _choose(String? id) {
    final next = _current.withEffect(_tab, id);
    setState(() => _current = next);
    widget.onPreview(next);
  }

  void _changeDuration(double seconds) {
    final next = _current.withSeconds(_tab, seconds);
    setState(() => _current = next);
    widget.onPreview(next);
  }

  @override
  Widget build(BuildContext context) {
    final safeArea = MediaQuery.of(context).padding.bottom;
    final hasChoice = _current.effect(_tab) != null;
    final lower = _tab == CropAnimationTab.group ? .2 : .1;
    // Timeline handles may stretch an animation beyond five seconds.
    // The duration slider must show the same committed value.
    final limit = (widget.clipDuration.inMilliseconds / 1000.0)
        .clamp(lower, double.infinity).toDouble();
    final currentDuration = _current.seconds(_tab).clamp(lower, limit).toDouble();
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxHeight < 300;
      final content = Column(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: [

        SizedBox(height: compact ? 48 : 54, child: Row(children: [
          IconButton(onPressed: () => widget.onConfirm(_current),
            icon: const Icon(Icons.check, size: 30, color: Colors.white)),
          const Spacer(),
          Directionality(textDirection: TextDirection.rtl,
            child: Row(children: [
              _tabButton(CropAnimationTab.start, 'بداية'),
              _tabButton(CropAnimationTab.end, 'نهاية'),
              _tabButton(CropAnimationTab.group, 'مجموعة'),
            ])),
          const SizedBox(width: 6),
        ])),
        const Divider(height: 1, thickness: 1, color: Color(0xFF393939)),
        SizedBox(height: compact ? 6 : 18),
        SizedBox(height: compact ? 108 : 126,
          child: Directionality(textDirection: TextDirection.rtl,
            child: ListView(scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                _tile(null, 'لا شيء'),
                for (final effect in CropAnimationCatalog.forTab(_tab))
                  _tile(effect.id, effect.title),
              ]))),
        if (!compact) const Spacer(),
        if (hasChoice)
          Padding(padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: Row(textDirection: TextDirection.ltr, children: [
              Expanded(child: SliderTheme(data: SliderThemeData(
                trackHeight: 3,
                activeTrackColor: Colors.white54,
                inactiveTrackColor: const Color(0xFF494949),
                thumbColor: Colors.white,
                overlayColor: Colors.white12,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
              ), child: Slider(value: currentDuration,
                  min: lower, max: limit <= lower ? lower + .00001 : limit,
                  onChanged: (v) => _changeDuration(v.clamp(lower, limit).toDouble())))),
              const SizedBox(width: 8),
              Text('${currentDuration.toStringAsFixed(1)} ث',
                style: const TextStyle(color: Colors.white, fontSize: 14)),
            ])),
      ]);
      return Container(
        color: const Color(0xFF1B1B1B),
        padding: EdgeInsets.only(bottom: safeArea),
        child: compact ? SingleChildScrollView(child: content) : content,
      );
    });
  }

  Widget _tabButton(CropAnimationTab tab, String title) {
    final selected = _tab == tab;
    return InkWell(
      onTap: () => setState(() => _tab = tab),
      child: Container(
        width: ((MediaQuery.of(context).size.width - 82) / 3)
            .clamp(54.0, 79.0).toDouble(),
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(border: Border(bottom: BorderSide(
          color: selected ? Colors.white : Colors.transparent,
          width: selected ? 3 : 0))),
        child: Text(title, style: TextStyle(fontSize: 16,
          color: selected ? Colors.white : Colors.white60,
          fontWeight: selected ? FontWeight.bold : FontWeight.w500))),
    );
  }

  Widget _tile(String? id, String title) {
    final selected = _current.effect(_tab) == id;
    return GestureDetector(onTap: () => _choose(id),
      child: SizedBox(width: 84, child: Column(children: [
        Container(height: 74, width: 74,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: selected ? Colors.white : Colors.transparent,
              width: 2.5)),
          child: ClipRRect(borderRadius: BorderRadius.circular(14),
            child: ColoredBox(color: const Color(0xFF313131),
              child: id == null
                ? const Icon(Icons.block, size: 34, color: Colors.white70)
                : AnimatedBuilder(animation: _samples, builder: (context, _) {
                    final still = widget.previewFrames.isNotEmpty
                        ? Image.memory(widget.previewFrames.first,
                            gaplessPlayback: true, fit: BoxFit.cover,
                            width: 70, height: 70, cacheWidth: 160)
                        : const Center(child: Icon(Icons.movie_creation_outlined,
                            color: Colors.white70, size: 32));
                    return CropAnimationPreview.animationVisual(
                      id, _samples.value, still);
                  }))),
        ),
        const SizedBox(height: 7),
        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(color: selected ? Colors.white : Colors.white60,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 12)),
      ])),
    );
  }
}
