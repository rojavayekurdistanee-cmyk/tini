import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'filter_model.dart';

class FilterUtils {
  static Future<Uint8List?> generateThumbnail({
    required String videoPath,
    required FilterModel filter,
  }) async {
    try {
      final file = File(videoPath);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      if (image == null) return null;

      // تصغير للمعاينة
      image = img.copyResize(image, width: 200);

      // تطبيق الماتريكس يدوي للـThumbnail
      final pixels = image.getBytes();
      final matrix = filter.matrix;

      for (int i = 0; i < pixels.length; i += 4) {
        final r = pixels[i];
        final g = pixels[i + 1];
        final b = pixels[i + 2];

        final newR = (r * matrix[0] + g * matrix[1] + b * matrix[2] + matrix[4]).clamp(0, 255);
        final newG = (r * matrix[5] + g * matrix[6] + b * matrix[7] + matrix[9]).clamp(0, 255);
        final newB = (r * matrix[10] + g * matrix[11] + b * matrix[12] + matrix[14]).clamp(0, 255);

        pixels[i] = newR.toInt();
        pixels[i + 1] = newG.toInt();
        pixels[i + 2] = newB.toInt();
      }

      return Uint8List.fromList(img.encodeJpg(image, quality: 80));
    } catch (e) {
      return null;
    }
  }
}