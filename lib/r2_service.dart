import 'dart:io';
import 'dart:typed_data';
import 'package:minio/minio.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'media_quality.dart';

class R2Service {
  static const String endpoint = 'c1b1aafa46e941af1483ff0f31bed1e5.r2.cloudflarestorage.com';
  static const String bucket = 'titi-star-images';
  static const String publicUrl = 'https://pub-e602981c5b0b476c92bdec7ba140e7de.r2.dev';
  static const String accessKey = '441926c3b8bb9ef9f1ede70d39173681';
  static const String secretKey = '7ec7a62f2c9c6d4b759bcaca10a5cf66139636adde96c924ade7e5455ecd6e0b';

  final Minio _minio = Minio(
    endPoint: endpoint,
    accessKey: accessKey,
    secretKey: secretKey,
    useSSL: true,
    region: 'auto',
  );

Future<String> uploadFile(
    File file,
    String objectName, {
    void Function(int sentBytes, int totalBytes)? onProgress,
  }) async {
    bool isVideo = objectName.endsWith('.mp4');
    bool isProfile = objectName.contains('profile_images');
    bool isImage = objectName.toLowerCase().endsWith('.jpg') || objectName.toLowerCase().endsWith('.jpeg') || objectName.toLowerCase().endsWith('.png');
    bool isGif = objectName.toLowerCase().endsWith('.gif');

    // Stream videos from disk: do not copy a full rendered MP4 into RAM.
    // Image/GIF compression retains its original byte-based implementation.
    Uint8List fileBytes = isVideo ? Uint8List(0) : await file.readAsBytes();
    String finalObjectName = objectName;
    String contentType = 'application/octet-stream';

    if (isGif) {
      // GIF متحرك: نرفعه كما هو بدون أي ضغط حتى ما تضيع الحركة
      contentType = 'image/gif';
    } else if (isImage && MediaQuality.isHd(file.path)) {
      // جودة عالية الدقة (من شاشة معاينة الشات): بدون إعادة ضغط، JPEG الأصلي كما هو
      final bool isJpeg = fileBytes.length > 2 && fileBytes[0] == 0xFF && fileBytes[1] == 0xD8;
      if (!isJpeg) {
        fileBytes = await FlutterImageCompress.compressWithList(
          fileBytes,
          format: CompressFormat.jpeg,
          quality: 95,
          minWidth: 4096,
          minHeight: 4096,
        );
      }
      finalObjectName = objectName.replaceAll(RegExp(r'\.(jpg|jpeg|png)$'), '.jpg');
      contentType = 'image/jpeg';
    // النقطة 2 من الصورة: حول كل الصور لـ WebP
    } else if (isImage) {
      fileBytes = await FlutterImageCompress.compressWithList(
        fileBytes,
        format: CompressFormat.webp,
        quality: 80,
      );
      finalObjectName = objectName.replaceAll(RegExp(r'\.(jpg|jpeg|png)$'), '.webp');
      contentType = 'image/webp';
    } else if (isVideo) {
      contentType = 'video/mp4';
    } else {
      contentType = 'audio/m4a';
    }

    // النقطة 1 من الصورة: Cache-Control
    String cacheControl = 'public, max-age=31536000';
    if (isProfile) {
      // صور البروفايل بتتغير كتير فخليها قصيرة
      cacheControl = 'public, max-age=3600, must-revalidate';
    }

    if (isVideo) {
      final totalBytes = await file.length();
      if (totalBytes <= 0) {
        throw const FileSystemException('Video upload source is empty');
      }
      var sentBytes = 0;
      final stream = file.openRead().map((chunk) {
        sentBytes += chunk.length;
        // Counts bytes read into the uploader; completion still waits for R2.
        onProgress?.call(sentBytes.clamp(0, totalBytes).toInt(), totalBytes);
        return Uint8List.fromList(chunk);
      });
      await _minio.putObject(
        bucket,
        finalObjectName,
        stream,
        size: totalBytes,
        metadata: {
          'Content-Type': contentType,
          'Cache-Control': cacheControl,
        },
      );
    } else {
      await _minio.putObject(
        bucket,
        finalObjectName,
        Stream.value(fileBytes),
        size: fileBytes.length,
        metadata: {
          'Content-Type': contentType,
          'Cache-Control': cacheControl, // <--- هاد اللي بيوفر 80%
        },
      );
    }

    // شلت الـ?v= مشان الـ Cache يشتغل
    if (isProfile) {
      return '$publicUrl/$finalObjectName?v=${DateTime.now().millisecondsSinceEpoch}';
    }
    return '$publicUrl/$finalObjectName';
  }

  /// رفع المستندات بتدفق البيانات لتجنب تحميل الملف كاملاً في ذاكرة الهاتف.
  /// لا نستخدم هذه الدالة للصور والفيديوهات حفاظاً على معالجة الوسائط الأصلية.
  Future<String> uploadDocument(File file, String objectName) async {
    final size = await file.length();
    if (size <= 0) throw const FileSystemException('المستند فارغ');
    // الحد الأقصى للمستند الواحد: 50 ميغابايت. نتحقق قبل بدء الرفع.
    const maxDocumentBytes = 50 * 1024 * 1024;
    if (size > maxDocumentBytes) {
      throw const FileSystemException('حجم المستند يتجاوز الحد المسموح (50 ميغابايت). يرجى اختيار ملف أصغر.');
    }
    final extension = objectName.split('.').last.toLowerCase();
    const mimeTypes = <String, String>{
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt': 'application/vnd.ms-powerpoint',
      'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'txt': 'text/plain',
      'csv': 'text/csv',
      'zip': 'application/zip',
    };
await _minio.putObject(
  bucket,
  objectName,
  file.openRead().map((chunk) => Uint8List.fromList(chunk)),
  size: size,
  metadata: {
    'Content-Type': mimeTypes[extension] ?? 'application/octet-stream',
    'Cache-Control': 'private, no-store',
  },
);
    return '$publicUrl/$objectName';
  }

  Future<void> deleteByUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      String key = uri.path.startsWith('/')? uri.path.substring(1) : uri.path;
      if (key.contains('?')) key = key.split('?')[0];
      await _minio.removeObject(bucket, key);
    } catch (e) {}
  }

  // دالة جديدة للـ thumbnails - بتطبق نقطة الـ 60%
  Future<String> uploadThumbnail(File file, String objectName) async {
    final bytes = await file.readAsBytes();
    final thumbBytes = await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: 300,
      minHeight: 300,
      format: CompressFormat.webp,
      quality: 70,
    );
    final thumbName = objectName.replaceAll(RegExp(r'\.(jpg|jpeg|png)$'), '_thumb.webp');

    await _minio.putObject(
      bucket,
      thumbName,
      Stream.value(thumbBytes),
      size: thumbBytes.length,
      metadata: {
        'Content-Type': 'image/webp',
        'Cache-Control': 'public, max-age=31536000',
      },
    );
    return '$publicUrl/$thumbName';
  }
}
