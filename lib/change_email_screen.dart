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

  Future<String?> _showPhoneCodeDialog() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: surfaceColor,
        title: const Text("تأكيد رقم الهاتف", style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white, letterSpacing: 5),
          decoration: const InputDecoration(hintText: "رمز التحقق", hintStyle: TextStyle(color: Colors.white38)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("إلغاء", style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text("تأكيد", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    controller.dispose();
    return code;
  }

  Future<PhoneAuthCredential> _requestPhoneReauthentication(String phoneNumber) async {
    final completer = Completer<PhoneAuthCredential>();
    bool codeWasSent = false;
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (credential) {
        if (!completer.isCompleted) completer.complete(credential);
      },
      verificationFailed: (error) {
        if (!completer.isCompleted) completer.completeError(error);
      },
      codeSent: (verificationId, resendToken) async {
        codeWasSent = true;
        if (!mounted) {
          if (!completer.isCompleted) completer.completeError(StateError("تم إغلاق الشاشة قبل إدخال رمز التحقق"));
          return;
        }
        final code = await _showPhoneCodeDialog();
        if (completer.isCompleted) return;
        if (code == null) {
          completer.completeError(StateError("تم إلغاء التحقق من رقم الهاتف"));
        } else {
          completer.complete(PhoneAuthProvider.credential(verificationId: verificationId, smsCode: code));
        }
      },
      codeAutoRetrievalTimeout: (verificationId) {
        if (!codeWasSent && !completer.isCompleted) {
          completer.completeError(TimeoutException("انتهت مهلة التحقق من رقم الهاتف"));
        }
      },
    );
    return completer.future;
  }

  Future<User> _reauthenticateCurrentUser(User user) async {
    final providerIds = user.providerData.map((p) => p.providerId).toSet();
    if (providerIds.contains('password')) {
      final currentPassword = _currentPasswordController.text.trim();
      if (currentPassword.isEmpty) throw StateError("أدخل كلمة السر الحالية لتأكيد ملكية الحساب");
      final provider = user.providerData.firstWhere((p) => p.providerId == 'password');
      final accountEmail = provider.email ?? user.email;
      if (accountEmail == null || accountEmail.isEmpty) throw StateError("تعذر العثور على بريد وسيلة الدخول الحالية");
      final credential = EmailAuthProvider.credential(email: accountEmail, password: currentPassword);
      final result = await user.reauthenticateWithCredential(credential);
      return result.user ?? FirebaseAuth.instance.currentUser ?? user;
    }
    if (providerIds.contains('google.com')) {
      final googleSignIn = GoogleSignIn(
        scopes: const ['email', 'profile'],
        serverClientId: '965066441230-tha018u6nondvcsmsrtdu4thoob7m854.apps.googleusercontent.com',
      );
      await googleSignIn.signOut();
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) throw StateError("تم إلغاء إعادة المصادقة عبر Google");
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(accessToken: googleAuth.accessToken, idToken: googleAuth.idToken);
      final result = await user.reauthenticateWithCredential(credential);
      return result.user ?? FirebaseAuth.instance.currentUser ?? user;
    }
    if (providerIds.contains('phone')) {
      final provider = user.providerData.firstWhere((p) => p.providerId == 'phone');
      final phoneNumber = provider.phoneNumber ?? user.phoneNumber;
      if (phoneNumber == null || phoneNumber.isEmpty) throw StateError("تعذر العثور على رقم الهاتف المرتبط لإعادة المصادقة");
      final credential = await _requestPhoneReauthentication(phoneNumber);
      final result = await user.reauthenticateWithCredential(credential);
      return result.user ?? FirebaseAuth.instance.currentUser ?? user;
    }
    throw StateError("لا توجد وسيلة دخول معروفة لإعادة المصادقة. لم يتم إجراء أي تغيير.");
  }

  String _friendlyAuthError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'email-already-in-use':
        case 'credential-already-in-use':
          return "هذا البريد مستخدم أو مربوط بحساب آخر";
        case 'invalid-credential':
        case 'wrong-password':
        case 'invalid-login-credentials':
          return "بيانات إعادة المصادقة غير صحيحة";
        case 'requires-recent-login':
          return "تعذر تأكيد الجلسة. سجّل الدخول من جديد ثم أعد المحاولة";
        case 'network-request-failed':
          return "تحقق من الاتصال بالإنترنت";
        case 'provider-already-linked':
          return "وسيلة البريد وكلمة السر مرتبطة بالحساب مسبقاً";
        default:
          return error.message ?? error.code;
      }
    }
    return error.toString().replaceFirst("Bad state: ", "");
  }

  Future<void> _handleContinue() async {
    if (_isSubmitting) return;
    final auth = context.read<custom.AuthProvider>();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("أدخل البريد وكلمة السر"), backgroundColor: Colors.redAccent));
      return;
    }
    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("كلمة السر يجب أن تكون 6 أحرف على الأقل"), backgroundColor: Colors.redAccent));
      return;
    }
    final confirmed = await _showReAuthWarningDialog();
    if (!confirmed || !mounted) return;
    setState(() => _isSubmitting = true);

    try {
      var user = FirebaseAuth.instance.currentUser;
      if (user == null) throw StateError("لا يوجد مستخدم مسجل دخول");
      final originalUid = user.uid;
      await user.reload();
      user = FirebaseAuth.instance.currentUser;
      if (user == null || user.uid != originalUid) throw StateError("تغير الحساب الحالي. أعد تسجيل الدخول ثم حاول مجدداً");

      final providerIds = user.providerData.map((p) => p.providerId).toSet();
      final hasPasswordProvider = providerIds.contains('password');
      user = await _reauthenticateCurrentUser(user);
      if (user.uid != originalUid || FirebaseAuth.instance.currentUser?.uid != originalUid) {
        throw StateError("تغير الحساب أثناء إعادة المصادقة. تم إيقاف العملية لحماية الحساب");
      }

      bool emailSucceeded = false;
      bool passwordSucceeded = false;
      bool emailWasAlreadyCurrent = false;
      String? emailError, passwordError, vaultError, verificationError, syncError;

      if (hasPasswordProvider) {
        final provider = user.providerData.firstWhere((p) => p.providerId == 'password');
        final currentEmail = (provider.email ?? user.email ?? '').trim();
        if (currentEmail.toLowerCase() == email.toLowerCase()) {
          emailSucceeded = true;
          emailWasAlreadyCurrent = true;
        } else {
          try {
            await user.verifyBeforeUpdateEmail(email);
            emailSucceeded = true;
            try {
              await FirebaseFirestore.instance.collection('users').doc(originalUid).set({
                'pendingEmail': email,
                'pendingEmailRequestedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
            } catch (error) {
              syncError = "تعذر حفظ حالة البريد المعلّق في Firestore: ${_friendlyAuthError(error)}";
            }
          } catch (error) {
            emailError = _friendlyAuthError(error);
          }
        }

        // تحديث كلمة السر مستقل تماماً عن طلب تغيير البريد.
        try {
          await user.updatePassword(password);
          passwordSucceeded = true;
          try {
            await auth.savePasswordToVaultStrict(originalUid, password);
          } catch (error) {
            vaultError = _friendlyAuthError(error);
          }
        } catch (error) {
          passwordError = _friendlyAuthError(error);
        }
      } else {
        final credential = EmailAuthProvider.credential(email: email, password: password);
        try {
          final linked = await user.linkWithCredential(credential);
          user = linked.user ?? FirebaseAuth.instance.currentUser ?? user;
          await user.reload();
          user = FirebaseAuth.instance.currentUser ?? user;
          if (user.uid != originalUid || !user.providerData.any((p) => p.providerId == 'password')) {
            throw StateError("لم يؤكد Firebase ربط وسيلة البريد وكلمة السر بالحساب الحالي");
          }
          emailSucceeded = true;
          passwordSucceeded = true;
          try {
            await user.sendEmailVerification();
          } catch (error) {
            verificationError = _friendlyAuthError(error);
          }
          try {
            await FirebaseFirestore.instance.collection('users').doc(originalUid).set({
              'pendingEmail': email,
              'pendingEmailRequestedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          } catch (error) {
            syncError = "تعذر حفظ حالة البريد المعلّق في Firestore: ${_friendlyAuthError(error)}";
          }
          try {
            await auth.savePasswordToVaultStrict(originalUid, password);
          } catch (error) {
            vaultError = _friendlyAuthError(error);
          }
        } on FirebaseAuthException catch (error) {
          throw StateError(_friendlyAuthError(error));
        }
      }

      try {
        await auth.syncAccountProvidersFromFirebase();
      } catch (error) {
        syncError = syncError == null
            ? "تعذرت مزامنة بيانات الحساب: ${_friendlyAuthError(error)}"
            : "$syncError\nتعذرت مزامنة بيانات الحساب: ${_friendlyAuthError(error)}";
      }

      if (!mounted) return;
      final messages = <String>[];
      if (emailSucceeded) {
        messages.add(emailWasAlreadyCurrent
            ? "البريد الإلكتروني لم يتغير لأنه هو البريد الحالي بالفعل."
            : "تم إرسال طلب تأكيد البريد إلى $email. سيبقى البريد الحالي معتمداً حتى تأكيد الرسالة.");
      } else {
        messages.add("فشل تغيير البريد: ${emailError ?? "لم تكتمل العملية"}");
      }
      if (passwordSucceeded) {
        messages.add("تم تحديث كلمة السر في Firebase بنجاح.");
      } else {
        messages.add("فشل تحديث كلمة السر: ${passwordError ?? "لم تكتمل العملية"}");
      }
      if (verificationError != null) messages.add("تعذر إرسال رسالة تأكيد البريد: $verificationError");
      if (vaultError != null) messages.add("كلمة السر تغيّرت في Firebase لكن تعذر تحديث الخزنة المحلية: $vaultError");
      if (syncError != null) messages.add(syncError);

      final allSucceeded = emailSucceeded && passwordSucceeded && verificationError == null && vaultError == null && syncError == null;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(messages.join("\n")),
        backgroundColor: allSucceeded ? Colors.teal : Colors.orange,
        duration: const Duration(seconds: 8),
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_friendlyAuthError(error)),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 6),
      ));
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
            if (FirebaseAuth.instance.currentUser?.providerData.any((p) => p.providerId == 'password') ?? false) ...[
              const SizedBox(height: 15),
              TextField(
                controller: _currentPasswordController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "كلمة السر الحالية لتأكيد الحساب",
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: surfaceColor,
                  prefixIcon: const Icon(Icons.lock_clock_outlined, color: Colors.white38),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
            ],
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