import 'package:flutter/material.dart';

/// نافذة "جودة الوسائط" (تصميم واتساب).
/// ترجع true = عالية الدقة، false = قياسية، أو null عند الإغلاق دون اختيار.
Future<bool?> showMediaQualitySheet(BuildContext context, {required bool isHd}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black26,
    builder: (_) => _MediaQualitySheet(isHd: isHd),
  );
}

class _MediaQualitySheet extends StatelessWidget {
  final bool isHd;
  const _MediaQualitySheet({required this.isHd});

  static const Color _bg = Color(0xFF101719);
  static const Color _green = Color(0xFF21C063);
  static const Color _grey = Color(0xFF8696A0);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: const BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: const Color(0xFF8C9396), borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Text(
                  'جودة الوسائط',
                  style: TextStyle(color: Color(0xFFE9EDEF), fontFamily: 'Tajawal', fontSize: 18, fontWeight: FontWeight.w500),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 14, 24, 10),
                child: Text(
                  'حدد الجودة التي تريد إرسال الصور ومقاطع الفيديو بها.',
                  style: TextStyle(color: _grey, fontFamily: 'Tajawal', fontSize: 14),
                ),
              ),
              _option(
                context,
                selected: !isHd,
                title: 'جودة قياسية',
                subtitle: 'إرسال أسرع، حجم ملف أصغر',
                value: false,
              ),
              _option(
                context,
                selected: isHd,
                title: 'جودة عالية الدقة',
                subtitle: 'إرسال أبطأ، يمكن أن يكون الحجم أكبر 6 أضعاف',
                value: true,
              ),
              const SizedBox(height: 14),
            ],
          ),
        ),
      ),
    );
  }

  Widget _option(
    BuildContext context, {
    required bool selected,
    required String title,
    required String subtitle,
    required bool value,
  }) {
    return InkWell(
      onTap: () => Navigator.pop(context, value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: selected ? _green : const Color(0xFF3C464A), width: 2),
              ),
              child: selected
                  ? Container(width: 12, height: 12, decoration: const BoxDecoration(color: _green, shape: BoxShape.circle))
                  : null,
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Color(0xFFE9EDEF), fontFamily: 'Tajawal', fontSize: 16)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(color: _grey, fontFamily: 'Tajawal', fontSize: 13.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}