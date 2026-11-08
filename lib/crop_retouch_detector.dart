import 'dart:math' as math;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'crop_retouch_model.dart';

class CropRetouchDetector {
  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableLandmarks: true,
      minFaceSize: .06,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );
  Future<List<CropRetouchFace>> detect(String path) async =>
      (await _detector.processImage(
        InputImage.fromFilePath(path),
      )).map(fromFace).toList(growable: false);
  Future<void> close() => _detector.close();

  static CropRetouchFace fromFace(Face face) {
    List<math.Point<double>> contour(FaceContourType type) => [
      for (final p in face.contours[type]?.points ?? <math.Point<int>>[])
        math.Point(p.x.toDouble(), p.y.toDouble()),
    ];
    List<math.Point<double>> eye(
      FaceContourType type,
      FaceLandmarkType landmark,
    ) {
      final points = contour(type);
      if (points.isNotEmpty) return points;
      final p = face.landmarks[landmark]?.position;
      if (p == null) return [];
      return [
        for (var i = 0; i < 16; i++)
          math.Point(
            p.x + face.boundingBox.width * .09 * math.cos(i * math.pi / 8),
            p.y + face.boundingBox.height * .045 * math.sin(i * math.pi / 8),
          ),
      ];
    }

    final upper = contour(FaceContourType.upperLipBottom)
      ..sort((a, b) => a.x.compareTo(b.x));
    final lower = contour(FaceContourType.lowerLipTop)
      ..sort((a, b) => b.x.compareTo(a.x));
    List<math.Point<double>> mouth = [];
    if (upper.length >= 3 && lower.length >= 3) {
      final gap =
          lower.map((p) => p.y).reduce((a, b) => a + b) / lower.length -
          upper.map((p) => p.y).reduce((a, b) => a + b) / upper.length;
      if (gap > math.max(1, face.boundingBox.height * .008)) {
        mouth = [...upper, ...lower];
      }
    }
    return CropRetouchFace(
      left: face.boundingBox.left,
      top: face.boundingBox.top,
      width: face.boundingBox.width,
      height: face.boundingBox.height,
      outline: contour(FaceContourType.face),
      leftEye: eye(FaceContourType.leftEye, FaceLandmarkType.leftEye),
      rightEye: eye(FaceContourType.rightEye, FaceLandmarkType.rightEye),
      mouth: mouth,
    );
  }
}
