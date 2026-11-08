import 'package:flutter/material.dart';

class SystemNotificationDetailScreen extends StatelessWidget {
  final String hoursText;
  final String avgText;
  final String percentText;
  final String title;

  const SystemNotificationDetailScreen({
    super.key,
    required this.hoursText,
    required this.avgText,
    required this.percentText,
    this.title = 'تقريرك الأسبوعي',
  });

  @override
  Widget build(BuildContext context) {
    const bgColor = Color(0xFF0F1720);
    const surfaceColor = Color(0xFF1A222C);
    
    bool isDaily = avgText.isEmpty && percentText.isEmpty;
    String displayTitle = isDaily ? 'تجاوزت الحد اليومي' : title;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20), 
          onPressed: () => Navigator.pop(context)
        ),
        title: const Text("تفاصيل الإشعار", style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold, fontFamily: 'Tajawal')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(18)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  textDirection: TextDirection.rtl,
                  children: [
                    Icon(isDaily ? Icons.timer_outlined : Icons.calendar_today, color: const Color(0xFF14B8A6), size: 18),
                    const SizedBox(width: 8),
                    Text(displayTitle, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Tajawal')),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  isDaily
                  ? "قضيت $hoursText اليوم على Tini وتجاوزت الحد الذي حددته"
                  : "قضيت $hoursText هذا الأسبوع على إجمالي هذا الأسبوع Tini",
                  style: TextStyle(color: Colors.white.withValues(alpha:0.7), fontSize: 13, fontFamily: 'Tajawal', height: 1.6),
                  textAlign: TextAlign.right,
                  textDirection: TextDirection.rtl,
                ),
                const SizedBox(height: 16),
                if (!isDaily) _row("المتوسط اليومي", avgText),
                if (!isDaily) const SizedBox(height: 12),
                if (!isDaily) _row("المقارنة", percentText),
                if (isDaily) _row("الوقت المستخدم", hoursText),
                const SizedBox(height: 20),
                Divider(color: Colors.white.withValues(alpha:0.1)),
                const SizedBox(height: 12),
                Text(
                  isDaily
                  ? "حاول تقليل وقتك اليوم وخذ استراحة. يمكنك تعديل الحد اليومي من صفحة مدة الاستخدام."
                  : "حاول تقليل وقتك بنسبة 10% الأسبوع القادم لتحافظ على توازنك. يمكنك ضبط حد يومي من صفحة مدة الاستخدام.",
                  style: TextStyle(color: Colors.white.withValues(alpha:0.6), fontSize: 13, fontFamily: 'Tajawal', height: 1.6),
                  textAlign: TextAlign.right,
                  textDirection: TextDirection.rtl,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String title, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      textDirection: TextDirection.rtl,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            value, 
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Tajawal'),
            textAlign: TextAlign.left,
            textDirection: TextDirection.rtl,
          ),
        ),
        const SizedBox(width: 12),
        Text(title, style: TextStyle(color: Colors.white.withValues(alpha:0.5), fontSize: 13, fontFamily: 'Tajawal')),
      ],
    );
  }
}