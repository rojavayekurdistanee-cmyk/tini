import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_provider.dart' as custom;
import 'login_screen.dart';

/*
  [Tini Project Rules]:
    1. File Name: change_email_screen.dart
    2. UI Style: Simple Dark Input, Teal Action Button.
    3. Logic: Universal Link - Phone + Google + Email (Same UID) - 3 Keys One Account
    4. Fix V6.9: Full Support for All Login Types without breaking
*/

class ChangeEmailScreen extends StatefulWidget {
  const ChangeEmailScreen({super.key});

  @override
  State<ChangeEmailScreen> createState() => _ChangeEmailScreenState();
}

class _ChangeEmailScreenState extends State<ChangeEmailScreen> {
  final Color bgColor = const Color(0xFF0F1720);
  final Color surfaceColor = const Color(0xFF1A222C);

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<bool> _showReAuthWarningDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: surfaceColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text(
            "تنبيه هام",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            textAlign: TextAlign.right,
          ),
          content: const Text(
            "سيتم ربط هذا البريد وكلمة السر بنفس حسابك الحالي. بعدها ستتمكن من تسجيل الدخول بنفس الحساب إما برقم الموبايل أو بـ Google أو بالبريد وكلمة السر.",
            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
            textAlign: TextAlign.right,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("إلغاء", style: TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("تأكيد", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
    return result?? false;
  }

  Future<void> _handleContinue() async {
    final auth = context.read<custom.AuthProvider>();

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("أدخل البريد وكلمة السر"), backgroundColor: Colors.redAccent),
      );
      return;
    }
    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("كلمة السر يجب أن تكون 6 أحرف على الأقل"), backgroundColor: Colors.redAccent),
      );
      return;
    }

    final confirmed = await _showReAuthWarningDialog();
    if (!confirmed) return;
    if (!mounted) return;

    bool success = false;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw "لا يوجد مستخدم مسجل دخول";

      final bool hasPasswordProvider = user.providerData.any((p) => p.providerId == 'password');
      final bool hasGoogleProvider = user.providerData.any((p) => p.providerId == 'google.com');
      final bool hasPhoneProvider = user.providerData.any((p) => p.providerId == 'phone');

      // الحالة 1: حسابه إيميل وباسورد أصلاً -> تحديث الإيميل والباسورد
      if (hasPasswordProvider) {
        if (user.email?.toLowerCase()!= email.toLowerCase()) {
          await user.verifyBeforeUpdateEmail(email);
        }
        try {
          await user.updatePassword(password);
        } catch (_) {
          // قد يحتاج re-auth في بعض الحالات، نكمل الربط
        }
      } else {
        // الحالة 2: حسابه رقم أو Google -> ربط إيميل وباسورد جديد بنفس الـ UID
        final credential = EmailAuthProvider.credential(email: email, password: password);
        try {
          await user.linkWithCredential(credential);
        } on FirebaseAuthException catch (e) {
          if (e.code == 'provider-already-linked') {
            // عنده باسورد أصلاً
            if (user.email?.toLowerCase()!= email.toLowerCase()) {
              await user.verifyBeforeUpdateEmail(email);
            }
            await user.updatePassword(password);
          } else if (e.code == 'email-already-in-use') {
            throw "هذا البريد مستخدم في حساب آخر";
          } else if (e.code == 'credential-already-in-use') {
            throw "هذا البريد مربوط بحساب آخر";
          } else {
            rethrow;
          }
        }
      }

      // إرسال تحقق
      try {
        await user.sendEmailVerification();
      } catch (_) {}

      // تحديث Firestore بنفس الـ UID
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'email': email,
        'email_lowercase': email.toLowerCase(),
      }, SetOptions(merge: true));

      // حفظ في الخزنة V5
      try {
        await auth.savePasswordToVault(user.uid, password);
        await auth.syncCurrentAccountToVault(user.uid, auth.authType.isNotEmpty? auth.authType : 'email');
      } catch (_) {}

      success = true;
    } catch (e) {
      if (!mounted) return;
      String msg = e.toString();
      if (msg.contains('email-already-in-use') || msg.contains('مستخدم في حساب آخر')) {
        msg = "هذا البريد مستخدم في حساب آخر";
      } else if (msg.contains('credential-already-in-use') || msg.contains('مربوط بحساب آخر')) {
        msg = "هذا البريد مربوط بحساب آخر";
      } else if (msg.contains('requires-recent-login')) {
        msg = "يجب تسجيل الدخول من جديد قبل التغيير";
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
      );
    }

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF1A222C),
          duration: Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
          content: Text(
            "تم ربط البريد وكلمة السر بنجاح. تم إرسال رسالة تأكيد إلى بريدك الجديد، يرجى فتحها وتفعيلها. قم بتسجيل الدخول مرة أخرى.",
            style: TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
            textAlign: TextAlign.right,
          ),
        ),
      );

      await Future.delayed(const Duration(seconds: 3));

      if (!mounted) return;

      try {
        String? fcmToken = await FirebaseMessaging.instance.getToken();
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid!= null && fcmToken!= null) {
          await FirebaseFirestore.instance.collection('users').doc(uid).update({
            'fcmTokens': FieldValue.arrayRemove([fcmToken]),
          });
        }
      } catch (e) {
        debugPrint(e.toString());
      }

      await auth.signOut();

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
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
        title: const Text("البريد الإلكتروني", style: TextStyle(color: Colors.white, fontSize: 17)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "أدخل بريدك وكلمة سر جديدة له. سيصبح نفس حسابك الحالي يعمل بالرقم و Google و بالبريد معاً.",
              style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 30),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "البريد الإلكتروني الجديد",
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: surfaceColor,
                prefixIcon: const Icon(Icons.email_outlined, color: Colors.white38),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _passwordController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "كلمة سر جديدة للبريد (6 أحرف على الأقل)",
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: surfaceColor,
                prefixIcon: const Icon(Icons.lock_outline, color: Colors.white38),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: auth.isLoading
                   ? null
                    : () async {
                        await _handleContinue();
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: auth.isLoading
                   ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("متابعة", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}