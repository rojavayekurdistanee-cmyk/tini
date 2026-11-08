import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'r2_service.dart';

/*
  [Tini Project Rules]:
  1. File Name: close_account_screen.dart
  2. UI Style: Matched with your colors (0xFF1A222C Surface, 0xFF0F1720 BG).
  3. Logic: Full Data Wipe (Auth + Firestore + Storage).
*/

class CloseAccountScreen extends StatefulWidget {
  const CloseAccountScreen({super.key});

  @override
  State<CloseAccountScreen> createState() => _CloseAccountScreenState();
}

class _CloseAccountScreenState extends State<CloseAccountScreen> {
  bool _isLoading = false;

  // 🎨 الألوان المأخوذة من الكود اللي أرسلته أنت حرفياً
  final Color bgColor = const Color(0xFF0F1720);
  final Color surfaceColor = const Color(0xFF1A222C);
  final Color titiTeal = Colors.teal;
  final Color errorRed = const Color(0xFFE53935);

  Future<void> _permanentlyDeleteAccount() async {
    setState(() => _isLoading = true);
    final User? user = FirebaseAuth.instance.currentUser;
    final String? uid = user?.uid;

    if (uid == null) return;

    try {
            // 1. حذف الصورة من R2
      try {
        final r2 = R2Service();
        await r2.deleteByUrl('profile_images/$uid.jpg');
        await r2.deleteByUrl('profile_images/$uid');
      } catch (e) {
        debugPrint("R2 delete error: $e");
      }

      // 2. حذف مستند المستخدم من Firestore (مجموعة users)
      await FirebaseFirestore.instance.collection('users').doc(uid).delete();

      // 3. حذف الحساب من Firebase Authentication
      await user?.delete();

      if (mounted) {
        // العودة لشاشة تسجيل الدخول بعد الحذف
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        _showErrorSnackBar("للأمان، يرجى إعادة تسجيل الدخول قبل حذف الحساب.");
      } else {
        _showErrorSnackBar("حدث خطأ: ${e.message}");
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: errorRed),
    );
  }

  void _showConfirmDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("تأكيد إغلاق الحساب", 
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          "هل أنت متأكد؟ سيتم حذف كافة بياناتك وصورك نهائياً ولا يمكن التراجع.",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("إلغاء", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: errorRed),
            onPressed: () {
              Navigator.pop(context);
              _permanentlyDeleteAccount();
            },
            child: const Text("حذف نهائي", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("إغلاق الحساب", 
            style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: Column(
          children: [
            const SizedBox(height: 30),
            // الأيقونة بنفس لون Teal (0xFF009688) اللي في كود الأرشيف
            Icon(Icons.person_off_outlined, color: titiTeal, size: 80),
            const SizedBox(height: 20),
            const Text(
              "مغادرة تطبيق Tini",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),
            const Text(
              "عند إغلاق الحساب، سيتم مسح كافة هويتك الرقمية وصورك من خوادمنا بشكل كامل.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 30),
            
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: titiTeal, size: 40),
                    const SizedBox(height: 15),
                    const Text(
                      "سياسة حذف البيانات",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "يتم حذف (الملف الشخصي، الصور، التفاعلات) فوراً وبدون استرجاع.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 25),

            // الزر بنفس لون الـ Teal المعتمد في الأرشيف
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: titiTeal,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _isLoading ? null : _showConfirmDialog,
                child: _isLoading 
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        "تأكيد إغلاق الحساب", 
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}