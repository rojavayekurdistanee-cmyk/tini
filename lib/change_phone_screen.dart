import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:provider/provider.dart';
import 'auth_provider.dart' as custom;

/*
  [Tini Project Rules]:
    1. File Name: change_phone_screen.dart
    2. UI Style: Dark Background, Teal Button, International Phone Input.
    3. Logic: Universal Link - Email + Google + Phone (Same UID) - 3 Keys One Account
    4. Fix V6.9: Full Support for All Login Types without breaking
*/

class ChangePhoneScreen extends StatefulWidget {
  const ChangePhoneScreen({super.key});

  @override
  State<ChangePhoneScreen> createState() => _ChangePhoneScreenState();
}

class _ChangePhoneScreenState extends State<ChangePhoneScreen> {
  final Color bgColor = const Color(0xFF0F1720);
  final Color surfaceColor = const Color(0xFF1A222C);
  
  String _fullPhoneNumber = ""; // لتخزين الرقم مع رمز الدولة

  void _showOtpDialog(String verificationId) {
    final TextEditingController otpController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: surfaceColor,
        title: const Text("أدخل رمز التحقق", style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: otpController,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white, letterSpacing: 6),
          decoration: const InputDecoration(
            hintText: "------",
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("إلغاء", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            onPressed: () async {
              try {
                PhoneAuthCredential credential = PhoneAuthProvider.credential(
                  verificationId: verificationId,
                  smsCode: otpController.text.trim(),
                );
                final user = FirebaseAuth.instance.currentUser!;
                
                final bool hasPhoneProvider = user.providerData.any((p) => p.providerId == 'phone');
                
                try {
                  if (hasPhoneProvider) {
                    // إذا عنده رقم أصلاً -> تحديث الرقم
                    await user.updatePhoneNumber(credential);
                  } else {
                    // إذا ما عنده رقم -> ربط رقم جديد بنفس الـ UID (Google أو Email)
                    await user.linkWithCredential(credential);
                  }
                } on FirebaseAuthException catch (e) {
                  if (e.code == 'provider-already-linked') {
                    await user.updatePhoneNumber(credential);
                  } else if (e.code == 'credential-already-in-use') {
                    throw "هذا الرقم مربوط بحساب آخر";
                  } else if (e.code == 'phone-number-already-exists') {
                    throw "هذا الرقم مربوط بحساب آخر";
                  } else {
                    rethrow;
                  }
                }
                
                // [Tini Fix]: تحديث Firestore فوراً لتوحيد المصدر
                await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
                  'phoneNumber': _fullPhoneNumber,
                  'phone': _fullPhoneNumber,
                }, SetOptions(merge: true));

                // حفظ في الخزنة
                try {
                  final auth = Provider.of<custom.AuthProvider>(context, listen: false);
                  await auth.syncCurrentAccountToVault(user.uid, 'phone', phoneNumber: _fullPhoneNumber);
                } catch (_) {}

                await user.reload();
                await user.getIdToken(true);
                
                if (!mounted) return;
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (!mounted) return;
                
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("تم ربط الرقم بنجاح بنفس حسابك"), backgroundColor: Colors.teal),
                );
                
                Navigator.pop(context);
              } catch (e) {
                if (!mounted) return;
                if (!context.mounted) return;
                String msg = e.toString();
                if (msg.contains('credential-already-in-use') || msg.contains('مربوط بحساب آخر')) {
                  msg = "هذا الرقم مربوط بحساب آخر";
                } else if (msg.contains('invalid-verification-code')) {
                  msg = "كود التحقق غير صحيح";
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
                );
              }
            },
            child: const Text("تأكيد", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
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
        title: const Text("رقم الهاتف", style: TextStyle(color: Colors.white, fontSize: 17)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "أدخل رقم هاتفك الجديد. سنرسل لك رمز تحقق للتأكد من ملكية الرقم. سيصبح نفس حسابك يعمل بالرقم و Google و البريد معاً.",
              style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 30),
            IntlPhoneField(
              dropdownTextStyle: const TextStyle(color: Colors.white),
              style: const TextStyle(color: Colors.white),
              cursorColor: Colors.teal,
              textAlign: TextAlign.left,
              decoration: InputDecoration(
                labelText: 'رقم الهاتف',
                labelStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: surfaceColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              initialCountryCode: 'SA',
              onChanged: (phone) {
                _fullPhoneNumber = phone.completeNumber;
              },
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: auth.isLoading 
                  ? null 
                  : () async {
                      if (_fullPhoneNumber.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("أدخل رقم الهاتف"), backgroundColor: Colors.redAccent),
                        );
                        return;
                      }
                      await auth.verifyPhoneNumber(
                        _fullPhoneNumber,
                        onCodeSent: (verificationId) {
                          if (!mounted) return;
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("تم إرسال رمز التحقق بنجاح."),
                              backgroundColor: Colors.teal,
                            ),
                          );
                          _showOtpDialog(verificationId);
                        },
                      );
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