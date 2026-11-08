import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'crop_speed_model.dart';

/// Editor-only controls. Speed changes are previewed immediately; the check
/// commits one Undo step, while cancel restores the previous speed.
class CropSpeedPanel extends StatefulWidget {
  final CropSpeed initial;
  final ValueChanged<CropSpeed> onPreview;
  final ValueChanged<CropSpeed> onConfirm;
  final VoidCallback onCancel;

  const CropSpeedPanel({super.key, required this.initial,
    required this.onPreview, required this.onConfirm, required this.onCancel});

  @override
  State<CropSpeedPanel> createState() => _CropSpeedPanelState();
}

class _CropSpeedPanelState extends State<CropSpeedPanel> {
  late CropSpeed _speed;
  bool _editingCurve = false;
  int _draggedIndex = -1;

  @override
  void initState() {
    super.initState();
    _speed = widget.initial;
  }

  void _preview(CropSpeed value) {
    setState(() => _speed = value);
    widget.onPreview(value);
  }

  double _speedSliderValue(double speed) =>
      (1 - (math.log(speed.clamp(.1, 10)) / math.ln10 + 1) / 2).clamp(0.0, 1.0).toDouble();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        color: const Color(0xFF0E161B),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            IconButton(onPressed: widget.onCancel,
                icon: const Icon(Icons.close, color: Colors.white70)),
            const Spacer(),
            if (!_editingCurve) Container(
              decoration: BoxDecoration(color: const Color(0xFF323438),
                  borderRadius: BorderRadius.circular(24)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _modeButton('منحنى', true), _modeButton('عادي', false),
              ]),
            ) else TextButton.icon(
              onPressed: () => setState(() => _editingCurve = false),
              icon: const Icon(Icons.arrow_back, size: 17),
              label: const Text('المنحنيات'),
            ),
            const Spacer(),
            IconButton(onPressed: () => widget.onConfirm(_speed),
                icon: const Icon(Icons.check, color: Colors.white, size: 27)),
          ]),
          if (!_speed.isCurve)
            _normalSlider()
          else if (_editingCurve)
            _curveEditor()
          else
            _curvePresets(),
        ]),
      ),
    );
  }

  Widget _modeButton(String text, bool curve) {
    final active = _speed.isCurve == curve;
    return GestureDetector(
      onTap: () {
        _editingCurve = false;
        _preview(curve ? CropSpeed.preset('none') : const CropSpeed.normal());
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF707174) : Colors.transparent,
          borderRadius: BorderRadius.circular(22)),
        child: Text(text, style: TextStyle(color: Colors.white,
          fontWeight: active ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  Widget _normalSlider() {
    final s = _speed.normal;
    return Column(children: [
      const SizedBox(height: 9),
      Text('${s.toStringAsFixed(1)}x',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
          color: Colors.white)),
      const SizedBox(height: 5),
      SizedBox(height: 18, child: Stack(children: [
        for (final tick in [10.0, 5.0, 2.0, 1.0, .1])
          Align(alignment: Alignment(_speedSliderValue(tick) * 2 - 1, 0),
            child: Text('${tick == .1 ? '0.1' : tick.toStringAsFixed(0)}x',
              style: const TextStyle(color: Colors.white60, fontSize: 11))),
      ])),
      SliderTheme(data: SliderThemeData(
        activeTrackColor: Colors.white54,
        inactiveTrackColor: Colors.white38,
        thumbColor: Colors.white,
        trackHeight: 2,
        overlayColor: Colors.white12,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
      ), child: Slider(
        value: _speedSliderValue(s),
        onChanged: (v) => _preview(CropSpeed.normal(
          math.pow(10, (1 - v) * 2 - 1).toDouble().clamp(.1, 10).toDouble())),
      )),
      const SizedBox(height: 8),
    ]);
  }

  Widget _curvePresets() {
    final presets = <(String, String)>[
      ('none', 'لا شيء'), ('hero', 'حركة'), ('montage', 'مونتاج'),
      ('speedUp', 'تسريع'), ('slowDown', 'تباطؤ'), ('custom', 'مخصصة'),
    ];
    return Column(children: [
      const SizedBox(height: 6),
      SizedBox(height: 108, child: ListView.separated(
        scrollDirection: Axis.horizontal, itemCount: presets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 9),
        itemBuilder: (context, i) {
          final p = presets[i];
          final curve = CropSpeed.preset(p.$1);
          return InkWell(
            onTap: () {
              _preview(curve);
              if (p.$1 == 'custom') setState(() => _editingCurve = true);
            },
            child: Column(children: [
              Container(width: 72, height: 70,
                decoration: BoxDecoration(color: const Color(0xFF30343C),
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.all(9),
                child: CustomPaint(painter: _SpeedCurvePainter(curve))),
              const SizedBox(height: 6),
              Text(p.$2, style: const TextStyle(fontSize: 11, color: Colors.white)),
            ]),
          );
        },
      )),
      TextButton.icon(
        onPressed: () => setState(() => _editingCurve = true),
        icon: const Icon(Icons.edit, size: 16),
        label: const Text('تعديل المنحنى'),
      ),
    ]);
  }

  Widget _curveEditor() {
    return Column(children: [
      SizedBox(height: math.min(158.0, MediaQuery.of(context).size.height * 0.15), child: LayoutBuilder(builder: (context, layout) {
        final width = layout.maxWidth, height = layout.maxHeight;
        final points = _speed.points;
        void move(Offset at) {
          if (_draggedIndex < 0 || _draggedIndex >= points.length) return;
          final t = (at.dx / width).clamp(0.0, 1.0);
          final y = (at.dy / height).clamp(0.0, 1.0);
          final speed = math.pow(10, (1 - y) * 2 - 1).toDouble().clamp(.1, 10).toDouble();
          final left = _draggedIndex == 0 ? 0.0 : points[_draggedIndex - 1].at + .025;
          final right = _draggedIndex == points.length - 1 ? 1.0 : points[_draggedIndex + 1].at - .025;
          final updated = [...points];
          updated[_draggedIndex] = CropSpeedPoint(
            _draggedIndex == 0 ? 0.0 : _draggedIndex == points.length - 1 ? 1.0 : t.clamp(left, right).toDouble(), speed);
          _preview(CropSpeed.curve(updated));
        }
        return GestureDetector(behavior: HitTestBehavior.opaque,
          onPanStart: (details) {
            final offset = details.localPosition;
            var nearest = 0;
            var distance = double.infinity;
            for (var i = 0; i < points.length; i++) {
              final p = points[i];
              final px = p.at * width;
              final py = (1 - (math.log(p.speed) / math.ln10 + 1) / 2) * height;
              final d = (Offset(px, py) - offset).distance;
              if (d < distance) { nearest = i; distance = d; }
            }
            _draggedIndex = distance < 35 ? nearest : -1;
          },
          onPanUpdate: (details) => move(details.localPosition),
          onPanEnd: (_) => _draggedIndex = -1,
          child: CustomPaint(size: Size(width, height),
              painter: _SpeedCurvePainter(_speed, detailed: true)),
        );
      })),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        TextButton.icon(onPressed: () {
          final nodes = _speed.points;
          if (nodes.length >= 12) return;
          var at = .5, gap = 0.0;
          for (var i = 1; i < nodes.length; i++) {
            final g = nodes[i].at - nodes[i - 1].at;
            if (g > gap) { gap = g; at = (nodes[i].at + nodes[i - 1].at) / 2; }
          }
          _preview(CropSpeed.curve([...nodes, CropSpeedPoint(at, _speed.speedAt(at))]));
        }, icon: const Icon(Icons.add, size: 17), label: const Text('إضافة نقطة')),
        TextButton.icon(onPressed: () {
          if (_speed.points.length > 2) {
            final nodes = [..._speed.points];
            nodes.removeAt(nodes.length ~/ 2);
            _preview(CropSpeed.curve(nodes));
          }
        }, icon: const Icon(Icons.remove_circle_outline, size: 17), label: const Text('حذف نقطة')),
        TextButton.icon(onPressed: () => _preview(CropSpeed.preset('none')),
          icon: const Icon(Icons.restart_alt, size: 17), label: const Text('إعادة تعيين')),
      ]),
    ]);
  }
}

