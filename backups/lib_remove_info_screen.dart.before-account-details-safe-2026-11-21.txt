import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_provider.dart' as custom; 

class RemoveInfoScreen extends StatelessWidget {
  final String title;
  const RemoveInfoScreen({super.key, required this.title});

  final Color bgColor = const Color(0xFF0F1720);

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
                      final User? user = FirebaseAuth.instance.currentUser;
                      if (user == null) return;

                      final hasPhone = user.providerData.any((p) => p.providerId == 'phone');
                      final hasPassword = user.providerData.any((p) => p.providerId == 'password');
                      final hasGoogle = user.providerData.any((p) => p.providerId == 'google.com');
                      final providersCount = [hasPhone, hasPassword, hasGoogle].where((e) => e).length;
                      
                      if (providersCount <= 1) {
                         if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("لا يمكنك إلغاء الربط، يجب أن تبقي طريقة تسجيل واحدة على الأقل"), backgroundColor: Colors.orange),
                          );
                        }
                        return;
                      }

                      try {
                        if (title == "رقم الهاتف") {
                          if (hasPhone) {
                            await user.unlink('phone');
                          }
                          await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
                            'phoneNumber': FieldValue.delete(),
                            'phone': FieldValue.delete(),
                          });

                        } else if (title == "البريد الإلكتروني") {
                          // اذا مربوط كباسورد، فك ربطه
                          if (hasPassword) {
                            await user.unlink('password');
                          }
                          await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
                            'email': FieldValue.delete(),
                          });

                        } else if (title == "حساب Google") {
                          if (hasGoogle) {
                            await user.unlink('google.com');
                          }
                          await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
                            'googleEmail': FieldValue.delete(),
                            'isGoogleLinked': false,
                          });
                        }

                        try { await FirebaseAuth.instance.currentUser?.reload(); } catch (_) {}
                        try { await user.reload(); } catch (_) {}
                        await auth.fetchUserData();

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("تم إلغاء ربط $title بنجاح"), backgroundColor: Colors.green),
                          );
                          Navigator.pop(context, true);
                        }
                      } on FirebaseAuthException catch (e) {
                        // --- هون رح يطلع السبب الحقيقي ---
                        if (context.mounted) {
                          String reason = e.code;
                          if (e.code == 'requires-recent-login') {
                            reason = "requires-recent-login: لازم تسجل دخول من جديد";
                          } else if (e.code == 'no-such-provider') {
                            reason = "no-such-provider: الحساب مو مربوط بـ Firebase Auth (موجود بس بـ Firestore)";
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text("فشل: $reason\n${e.message ?? ''}"), 
                              backgroundColor: Colors.redAccent,
                              duration: const Duration(seconds: 5),
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text("فشل عام: ${e.toString()}"), 
                              backgroundColor: Colors.redAccent,
                              duration: const Duration(seconds: 5),
                            ),
                          );
                        }
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