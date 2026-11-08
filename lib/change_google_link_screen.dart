import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'auth_provider.dart' as custom;

/*
  [Tini Project Rules]:
    1. File Name: change_google_link_screen.dart
    2. UI Style: Dark Background, Teal Button, Google Style.
    3. Logic: Universal Link - Email + Phone + Google (Same UID) - 3 Keys One Account
    4. Fix V7.0: Link Google Account to Any Existing Account (Phone/Email)
*/

class ChangeGoogleLinkScreen extends StatefulWidget {
  const ChangeGoogleLinkScreen({super.key});

  @override
  State<ChangeGoogleLinkScreen> createState() => _ChangeGoogleLinkScreenState();
}

class _ChangeGoogleLinkScreenState extends State<ChangeGoogleLinkScreen> {
  final Color bgColor = const Color(0xFF0F1720);
  final Color surfaceColor = const Color(0xFF1A222C);

  bool _isLoading = false;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId: '965066441230-tha018u6nondvcsmsrtdu4thoob7m854.apps.googleusercontent.com',
  );

  Future<void> _handleLinkGoogle() async {
    final auth = context.read<custom.AuthProvider>();
    setState(() => _isLoading = true);

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw "لا يوجد مستخدم مسجل دخول";

      // تحقق هل Google مربوط أصلاً
      final bool hasGoogleProvider = currentUser.providerData.any((p) => p.providerId == 'google.com');
      if (hasGoogleProvider) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("حساب Google مربوط مسبقاً"), backgroundColor: Colors.teal),
        );
        setState(() => _isLoading = false);
        return;
      }

      await _googleSignIn.signOut();
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      try {
        // ربط Google بنفس الـ UID الحالي (إيميل أو رقم)
        await currentUser.linkWithCredential(credential);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'provider-already-linked') {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("حساب Google مربوط مسبقاً"), backgroundColor: Colors.teal),
          );
          setState(() => _isLoading = false);
          return;
        } else if (e.code == 'credential-already-in-use' || e.code == 'email-already-in-use') {
          throw "هذا حساب Google مربوط بحساب آخر";
        } else {
          rethrow;
        }
      }

      // تحديث Firestore
      await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).set({
        'email': googleUser.email,
        'email_lowercase': googleUser.email.toLowerCase(),
      }, SetOptions(merge: true));

      // حفظ في الخزنة
      try {
        await auth.syncCurrentAccountToVault(currentUser.uid, 'google');
      } catch (_) {}

      await currentUser.reload();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("تم ربط Google بنجاح بنفس حسابك"), backgroundColor: Colors.teal),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      String msg = e.toString();
      if (msg.contains('مربوط بحساب آخر') || msg.contains('credential-already-in-use')) {
        msg = "هذا حساب Google مربوط بحساب آخر";
      } else if (msg.contains('network')) {
        msg = "تحقق من الاتصال بالإنترنت";
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("ربط Google", style: TextStyle(color: Colors.white, fontSize: 17)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "اربط حسابك بـ Google. بعدها ستتمكن من تسجيل الدخول بنفس حسابك إما بالرقم أو بالبريد أو بـ Google.",
              style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 30),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.g_mobiledata, color: Colors.red, size: 30),
                  ),
                  const SizedBox(width: 15),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Google", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        SizedBox(height: 4),
                        Text("ربط سريع وآمن", style: TextStyle(color: Colors.white38, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleLinkGoogle,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.black)
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.login, color: Colors.black, size: 20),
                          SizedBox(width: 10),
                          Text("ربط حساب Google", style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: surfaceColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("إلغاء", style: TextStyle(color: Colors.white70, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}