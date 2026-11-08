import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'crop_effects_catalog.dart';
import 'crop_effects_model.dart';
import 'crop_intro_effects_preview.dart';
import 'crop_basic_effects_preview.dart';
import 'crop_vibe_effects_painter.dart';
import 'crop_dynamic_effects_preview.dart';
import 'crop_lighting_effects_preview.dart';
import 'crop_amazing_next8_preview.dart';
import 'crop_amazing_ten_preview.dart';
import 'crop_amazing_effects_preview.dart';
import 'crop_glitch_effects_preview.dart';
import 'crop_distortion_effects_preview.dart';
import 'crop_classic_effects_preview.dart';
import 'crop_screen_effects_preview.dart';
import 'crop_nature_effects_preview.dart';
import 'crop_texture_effects_preview.dart';
import 'crop_effects_preview.dart';

/// Independent Effects picker. It never writes a source file; parent owns
/// transaction, Undo/Redo and final export. Unsupported reference effects stay
/// visible but cannot silently substitute another effect.
class TiniEffectsPanel extends StatefulWidget {
  final List<TiniAppliedEffect> initial;
  final Duration clipDuration;
  final double playheadSeconds;
  final List<Uint8List> thumbnails;
  final ValueChanged<List<TiniAppliedEffect>> onPreview;
  final ValueChanged<List<TiniAppliedEffect>> onConfirm;
  final VoidCallback onCancel;

  const TiniEffectsPanel({super.key, required this.initial,
    required this.clipDuration, required this.playheadSeconds,
    required this.thumbnails, required this.onPreview,
    required this.onConfirm, required this.onCancel});

  @override
  State<TiniEffectsPanel> createState() => _TiniEffectsPanelState();
}

