/// جودة الوسائط المرسلة في الشات (قياسية / عالية الدقة).
/// شاشة المعاينة تسجّل المسارات المختارة "عالية الدقة" هنا،
/// وخدمات الرفع والضغط تقرأ منها دون تغيير أي توقيع دوال موجودة.
class MediaQuality {
  MediaQuality._();

  static final Set<String> _hdPaths = <String>{};

  static void setHd(String path, bool hd) {
    if (hd) {
      _hdPaths.add(path);
    } else {
      _hdPaths.remove(path);
    }
  }

  static bool isHd(String path) => _hdPaths.contains(path);
}