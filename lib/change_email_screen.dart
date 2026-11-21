import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
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

  Future<void> _reauthenticateWithGoogle(User user) async {
    final googleSignIn = GoogleSignIn(
      scopes: ['email', 'profile'],
      serverClientId: '965066441230-tha018u6nondvcsmsrtdu4thoob7m854.apps.googleusercontent.com',
    );
    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      throw StateError("تم إلغاء التحقق باستخدام Google");
    }
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    await user.reauthenticateWithCredential(credential);
  }

  Future<PhoneAuthCredential> _requestPhoneReauthenticationCredential(String phoneNumber) async {
    final completer = Completer<PhoneAuthCredential>();
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (credential) {
        if (!completer.isCompleted) completer.complete(credential);
      },
      verificationFailed: (error) {
        if (!completer.isCompleted) completer.completeError(error);
      },
      codeSent: (verificationId, _) async {
        if (completer.isCompleted) return;
        if (!mounted) {
          completer.completeError(StateError("انتهت شاشة التحقق"));
          return;
        }
        final codeController = TextEditingController();
        final code = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: surfaceColor,
            title: const Text("تأكيد رقم الهاتف", style: TextStyle(color: Colors.white)),
            content: TextField(
              controller: codeController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white, letterSpacing: 5),
              decoration: const InputDecoration(
                hintText: "رمز التحقق",
                hintStyle: TextStyle(color: Colors.white38),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text("إلغاء", style: TextStyle(color: Colors.white70)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, codeController.text.trim()),
                child: const Text("تأكيد", style: TextStyle(color: Colors.teal)),
              ),
            ],
          ),
        );
        codeController.dispose();
        if (completer.isCompleted) return;
        if (code == null || code.isEmpty) {
          completer.completeError(StateError("تم إلغاء التحقق برمز الهاتف"));
          return;
        }
        completer.complete(PhoneAuthProvider.credential(
          verificationId: verificationId,
          smsCode: code,
        ));
      },
      codeAutoRetrievalTimeout: (_) {},
    );
    return completer.future;
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
    bool emailChangeFailed = false;
    bool passwordUpdated = false;
    bool linked = false;
    bool verificationSendFailed = false;
    bool firestoreSynced = false;
    bool vaultSynced = false;
    String? emailFailureMessage;
    String? passwordFailureMessage;

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
        final currentEmail = passwordProvider.email ?? user.email;
        if (currentEmail == null || currentEmail.isEmpty) {
          throw StateError("تعذر قراءة البريد الحالي من Firebase");
        }
        await user.reauthenticateWithCredential(
          EmailAuthProvider.credential(email: currentEmail, password: currentPassword),
        );

        if (currentEmail.toLowerCase() != email.toLowerCase()) {
          try {
            await user.verifyBeforeUpdateEmail(email);
            emailVerificationSent = true;
          } on FirebaseAuthException catch (e) {
            emailChangeFailed = true;
            emailFailureMessage = e.code == 'email-already-in-use' || e.code == 'credential-already-in-use'
                ? "البريد مستخدم أو مربوط بحساب آخر."
                : (e.message ?? "تعذر إرسال تأكيد البريد.");
          } catch (e) {
            emailChangeFailed = true;
            emailFailureMessage = e.toString();
          }
        }

        // البريد وكلمة السر عمليتان مستقلتان؛ فشل الأولى لا يمنع محاولة الثانية.
        try {
          await user.updatePassword(password);
          passwordUpdated = true;
        } on FirebaseAuthException catch (e) {
          passwordFailureMessage = e.code == 'weak-password'
              ? "كلمة السر الجديدة ضعيفة."
              : e.code == 'requires-recent-login'
                  ? "يلزم تسجيل الدخول مجدداً لتحديث كلمة السر."
                  : (e.message ?? "تعذر تحديث كلمة السر.");
        }
      } else {
        // إعادة المصادقة بالطريقة المرتبطة فعلياً قبل إضافة البريد وكلمة السر.
        if (providers.contains('google.com')) {
          await _reauthenticateWithGoogle(user);
        } else if (providers.contains('phone')) {
          final phoneProvider = user.providerData.firstWhere((p) => p.providerId == 'phone');
          final phoneNumber = phoneProvider.phoneNumber ?? user.phoneNumber;
          if (phoneNumber == null || phoneNumber.isEmpty) {
            throw StateError("تعذر قراءة رقم الهاتف المرتبط لإعادة المصادقة");
          }
          final phoneCredential = await _requestPhoneReauthenticationCredential(phoneNumber);
          await user.reauthenticateWithCredential(phoneCredential);
        }

        final credential = EmailAuthProvider.credential(email: email, password: password);
        final result = await user.linkWithCredential(credential);
        user = result.user;
        if (user == null || user.uid != originalUid) {
          throw StateError("تعذر تأكيد بقاء الحساب على UID نفسه");
        }
        linked = true;
        passwordUpdated = true;
        try {
          await user.sendEmailVerification();
          emailVerificationSent = true;
        } catch (_) {
          verificationSendFailed = true;
        }
      }

      user = FirebaseAuth.instance.currentUser;
      if (user == null || user.uid != originalUid) {
        throw StateError("تغير الحساب أثناء العملية؛ لم يتم اعتماد النتيجة");
      }

      try {
        await auth.syncAccountLoginMethodsFromFirebase();
        firestoreSynced = true;
      } catch (_) {
        firestoreSynced = false;
      }
      if (passwordUpdated) {
        try {
          await auth.savePasswordToVaultStrict(originalUid, password);
          vaultSynced = true;
        } catch (_) {
          vaultSynced = false;
        }
      }

      if (!mounted) return;
      final parts = <String>[];
      if (linked) {
        parts.add("تم ربط البريد وكلمة السر بالحساب نفسه");
      } else if (emailVerificationSent) {
        parts.add("تم إرسال طلب تأكيد البريد؛ سيبقى البريد الحالي معتمداً حتى تأكيده");
      } else if (emailChangeFailed) {
        parts.add("لم يتغير البريد: ${emailFailureMessage ?? "تعذر إرسال التأكيد"}");
      } else {
        parts.add("البريد الحالي بقي كما هو");
      }

      if (passwordUpdated) {
        parts.add("تم تحديث كلمة السر في Firebase");
      } else {
        parts.add("لم تتغير كلمة السر: ${passwordFailureMessage ?? "تعذر تحديثها"}");
      }
      if (verificationSendFailed) {
        parts.add("تعذر إرسال رسالة التحقق؛ يمكنك طلبها لاحقاً من إعدادات الحساب");
      }
      if (!firestoreSynced) {
        parts.add("تعذرت مزامنة بيانات وسائل الدخول في Firestore، وستُعاد المحاولة عند فتح تفاصيل الحساب");
      }
      if (passwordUpdated && !vaultSynced) {
        parts.add("لم تُحفظ كلمة السر الجديدة في الخزنة المحلية؛ أعد تسجيل الدخول لحفظها");
      }

      final complete = passwordUpdated && !emailChangeFailed && firestoreSynced && vaultSynced && !verificationSendFailed;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(parts.join(". "), textAlign: TextAlign.right),
          backgroundColor: complete ? const Color(0xFF1A222C) : Colors.orange.shade800,
          duration: const Duration(seconds: 7),
        ),
      );
      if (passwordUpdated || emailVerificationSent || linked) {
        Navigator.pop(context, true);
      }
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
          message = e.message ?? "تعذر إكمال العملية (" + e.code + ").";
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