class _TiniEffectsPanelState extends State<TiniEffectsPanel>
    with SingleTickerProviderStateMixin {
  late List<TiniAppliedEffect> _effects;
  int _tab = 0;
  String _query = '';
  int? _selectedIndex;
  final _scroll = ScrollController();
  late final AnimationController _dynamicClock;

  @override
  void initState() {
    super.initState();
    _dynamicClock = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2000),
    )..repeat();
    _effects = List.of(widget.initial);
    if (_effects.isNotEmpty) _selectedIndex = _effects.length - 1;
  }

  @override
  void dispose() {
    _dynamicClock.dispose();
    _scroll.dispose();
    super.dispose();
  }

  double get _total => math.max(0.1, widget.clipDuration.inMicroseconds / 1000000.0);

  void _notify() => widget.onPreview(List.unmodifiable(_effects));

  void _add(TiniEffectDescriptor descriptor) {
    if (!descriptor.available) return;
    final start = widget.playheadSeconds.clamp(0.0, math.max(0.0, _total - .1)).toDouble();
    final end = math.min(_total, start + 2.0);
    setState(() {
      _effects.add(TiniAppliedEffect(id: descriptor.id,
          startSeconds: start, endSeconds: end));
      _selectedIndex = _effects.length - 1;
    });
    _notify();
  }

  void _deleteSelected() {
    final index = _selectedIndex;
    if (index == null || index >= _effects.length) return;
    setState(() {
      _effects.removeAt(index);
      _selectedIndex = _effects.isEmpty ? null : _effects.length - 1;
    });
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedIndex == null || _selectedIndex! >= _effects.length
        ? null : _effects[_selectedIndex!];
    final group = TiniEffectsCatalog.categories[_tab];
    final filtered = _query.trim().isEmpty
        ? TiniEffectsCatalog.itemsFor(group.name)
        : [for (final cat in TiniEffectsCatalog.categories)
            ...TiniEffectsCatalog.itemsFor(cat.name).where((e) =>
                e.name.toLowerCase().contains(_query.toLowerCase()) ||
                e.category.contains(_query))];

    return Container(
      color: const Color(0xFF1A1A1A),
      child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(10, 4, 10, 8), child: Row(children: [
          IconButton(tooltip: 'تأكيد', onPressed: () => widget.onConfirm(List.unmodifiable(_effects)),
            icon: const Icon(Icons.check, color: Colors.white, size: 27)),
          Expanded(child: SizedBox(height: 39, child: TextField(
            style: const TextStyle(color: Colors.white, fontSize: 13),
            textDirection: TextDirection.rtl,
            onChanged: (s) => setState(() => _query = s),
            decoration: InputDecoration(
              hintText: 'البحث عن مؤثرات', hintStyle: const TextStyle(color: Colors.white54),
              suffixIcon: const Icon(Icons.search, color: Colors.white54, size: 19),
              filled: true, fillColor: const Color(0xFF393939),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(7),
                  borderSide: BorderSide.none),
            ),
          ))),
          IconButton(tooltip: 'إلغاء', onPressed: widget.onCancel,
            icon: const Icon(Icons.close, color: Colors.white70)),
        ])),
        if (_query.isEmpty)
          SizedBox(height: 46, child: ListView.builder(
            controller: _scroll, scrollDirection: Axis.horizontal, reverse: true,
            itemCount: TiniEffectsCatalog.categories.length,
            itemBuilder: (context, index) => InkWell(
              onTap: () => setState(() => _tab = index),
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 13),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text(TiniEffectsCatalog.categories[index].name,
                      style: TextStyle(color: index == _tab ? Colors.white : Colors.white60,
                          fontWeight: index == _tab ? FontWeight.w600 : FontWeight.normal,
                          fontSize: 13)),
                  const SizedBox(height: 10),
                  Container(height: 2, width: 40,
                    color: index == _tab ? Colors.white : Colors.transparent),
                ])),
            ),
          )),
        const Divider(color: Color(0xFF343434), height: 1),
        if (selected != null) ...[
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(children: [
              IconButton(tooltip: 'إزالة المؤثر المحدد', onPressed: _deleteSelected,
                icon: const Icon(Icons.delete_outline, color: Color(0xFFE53935), size: 22)),
              Expanded(child: Text(selected.descriptor?.name ?? '',
                textAlign: TextAlign.center, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 12))),
              Text('${(selected.endSeconds - selected.startSeconds).toStringAsFixed(1)}s',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ])),
          RangeSlider(
            min: 0, max: _total,
            values: RangeValues(selected.startSeconds.clamp(0.0, _total).toDouble(),
                selected.endSeconds.clamp(0.0, _total).toDouble()),
            activeColor: selected.descriptor?.color ?? Colors.teal,
            inactiveColor: Colors.white24,
            onChanged: (range) {
              if (range.end - range.start < .10) return;
              setState(() => _effects[_selectedIndex!] = selected.copyWith(
                  startSeconds: range.start, endSeconds: range.end));
              _notify();
            },
          ),
        ],
        Expanded(child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 14),
          itemCount: filtered.length + 1,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4, crossAxisSpacing: 10, mainAxisSpacing: 14,
            childAspectRatio: .78),
          itemBuilder: (context, i) {
            if (i == 0) {
              return _tile('لا شيء', null, selected == null,
                onTap: _deleteSelected, icon: Icons.block);
            }
            final effect = filtered[i - 1];
            final isSelected = selected?.id == effect.id;
            return _tile(effect.name, effect, isSelected,
                onTap: effect.available ? () => _add(effect) : null);
          },
        )),
      ]),
    );
  }

  Widget _tile(String title, TiniEffectDescriptor? descriptor,
      bool selected, {required VoidCallback? onTap, IconData? icon}) {
    final enabled = onTap != null;
    final color = descriptor?.color ?? const Color(0xFF383838);
    return InkWell(onTap: onTap, child: Column(children: [
      Expanded(child: Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10),
          color: const Color(0xFF303030),
          border: Border.all(color: selected ? Colors.white : Colors.transparent,
              width: selected ? 2.5 : 0)),
        clipBehavior: Clip.antiAlias,
        child: Stack(fit: StackFit.expand, children: [
          if (widget.thumbnails.isNotEmpty && descriptor != null)
            Opacity(opacity: enabled ? 1 : .33,
              child: descriptor.category == 'مقدمة وخاتمة'
                // Show the effect itself on the source clip's thumbnail,
                // instead of a generic coloured tile for every effect.
                ? TiniIntroEffectsPreview.apply(
                    name: descriptor.name, id: descriptor.id,
                    elapsed: .62, start: 0, end: 1,
                    child: Image.memory(widget.thumbnails.first,
                      fit: BoxFit.cover, gaplessPlayback: true))
                : descriptor.category == 'أساسية'
                ? TiniBasicEffectsPreview.apply(name: descriptor.name,
                    elapsed: .62, start: 0, end: 1,
                    child: Image.memory(widget.thumbnails.first,
                      fit: BoxFit.cover, gaplessPlayback: true))
                : descriptor.category == TiniDynamicEffectsPreview.category && enabled
                ? (selected
                    // Animate only the selected tile: 35 simultaneous animated
                    // thumbnails would force 35 image layers per video frame.
                    ? AnimatedBuilder(animation: _dynamicClock,
                        builder: (context, _) => TiniDynamicEffectsPreview.apply(
                          name: descriptor.name,
                          elapsed: _dynamicClock.value * 2, start: 0, end: 2,
                          child: Image.memory(widget.thumbnails.first,
                            fit: BoxFit.cover, gaplessPlayback: true)))
                    : TiniDynamicEffectsPreview.apply(
                        name: descriptor.name,
                        elapsed: TiniDynamicEffectsPreview.thumbnailSeconds(
                            descriptor.name), start: 0, end: 2,
                        child: Image.memory(widget.thumbnails.first,
                          fit: BoxFit.cover, gaplessPlayback: true)))
                : descriptor.category == TiniLightingEffectsPreview.category && enabled
                ? (selected
                    ? AnimatedBuilder(animation: _dynamicClock,
                        builder: (context, _) => TiniLightingEffectsPreview.apply(
                          name: descriptor.name,
                          elapsed: _dynamicClock.value * 2, start: 0, end: 2,
                          child: Image.memory(widget.thumbnails.first,
                            fit: BoxFit.cover, gaplessPlayback: true)))
                    : TiniLightingEffectsPreview.apply(
                        name: descriptor.name,
                        elapsed: TiniLightingEffectsPreview.thumbnailSeconds(
                            descriptor.name), start: 0, end: 2,
                        child: Image.memory(widget.thumbnails.first,
                          fit: BoxFit.cover, gaplessPlayback: true)))
                : descriptor.category == TiniAmazingEffectsPreview.category &&
                    TiniAmazingEffectsPreview.supported.contains(descriptor.name) && enabled
                ? (selected
                    ? AnimatedBuilder(animation: _dynamicClock,
                        builder: (context, _) => TiniAmazingEffectsPreview.apply(
                          name: descriptor.name,
                          elapsed: _dynamicClock.value * 2, start: 0, end: 2,
                          child: Image.memory(widget.thumbnails.first,
                            fit: BoxFit.cover, gaplessPlayback: true)))
                    : TiniAmazingEffectsPreview.apply(
                        name: descriptor.name,
                        elapsed: TiniAmazingEffectsPreview.thumbnailSeconds(
                            descriptor.name), start: 0, end: 2,
                        child: Image.memory(widget.thumbnails.first,
                          fit: BoxFit.cover, gaplessPlayback: true)))
                : descriptor.category == TiniAmazingNextEightPreview.category &&
                    TiniAmazingNextEightPreview.supported.contains(descriptor.name) && enabled
                ? (selected
                    ? AnimatedBuilder(animation: _dynamicClock,
                        builder: (context, _) => TiniAmazingNextEightPreview.apply(
                          name: descriptor.name,
                          elapsed: _dynamicClock.value * 2, start: 0, end: 2,
                          child: Image.memory(widget.thumbnails.first,
                            fit: BoxFit.cover, gaplessPlayback: true)))
                    : TiniAmazingNextEightPreview.apply(
                        name: descriptor.name,
                        elapsed: TiniAmazingNextEightPreview.thumbnailSeconds(
                            descriptor.name), start: 0, end: 2,
                        child: Image.memory(widget.thumbnails.first,
                          fit: BoxFit.cover, gaplessPlayback: true)))
                : descriptor.category == TiniAmazingTenPreview.category &&
                    TiniAmazingTenPreview.supported.contains(descriptor.name) && enabled
                ? (selected
                    ? AnimatedBuilder(animation: _dynamicClock,
                        builder: (context, _) => TiniAmazingTenPreview.apply(
                          name: descriptor.name,
                          elapsed: _dynamicClock.value * 2, start: 0, end: 2,
                          child: Image.memory(widget.thumbnails.first,
                            fit: BoxFit.cover, gaplessPlayback: true)))
                    : TiniAmazingTenPreview.apply(
                        name: descriptor.name,
                        elapsed: TiniAmazingTenPreview.thumbnailSeconds(
                            descriptor.name), start: 0, end: 2,
                        child: Image.memory(widget.thumbnails.first,
                          fit: BoxFit.cover, gaplessPlayback: true)))
                : descriptor.category == TiniGlitchEffectsPreview.category && enabled
                ? (selected
                    ? AnimatedBuilder(animation: _dynamicClock,
                        builder: (context, _) => TiniGlitchEffectsPreview.apply(
                          name: descriptor.name,
                          elapsed: _dynamicClock.value * 2, start: 0, end: 2,
                          child: Image.memory(widget.thumbnails.first,
                            fit: BoxFit.cover, gaplessPlayback: true)))
                    : TiniGlitchEffectsPreview.apply(
                        name: descriptor.name,
                        elapsed: TiniGlitchEffectsPreview.thumbnailSeconds(
                            descriptor.name), start: 0, end: 2,
                        child: Image.memory(widget.thumbnails.first,
                          fit: BoxFit.cover, gaplessPlayback: true)))
                : descriptor.category == TiniDistortionEffectsPreview.category && enabled
                ? (selected
                    ? AnimatedBuilder(animation: _dynamicClock,
                        builder: (context, _) => TiniDistortionEffectsPreview.apply(
                          name: descriptor.name,
                          elapsed: _dynamicClock.value * 2, start: 0, end: 2,
                          child: Image.memory(widget.thumbnails.first,
                            fit: BoxFit.cover, gaplessPlayback: true)))
                    : TiniDistortionEffectsPreview.apply(
                        name: descriptor.name,
                        elapsed: TiniDistortionEffectsPreview.thumbnailSeconds(
                            descriptor.name), start: 0, end: 2,
                        child: Image.memory(widget.thumbnails.first,
                          fit: BoxFit.cover, gaplessPlayback: true)))
                : descriptor.category == TiniClassicEffectsPreview.category && enabled
                ? (selected
                    ? AnimatedBuilder(animation: _dynamicClock,
                        builder: (context, _) => TiniClassicEffectsPreview.apply(
                          name: descriptor.name,
                          elapsed: _dynamicClock.value * 2, start: 0, end: 2,
                          child: Image.memory(widget.thumbnails.first,
                            fit: BoxFit.cover, gaplessPlayback: true)))
                    : TiniClassicEffectsPreview.apply(
                        name: descriptor.name,
                        elapsed: TiniClassicEffectsPreview.thumbnailSeconds(
                            descriptor.name), start: 0, end: 2,
                        child: Image.memory(widget.thumbnails.first,
                          fit: BoxFit.cover, gaplessPlayback: true)))
                : descriptor.category == TiniScreenEffectsPreview.category && enabled
                ? (selected
                    ? AnimatedBuilder(animation: _dynamicClock,
                        builder: (context, _) => TiniScreenEffectsPreview.apply(
                          name: descriptor.name,
                          elapsed: _dynamicClock.value * 2, start: 0, end: 2,
                          child: Image.memory(widget.thumbnails.first,
                            fit: BoxFit.cover, gaplessPlayback: true)))
                    : TiniScreenEffectsPreview.apply(
                        name: descriptor.name,
                        elapsed: TiniScreenEffectsPreview.thumbnailSeconds(
                            descriptor.name), start: 0, end: 2,
                        child: Image.memory(widget.thumbnails.first,
                          fit: BoxFit.cover, gaplessPlayback: true)))
                : descriptor.category == TiniNatureEffectsPreview.category && enabled
                ? (selected
                    ? AnimatedBuilder(animation: _dynamicClock,
                        builder: (context, _) => TiniNatureEffectsPreview.apply(
                          name: descriptor.name,
                          elapsed: _dynamicClock.value * 2, start: 0, end: 2,
                          child: Image.memory(widget.thumbnails.first,
                            fit: BoxFit.cover, gaplessPlayback: true)))
                    : TiniNatureEffectsPreview.apply(
                        name: descriptor.name,
                        elapsed: TiniNatureEffectsPreview.thumbnailSeconds(
                            descriptor.name), start: 0, end: 2,
                        child: Image.memory(widget.thumbnails.first,
                          fit: BoxFit.cover, gaplessPlayback: true)))
                : descriptor.category == TiniTextureEffectsPreview.category && enabled
                ? (selected
                    ? AnimatedBuilder(animation: _dynamicClock,
                        builder: (context, _) => TiniTextureEffectsPreview.apply(
                          name: descriptor.name,
                          elapsed: _dynamicClock.value * 2, start: 0, end: 2,
                          child: Image.memory(widget.thumbnails.first,
                            fit: BoxFit.cover, gaplessPlayback: true)))
                    : TiniTextureEffectsPreview.apply(
                        name: descriptor.name,
                        elapsed: TiniTextureEffectsPreview.thumbnailSeconds(
                            descriptor.name), start: 0, end: 2,
                        child: Image.memory(widget.thumbnails.first,
                          fit: BoxFit.cover, gaplessPlayback: true)))
                : descriptor.category == 'انقسام الشاشة' && enabled
                ? TiniEffectsPreview(
                    effects: [TiniAppliedEffect(id: descriptor.id,
                      startSeconds: 0, endSeconds: 2)],
                    elapsedSeconds: .65,
                    child: Image.memory(widget.thumbnails.first,
                      fit: BoxFit.cover, gaplessPlayback: true))
                : descriptor.category == TiniVibeEffectsPainter.category && enabled
                ? CustomPaint(
                    foregroundPainter: TiniVibeEffectsPainter(
                      effects: [TiniAppliedEffect(id: descriptor.id,
                        startSeconds: 0, endSeconds: 2)], seconds: .65),
                    child: Image.memory(widget.thumbnails.first,
                        fit: BoxFit.cover, gaplessPlayback: true))
                : Image.memory(widget.thumbnails.first, fit: BoxFit.cover,
                    gaplessPlayback: true))
          else Container(color: const Color(0xFF303030)),
          if (!{'مقدمة وخاتمة', 'أساسية', 'Vibe', 'ديناميكية', 'إضاءة', 'مذهلة', 'خلل', 'تشويه', 'كلاسيكية', 'شاشة', 'الطبيعة', 'ملمس', 'انقسام الشاشة'}.contains(descriptor?.category) ||
              widget.thumbnails.isEmpty ||
              (descriptor?.category == TiniAmazingEffectsPreview.category &&
               !TiniAmazingEffectsPreview.supported.contains(descriptor?.name) &&
               !TiniAmazingNextEightPreview.supported.contains(descriptor?.name) &&
               !TiniAmazingTenPreview.supported.contains(descriptor?.name))) ...[
            if (descriptor != null) Container(
              color: color.withValues(alpha: enabled ? .25 : .07)),
            Center(child: Icon(icon ?? (enabled ? Icons.auto_awesome : Icons.lock_outline),
                color: enabled ? Colors.white : Colors.white38, size: 27)),
          ],
        ]),
      )),
      const SizedBox(height: 6),
      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center, textDirection: TextDirection.ltr,
        style: TextStyle(fontSize: 11,
          color: enabled ? Colors.white : Colors.white38)),
    ]));
  }
}
