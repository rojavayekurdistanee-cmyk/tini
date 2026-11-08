import 'dart:math' as math;

import 'package:image/image.dart' as img;

import 'crop_retouch_model.dart';

/// CPU reference implementation shared by still preview and every export frame.
/// Only detector-localized, skin-coloured face pixels and visible teeth change.
class CropRetouchPixels {
  static bool inside(double x, double y, List<math.Point<double>> polygon) {
    if (polygon.length < 3) return false;
    var hit = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i], b = polygon[j];
      if ((a.y > y) != (b.y > y) &&
          x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x) {
        hit = !hit;
      }
    }
    return hit;
  }

  static List<double> _intersections(
    double y,
    List<math.Point<double>> polygon,
  ) {
    if (polygon.length < 3) return const [];
    final crossings = <double>[];
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i], b = polygon[j];
      if ((a.y > y) != (b.y > y)) {
        crossings.add((b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x);
      }
    }
    return crossings;
  }

  static bool _insideRow(double x, List<double> crossings) {
    var hit = false;
    for (final boundary in crossings) {
      if (x < boundary) hit = !hit;
    }
    return hit;
  }

  static double _ramp(double value, double low, double high) {
    final t = ((value - low) / (high - low)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  static double _distance(
    double x,
    double y,
    List<math.Point<double>> polygon,
  ) {
    var best = double.infinity;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[j], b = polygon[i];
      final dx = b.x - a.x, dy = b.y - a.y;
      final norm = dx * dx + dy * dy;
      final t = norm == 0 ? 0.0 : ((x - a.x) * dx + (y - a.y) * dy) / norm;
      final px = a.x + dx * t.clamp(0.0, 1.0);
      final py = a.y + dy * t.clamp(0.0, 1.0);
      best = math.min(
        best,
        math.sqrt((x - px) * (x - px) + (y - py) * (y - py)),
      );
    }
    return best;
  }

  static double _skin(num r, num g, num b) {
    final cb = 128 - .168736 * r - .331264 * g + .5 * b;
    final cr = 128 + .5 * r - .418688 * g - .081312 * b;
    // Broad chroma bounds include darker skin; luminance is never lifted.
    return _ramp(cb, 70, 88) *
        (1 - _ramp(cb, 135, 150)) *
        _ramp(cr, 120, 135) *
        (1 - _ramp(cr, 178, 195));
  }

  static int apply(
    img.Image image,
    List<CropRetouchFace> faces,
    CropRetouchSettings settings,
  ) {
    if (!settings.enabled || faces.isEmpty) return 0;
    // Whitening reads only its current source pixel; avoid a full-frame copy
    // unless smoothing also needs neighbouring original pixels.
    final original = settings.smooth > 0 ? img.Image.from(image) : image;
    var changed = 0;
    for (final face in faces) {
      if (face.width < 8 ||
          face.height < 8 ||
          !face.width.isFinite ||
          !face.height.isFinite ||
          !face.left.isFinite ||
          !face.top.isFinite) {
        continue;
      }
      final x0 = face.left.floor().clamp(0, image.width - 1);
      final y0 = face.top.floor().clamp(0, image.height - 1);
      final x1 = (face.left + face.width).ceil().clamp(0, image.width);
      final y1 = (face.top + face.height).ceil().clamp(0, image.height);
      if (x1 <= x0 || y1 <= y0) continue;
      // Teeth-only mode avoids allocating or blurring a face crop altogether.
      // For large faces, blur at half resolution and scale the result back:
      // the effective blur radius stays close to the source-pixel value while
      // the expensive Gaussian processes about one quarter as many pixels.
      img.Image? blurred;
      if (settings.smooth > 0) {
        final crop = img.copyCrop(
          original,
          x: x0,
          y: y0,
          width: x1 - x0,
          height: y1 - y0,
        );
        final radius = (face.width * .035).round().clamp(3, 24);
        if (crop.width >= 256 && crop.height >= 256 && radius >= 8) {
          final small = img.copyResize(
            crop,
            width: (crop.width + 1) ~/ 2,
            height: (crop.height + 1) ~/ 2,
            interpolation: img.Interpolation.linear,
          );
          final smoothSmall = img.gaussianBlur(
            small,
            radius: (radius / 2).round().clamp(2, 12),
          );
          blurred = img.copyResize(
            smoothSmall,
            width: crop.width,
            height: crop.height,
            interpolation: img.Interpolation.linear,
          );
        } else {
          blurred = img.gaussianBlur(crop, radius: radius);
        }
      }
      final feather = math.max(1.0, face.width * .025);
      final leftEye = _RetouchEyeMask(face.leftEye, feather);
      final rightEye = _RetouchEyeMask(face.rightEye, feather);
      for (var y = y0; y < y1; y++) {
        // Scan conversion avoids re-testing every contour edge at every pixel.
        final outlineRow = _intersections(y + .5, face.outline);
        final mouthRow = settings.teeth > 0
            ? _intersections(y + .5, face.mouth)
            : const <double>[];
        for (var x = x0; x < x1; x++) {
          final source = original.getPixel(x, y);
          if (source.a == 0) continue;
          final r = source.r.toDouble(),
              g = source.g.toDouble(),
              b = source.b.toDouble();
          var nr = r, ng = g, nb = b;
          final fx = (x - face.left) / face.width,
              fy = (y - face.top) / face.height;
          final dx = (fx - .5) / .47;
          final dy = (fy - .52) / .49;
          final ellipse = dx * dx + dy * dy;
          final inMouth = settings.teeth > 0 && _insideRow(x + .5, mouthRow);
          if (blurred != null &&
              ellipse < 1 &&
              (face.outline.isEmpty || _insideRow(x + .5, outlineRow))) {
            // Preserve eyes, eyebrows, nose creases and the complete lip area.
            final eyeZone = fy > .22 && fy < .48;
            final noseZone = (fx - .5).abs() < .11 && fy > .36 && fy < .7;
            final lipsZone = fy > .66 && fy < .9 && (fx - .5).abs() < .32;
            if (!eyeZone &&
                !noseZone &&
                !lipsZone &&
                !leftEye.contains(x + .5, y + .5) &&
                !rightEye.contains(x + .5, y + .5)) {
              final soft = blurred.getPixel(x - x0, y - y0);
              final delta =
                  ((r - soft.r).abs() +
                      (g - soft.g).abs() +
                      (b - soft.b).abs()) /
                  3;
              // High-frequency edges get less smoothing than small blemishes.
              final edge = math.exp(-delta * delta / (2 * 36 * 36));
              final border = (1 - ellipse).clamp(0.0, 1.0).toDouble();
              final weight =
                  settings.smooth.clamp(0.0, 1.0) *
                  .9 *
                  _skin(r, g, b) *
                  _ramp(border, 0, .18) *
                  edge;
              nr += (soft.r - r) * weight;
              ng += (soft.g - g) * weight;
              nb += (soft.b - b) * weight;
            }
          }
          if (settings.teeth > 0 && inMouth && face.mouth.length >= 6) {
            final maxC = math.max(r, math.max(g, b)),
                minC = math.min(r, math.min(g, b));
            final luma = .2126 * r + .7152 * g + .0722 * b;
            // Bright, low-chroma pixels inside the actual inner lips only.
            // Dark oral cavity, tongue, red lips and surrounding skin are kept.
            final neutrality =
                1 - _ramp((maxC - minC) / math.max(1, maxC), .22, .48);
            final notRed = 1 - _ramp(r - g, 18, 42);
            final featherWeight = _ramp(
              _distance(x + .5, y + .5, face.mouth),
              0,
              math.max(1, face.width * .012),
            );
            final weight =
                settings.teeth.clamp(0.0, 1.0) *
                neutrality *
                notRed *
                _ramp(luma, 75, 140) *
                featherWeight;
            final target = (luma + (255 - luma) * .38).clamp(0.0, 255.0);
            nr += (target - r) * weight;
            ng += (target - g) * weight;
            nb += (target - b) * weight;
          }
          final rr = nr.round().clamp(0, 255),
              gg = ng.round().clamp(0, 255),
              bb = nb.round().clamp(0, 255);
          if (rr != source.r || gg != source.g || bb != source.b) {
            image.setPixelRgba(x, y, rr, gg, bb, source.a);
            changed++;
          }
        }
      }
    }
    return changed;
  }
}

class _RetouchEyeMask {
  final List<math.Point<double>> points;
  final double padding, left, right, top, bottom;
  _RetouchEyeMask(this.points, this.padding)
    : left = points.isEmpty
          ? 0
          : points.map((p) => p.x).reduce(math.min) - padding,
      right = points.isEmpty
          ? 0
          : points.map((p) => p.x).reduce(math.max) + padding,
      top = points.isEmpty
          ? 0
          : points.map((p) => p.y).reduce(math.min) - padding,
      bottom = points.isEmpty
          ? 0
          : points.map((p) => p.y).reduce(math.max) + padding;
  bool contains(double x, double y) =>
      points.isNotEmpty &&
      x >= left &&
      x <= right &&
      y >= top &&
      y <= bottom &&
      (CropRetouchPixels.inside(x, y, points) ||
          CropRetouchPixels._distance(x, y, points) < padding);
}
