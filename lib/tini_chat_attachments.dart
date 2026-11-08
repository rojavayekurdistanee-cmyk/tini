import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'location_picker_sheet.dart';

/// نتيجة موقع ثابت فقط؛ لا يتم تتبع المستخدم بعد الإرسال.
class TiniFixedLocation {
  const TiniFixedLocation(this.latitude, this.longitude, this.label);
  final double latitude;
  final double longitude;
  final String label;
  String get url => 'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude';
}

class TiniChatAttachments {
  /// الحد الأقصى لحجم المستند الواحد: 50 ميغابايت.
  static const int maxDocumentBytes = 50 * 1024 * 1024;

  /// فتح الخريطة أولاً، ولا يتم الإرسال إلا بعد تأكيد المستخدم.
  static Future<TiniFixedLocation?> pickLocation(BuildContext context) {
    return showModalBottomSheet<TiniFixedLocation>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const LocationPickerSheet(forChat: true),
    );
  }

  /// طلب الإذن عند الاستخدام فقط، دون صلاحية الموقع في الخلفية.
  static Future<TiniFixedLocation?> currentLocation(BuildContext context) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى تشغيل خدمة الموقع')));
      return null;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد صلاحية للوصول إلى الموقع')));
      return null;
    }
    final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
    var label = 'موقع محدد';
    try {
      final places = await placemarkFromCoordinates(position.latitude, position.longitude);
      if (places.isNotEmpty) label = [places.first.street, places.first.locality, places.first.country].where((s) => s != null && s.isNotEmpty).join('، ');
    } catch (_) { /* فشل اسم المكان لا يمنع إرسال الإحداثيات. */ }
    return TiniFixedLocation(position.latitude, position.longitude, label);
  }

 static Future<PlatformFile?> pickDocument() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: [
      'pdf',
      'doc',
      'docx',
      'xls',
      'xlsx',
      'ppt',
      'pptx',
      'txt',
      'csv',
      'zip',
    ],
  );

  if (file == null) return null;

  // فحص الحجم قبل الرفع، دون قراءة محتوى المستند إلى الذاكرة.
  final fileSize = await file.length();
  if (fileSize == null) {
    throw StateError('تعذر تحديد حجم المستند. يرجى اختيار ملف آخر.');
  }
  if (fileSize > maxDocumentBytes) {
    throw StateError('حجم المستند يتجاوز الحد المسموح (50 ميغابايت). يرجى اختيار ملف أصغر.');
  }

  // الإصدارات الحديثة من file_picker قد تعيد ملفاً بدون مسار محلي.
  // نترك التحقق من المسار لدالة الإرسال لتجنب استهلاك الذاكرة.
  return file;
}

  static Widget message({required String type, required String text, String? mediaUrl}) {
    final location = type == 'location';
    return InkWell(
      onTap: () async {
        final uri = Uri.tryParse(location ? text : (mediaUrl ?? ''));
        if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) await launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      child: Container(
        constraints: const BoxConstraints(maxWidth: 245),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFF1A222C), borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(location ? Icons.location_on_outlined : Icons.insert_drive_file_outlined, color: Colors.teal),
          const SizedBox(width: 8),
          Flexible(child: Text(location ? 'فتح الموقع على الخريطة' : text, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white))),
        ]),
      ),
    );
  }
}
