import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_provider.dart' as custom;

class RemoveInfoScreen extends StatelessWidget {
  final String title;
  const RemoveInfoScreen({super.key, required this.title});

  final Color bgColor = const Color(0xFF0F1720);

  String? _providerIdForTitle() {
    switch (title) {
      case "رقم الهاتف":
        return 'phone';
      case "البريد الإلكتروني":
        return 'password';
      case "حساب Google":
        return 'google.com';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<custom.AuthProvider>(context);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(25.0),
        child: Column(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 80),
            const SizedBox(height: 25),
            Text(
              "إلغاء ربط $title؟",
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),
            const Text(
              "بمجرد إلغاء الربط، لن تتمكن من استخدامه لتسجيل الدخول أو استرداد حسابك. هل أنت متأكد؟",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.6),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: auth.isLoading
                    ? null
                    : () async {
                        final providerId = _providerIdForTitle();
                        final user = FirebaseAuth.instance.currentUser;
                        if (user == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("لا يوجد حساب مسجل حالياً"), backgroundColor: Colors.redAccent),
                          );
                          return;
                        }
                        if (providerId == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("وسيلة الدخول المطلوبة غير معروفة"), backgroundColor: Colors.redAccent),
                          );
                          return;
                        }

                        final linkedProviders = user.providerData
                            .map((provider) => provider.providerId)
                            .toSet();
                        if (!linkedProviders.contains(providerId)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("وسيلة الدخول غير مرتبطة بحساب Firebase حالياً"), backgroundColor: Colors.orange),
                          );
                          return;
                        }
                        if (linkedProviders.length <= 1) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("لا يمكنك إلغاء ربط آخر وسيلة دخول صالحة"), backgroundColor: Colors.orange),
                          );
                          return;
                        }

                        try {
                          await user.unlink(providerId);
                          final currentUser = FirebaseAuth.instance.currentUser;
                          if (currentUser == null || currentUser.uid != user.uid) {
                            throw StateError("تغير الحساب أثناء إلغاء الربط");
                          }
                          await currentUser.reload();
                          final refreshedUser = FirebaseAuth.instance.currentUser;
                          if (refreshedUser == null || refreshedUser.uid != user.uid) {
                            throw StateError("تعذر تأكيد الحساب بعد إلغاء الربط");
                          }
                          final remainingProviders = refreshedUser.providerData
                              .map((provider) => provider.providerId)
                              .toSet();
                          if (remainingProviders.contains(providerId)) {
                            throw StateError("لم يؤكد Firebase إلغاء ربط وسيلة الدخول");
                          }

                          // إذا تعذرت المزامنة، نُبقي نتيجة Firebase كما هي
                          // وتُعاد المحاولة تلقائياً عند فتح تفاصيل الحساب.
                          try {
                            await context.read<custom.AuthProvider>().syncAccountLoginMethodsFromFirebase();
                            await context.read<custom.AuthProvider>().fetchUserData();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("تم إلغاء ربط $title بنجاح"), backgroundColor: Colors.green),
                            );
                          } catch (_) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text("تم إلغاء ربط $title من Firebase، لكن تعذرت مزامنة Firestore. ستُعاد المحاولة عند فتح تفاصيل الحساب."),
                                backgroundColor: Colors.orange,
                                duration: const Duration(seconds: 6),
                              ),
                            );
                          }
                          if (context.mounted) Navigator.pop(context, true);
                        } on FirebaseAuthException catch (e) {
                          if (!context.mounted) return;
                          String reason = e.message ?? e.code;
                          if (e.code == 'requires-recent-login') {
                            reason = "يلزم تسجيل الدخول مجدداً قبل إلغاء الربط.";
                          } else if (e.code == 'no-such-provider') {
                            reason = "وسيلة الدخول غير مرتبطة بحساب Firebase.";
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text("فشل إلغاء الربط: $reason"),
                              backgroundColor: Colors.redAccent,
                              duration: const Duration(seconds: 5),
                            ),
                          );
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text("فشل إلغاء الربط: ${e.toString().replaceFirst('Exception: ', '')}"),
                              backgroundColor: Colors.redAccent,
                              duration: const Duration(seconds: 5),
                            ),
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: auth.isLoading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text("تأكيد الإزالة", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
