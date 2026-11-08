import 'package:flutter/material.dart';

// نفس ألوانك بالضبط
const Color kBg = Color(0xFF0F1720);
const Color kSurface = Color(0xFF1A222C);

class GroupPrivacySafetyScreen extends StatefulWidget {
  final String groupId;
  const GroupPrivacySafetyScreen({super.key, required this.groupId});

  @override
  State<GroupPrivacySafetyScreen> createState() => _GroupPrivacySafetyScreenState();
}

class _GroupPrivacySafetyScreenState extends State<GroupPrivacySafetyScreen> {

  Widget _buildDisabledRow({
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Switch(
            value: false,
            onChanged: null, // مقفول
            activeColor: Colors.white,
            activeTrackColor: Colors.teal,
            inactiveThumbColor: Colors.white24,
            inactiveTrackColor: Colors.white10,
            trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Colors.white38, // لون مطفي
                    fontFamily: 'Tajawal',
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Colors.white24,
                    fontFamily: 'Tajawal',
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kSurface,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.arrow_forward, color: Colors.white, size: 28),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 4),
          const Text(
            'الخصوصية والسلامة',
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'Tajawal',
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: ListView(
        children: [
          const SizedBox(height: 24),

          // رسالة توضيحية - هذا هو المهم
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'في المجموعات، يتم عرض حالة الرسائل كـ "تم الإرسال ✓✓". لا يتم حفظ من قرأ الرسالة أو من يكتب.',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Colors.white70,
                fontFamily: 'Tajawal',
                fontSize: 14,
                height: 1.6,
              ),
            ),
          ),

          const SizedBox(height: 20),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'الأشخاص الذين يمكنهم رؤية نشاطك',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: Colors.white24,
                  fontFamily: 'Tajawal',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          const SizedBox(height: 10),

          _buildDisabledRow(
            title: 'مؤشرات قراءة الرسائل',
            subtitle: 'غير متاح في المجموعات - يتم عرض "تم الإرسال" فقط.',
          ),

          _buildDisabledRow(
            title: 'مؤشر الكتابة',
            subtitle: 'غير متاح في المجموعات لتوفير الأداء.',
          ),
        ],
      ),
    );
  }
}