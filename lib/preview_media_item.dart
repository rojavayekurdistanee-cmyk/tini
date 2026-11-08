import 'dart:io';

int _previewItemSeq = 0;

/// عنصر وسائط (صورة أو فيديو) داخل شاشة المعاينة المتعددة.
class PreviewMediaItem {
  final String id;
  final File file;
  final bool isVideo;
  final Duration duration;

  PreviewMediaItem({
    required this.file,
    required this.isVideo,
    this.duration = Duration.zero,
  }) : id = '${DateTime.now().microsecondsSinceEpoch}_${_previewItemSeq++}';

  /// يبني عنصراً من مسار ملف (يحدد الفيديو من الامتداد).
  factory PreviewMediaItem.fromPath(String path) {
    final String p = path.toLowerCase();
    final bool video = p.endsWith('.mp4') ||
        p.endsWith('.mov') ||
        p.endsWith('.avi') ||
        p.endsWith('.mkv') ||
        p.endsWith('.3gp') ||
        p.endsWith('.webm');
    return PreviewMediaItem(file: File(path), isVideo: video);
  }
}