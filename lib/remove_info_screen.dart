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
                      final messenger = ScaffoldMessenger.of(context);
                      final initialUser = FirebaseAuth.instance.currentUser;
                      if (initialUser == null) {
                        messenger.showSnackBar(
                          const SnackBar(content: Text("لا يوجد حساب مسجل دخول"), backgroundColor: Colors.redAccent),
                        );
                        return;
                      }

                      String providerId;
                      if (title == "رقم الهاتف") {
                        providerId = 'phone';
                      } else if (title == "البريد الإلكتروني") {
                        providerId = 'password';
                      } else if (title == "حساب Google") {
                        providerId = 'google.com';
                      } else {
                        messenger.showSnackBar(
                          const SnackBar(content: Text("وسيلة الدخول المطلوبة غير معروفة"), backgroundColor: Colors.redAccent),
                        );
                        return;
                      }

                      bool unlinkCompleted = false;
                      try {
                        final originalUid = initialUser.uid;
                        await initialUser.reload();
                        final currentUser = FirebaseAuth.instance.currentUser;
                        if (currentUser == null || currentUser.uid != originalUid) {
                          throw StateError("تغير الحساب الحالي. أعد المحاولة");
                        }

                        final providerIds = currentUser.providerData
                            .where((provider) => provider.providerId != 'firebase')
                            .map((provider) => provider.providerId)
                            .toSet();

                        if (!providerIds.contains(providerId)) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text("$title غير مرتبط فعلياً بحساب Firebase"),
                              backgroundColor: Colors.orange,
                            ),
                          );
                          return;
                        }

                        final remainingProviders = providerIds.where((id) => id != providerId).toList();
                        if (remainingProviders.isEmpty) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text("لا يمكنك إلغاء ربط آخر وسيلة دخول صالحة"),
                              backgroundColor: Colors.orange,
                            ),
                          );
                          return;
                        }

                        await currentUser.unlink(providerId);
                        unlinkCompleted = true;

                        final afterUnlink = FirebaseAuth.instance.currentUser;
                        if (afterUnlink == null || afterUnlink.uid != originalUid) {
                          throw StateError("تم إلغاء الربط لكن تعذر قراءة الحساب الحالي بعد العملية");
                        }
                        await afterUnlink.reload();

                        // تحديث Firestore والخزنة من providerData الجديد فقط.
                        await auth.syncAccountProvidersFromFirebase();
                        await auth.fetchUserData();

                        if (!context.mounted) return;
                        messenger.showSnackBar(
                          SnackBar(content: Text("تم إلغاء ربط $title بنجاح"), backgroundColor: Colors.teal),
                        );
                        Navigator.pop(context, true);
                      } on FirebaseAuthException catch (error) {
                        if (!context.mounted) return;
                        String reason = error.message ?? error.code;
                        if (error.code == 'requires-recent-login') {
                          reason = "يجب تأكيد تسجيل الدخول من جديد قبل إلغاء الربط";
                        } else if (error.code == 'no-such-provider') {
                          reason = "وسيلة الدخول غير مرتبطة فعلياً بحساب Firebase";
                        } else if (error.code == 'network-request-failed') {
                          reason = "تحقق من الاتصال بالإنترنت";
                        }
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(unlinkCompleted
                                ? "تم إلغاء الربط في Firebase، لكن تعذرت مزامنة البيانات: $reason. افتح تفاصيل الحساب لاحقاً لإعادة المزامنة."
                                : "فشل إلغاء الربط: $reason"),
                            backgroundColor: Colors.redAccent,
                            duration: const Duration(seconds: 7),
                          ),
                        );
                        if (unlinkCompleted) Navigator.pop(context, true);
                      } catch (error) {
                        if (!context.mounted) return;
                        final reason = error.toString().replaceFirst("Bad state: ", "");
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(unlinkCompleted
                                ? "تم إلغاء الربط في Firebase، لكن تعذرت مزامنة Firestore أو الخزنة: $reason. ستُعاد المحاولة عند فتح تفاصيل الحساب."
                                : "فشل إلغاء الربط: $reason"),
                            backgroundColor: Colors.redAccent,
                            duration: const Duration(seconds: 7),
                          ),
                        );
                        if (unlinkCompleted) Navigator.pop(context, true);
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