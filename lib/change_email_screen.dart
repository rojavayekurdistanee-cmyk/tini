import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_provider.dart' as custom;

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
  final TextEditingController _currentPasswordController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _currentPasswordController.dispose();
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
    if (_isSubmitting) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final currentPassword = _currentPasswordController.text;

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("أدخل البريد وكلمة السر الجديدة"), backgroundColor: Colors.redAccent),
      );
      return;
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("أدخل بريداً إلكترونياً صالحاً"), backgroundColor: Colors.redAccent),
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
    if (!confirmed || !mounted) return;
    setState(() => _isSubmitting = true);

    bool emailVerificationSent = false;
    bool passwordUpdated = false;
    bool linked = false;
    try {
      final auth = context.read<custom.AuthProvider>();
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) throw StateError("لا يوجد مستخدم مسجل دخول");
      final originalUid = user.uid;
      final providers = user.providerData.map((p) => p.providerId).toSet();
      final hasPasswordProvider = providers.contains('password');

      if (hasPasswordProvider) {
        if (currentPassword.isEmpty) {
          throw FirebaseAuthException(code: 'current-password-required', message: 'أدخل كلمة السر الحالية للتحقق من هويتك قبل التعديل.');
        }
        final passwordProvider = user.providerData.firstWhere((p) => p.providerId == 'password');
        final currentEmail = user.email ?? passwordProvider.email;
        if (currentEmail == null || currentEmail.isEmpty) {
          throw StateError("تعذر قراءة البريد الحالي من Firebase");
        }
        await user.reauthenticateWithCredential(
          EmailAuthProvider.credential(email: currentEmail, password: currentPassword),
        );
        if (currentEmail.toLowerCase() != email.toLowerCase()) {
          await user.verifyBeforeUpdateEmail(email);
          emailVerificationSent = true;
        }
        // لا نبتلع فشل Firebase ولا نحفظ كلمة السر بالخزنة قبله.
        await user.updatePassword(password);
        passwordUpdated = true;
      } else {
        final credential = EmailAuthProvider.credential(email: email, password: password);
        final result = await user.linkWithCredential(credential);
        user = result.user;
        if (user == null || user.uid != originalUid) {
          throw StateError("تعذر تأكيد بقاء الحساب على UID نفسه");
        }
        linked = true;
        await user.reload();
        user = FirebaseAuth.instance.currentUser;
        if (user == null || user.uid != originalUid) {
          throw StateError("تغيرت جلسة الحساب أثناء ربط البريد");
        }
        passwordUpdated = true;
        if (!user.emailVerified) {
          await user.sendEmailVerification();
          emailVerificationSent = true;
        }
      }

      user = FirebaseAuth.instance.currentUser;
      if (user == null || user.uid != originalUid) {
        throw StateError("تغير الحساب أثناء العملية؛ لم يتم اعتماد النتيجة");
      }

      // نزامن بيانات Firebase الفعلية أولاً، ثم نحفظ كلمة السر محلياً بعد نجاح Firebase.
      await auth.syncAccountLoginMethodsFromFirebase();
      if (passwordUpdated) {
        await auth.savePasswordToVaultStrict(originalUid, password);
      }

      if (!mounted) return;
      final message = emailVerificationSent
          ? (linked
              ? "تم ربط البريد وكلمة السر بالحساب نفسه. أرسلنا رسالة تأكيد؛ لن يصبح البريد معتمداً قبل تأكيده."
              : "تم تحديث كلمة السر وإرسال طلب تأكيد البريد الجديد. سيبقى البريد الحالي معتمداً حتى تأكيد الرسالة.")
          : "تم تحديث كلمة السر بنجاح.";
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message, textAlign: TextAlign.right), backgroundColor: const Color(0xFF1A222C), duration: const Duration(seconds: 5)),
      );
      Navigator.pop(context, true);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String message;
      switch (e.code) {
        case 'email-already-in-use':
        case 'credential-already-in-use':
          message = "هذا البريد مستخدم أو مربوط بحساب آخر.";
          break;
        case 'invalid-credential':
        case 'wrong-password':
        case 'invalid-login-credentials':
          message = "كلمة السر الحالية غير صحيحة.";
          break;
        case 'requires-recent-login':
          message = "انتهت صلاحية التحقق الأمني. سجّل الدخول مجدداً ثم أعد المحاولة.";
          break;
        case 'current-password-required':
          message = e.message ?? "أدخل كلمة السر الحالية.";
          break;
        case 'weak-password':
          message = "كلمة السر الجديدة ضعيفة؛ استخدم 6 أحرف على الأقل.";
          break;
        case 'invalid-email':
          message = "صيغة البريد الإلكتروني غير صحيحة.";
          break;
        case 'provider-already-linked':
          message = "وسيلة البريد مرتبطة مسبقاً. حدّث تفاصيل الحساب ثم أعد المحاولة.";
          break;
        default:
          message = e.message ?? "تعذر إكمال التعديل (" + e.code + ").";
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message, textAlign: TextAlign.right), backgroundColor: Colors.redAccent, duration: const Duration(seconds: 6)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''), textAlign: TextAlign.right), backgroundColor: Colors.redAccent, duration: const Duration(seconds: 6)),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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
              "أدخل البريد وكلمة السر الجديدة. إذا كان البريد وكلمة السر مرتبطين حالياً، سنطلب كلمة السر الحالية للتحقق من هويتك.",
              style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
            ),
            if (FirebaseAuth.instance.currentUser?.providerData.any((p) => p.providerId == 'password') ?? false) ...[
              const SizedBox(height: 20),
              TextField(
                controller: _currentPasswordController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "كلمة السر الحالية",
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: surfaceColor,
                  prefixIcon: const Icon(Icons.lock_outline, color: Colors.white38),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
            ],
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
                onPressed: (auth.isLoading || _isSubmitting)
                   ? null
                    : () async {
                        await _handleContinue();
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: (auth.isLoading || _isSubmitting)
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