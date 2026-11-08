import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth_provider.dart' as custom;

// [Tini - NEW FILE ONLY - Block New]
// هاد الملف جديد بالكامل - ما بيأثر على أي بلوك قديم
// ألوان التطبيق الأصلية - مو ألوان تيك توك

class FollowingListPrivacySheet extends StatelessWidget {
  const FollowingListPrivacySheet({super.key});

  @override
  Widget build(BuildContext context) {
    // [COLORS - Tini Official Palette]
    const Color bgColor = Color(0xFF0F1720); // BG
    const Color surfaceColor = Color(0xFF1A222C); // Surface
    const Color fieldFillColor = Color(0xFF1C1C1E); // Field Fill
    const Color titiTeal = Colors.teal; // Action & Success
    const Color errorRed = Color(0xFFE53935); // Error
    const Color linkRed = Color(0xFFFF3B30); // Links & Highlight

    return Consumer<custom.AuthProvider>(
      builder: (context, auth, child) {
        // القيم الجديدة المميزة - ما الها علاقة ب everyone / only_me القديمة
        final String currentValue = auth.whoCanSeeFollowingList;

        return Container(
          decoration: const BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 15, 20, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white54,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Title Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "قائمة المتابعة",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: fieldFillColor,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white54, size: 20),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                "من يمكنه رؤية قائمة متابَعيك؟",
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 20),

              // Option 1: الكل
              _buildOption(
                title: "الكل",
                value: "follow_list_public",
                groupValue: currentValue,
                titiTeal: titiTeal,
                fieldFill: fieldFillColor,
                onTap: () {
                  auth.updateWhoCanSeeFollowingList("follow_list_public");
                },
              ),
              const SizedBox(height: 12),

              // Option 2: مخصص لك
              _buildOption(
                title: "مخصص لك",
                value: "follow_list_mutual",
                groupValue: currentValue,
                titiTeal: titiTeal,
                fieldFill: fieldFillColor,
                onTap: () {
                  auth.updateWhoCanSeeFollowingList("follow_list_mutual");
                },
              ),
              const SizedBox(height: 20),

              // Info Box - BG + Typography Secondary
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, color: Colors.white54, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        currentValue == "follow_list_mutual"
                            ? 'إذا قمت بتحديد "مخصص لك"، فسيرى المستخدمون الآخرون الأصدقاء المشتركين فقط.'
                            : 'يمكن لأي شخص رؤية قائمتي "أتابع" و"متابِعون" الخاصتين بك.',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOption({
    required String title,
    required String value,
    required String groupValue,
    required Color titiTeal,
    required Color fieldFill,
    required VoidCallback onTap,
  }) {
    final bool isSelected = value == groupValue;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? titiTeal.withValues(alpha: 0.15) : fieldFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? titiTeal : Colors.white54.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 15,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? titiTeal : Colors.white54,
                  width: 2,
                ),
                color: isSelected ? titiTeal : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 14)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