class _SpeedCurvePainter extends CustomPainter {
  final CropSpeed speed;
  final bool detailed;
  _SpeedCurvePainter(this.speed, {this.detailed = false});
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = Colors.white24..strokeWidth = 1;
    if (detailed) {
      for (final y in [.0, .5, 1.0]) {
        canvas.drawLine(Offset(0, y * size.height),
            Offset(size.width, y * size.height), grid);
      }
    }
    final curve = Path();
    for (var i = 0; i <= 80; i++) {
      final t = i / 80.0;
      final rate = speed.speedAt(t);
      final y = (1 - (math.log(rate) / math.ln10 + 1) / 2).clamp(0.0, 1.0).toDouble();
      final point = Offset(t * size.width, y * size.height);
      if (i == 0) { curve.moveTo(point.dx, point.dy); }
      else { curve.lineTo(point.dx, point.dy); }
    }
    canvas.drawPath(curve, Paint()..color = const Color(0xFFFF3B30)
      ..strokeWidth = detailed ? 2.8 : 2
      ..style = PaintingStyle.stroke);
    if (detailed) {
      for (final p in speed.points) {
        final y = 1 - (math.log(p.speed) / math.ln10 + 1) / 2;
        canvas.drawCircle(Offset(p.at * size.width, y * size.height), 6,
          Paint()..color = Colors.white);
      }
    }
  }
  @override
  bool shouldRepaint(covariant _SpeedCurvePainter old) => true;
}
