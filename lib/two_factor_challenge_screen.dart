import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';
import 'device_service.dart';
import 'auth_provider.dart' as custom;
import 'login_screen.dart';

class TwoFactorChallengeScreen extends StatefulWidget {
  final String uid;
  final String firstLoginType; // google / phone / email
  const TwoFactorChallengeScreen({super.key, required this.uid, required this.firstLoginType});

  @override
  State<TwoFactorChallengeScreen> createState() => _TwoFactorChallengeScreenState();
}

class _TwoFactorChallengeScreenState extends State<TwoFactorChallengeScreen> {
  final TextEditingController _controller = TextEditingController();
  bool loading = false;
  bool codeSent = false;
  String? _verificationId;
  int? _resendToken;

  String secondType = 'password';
  String maskedValue = '';
  String rawPhone = '';
  String rawEmail = '';

  @override
  void initState() {
    super.initState();
    _loadSecondFactor();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadSecondFactor() async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(widget.uid).get();
    final data = doc.data()?? {};

    rawPhone = (data['phoneNumber']?? data['phone']?? '').toString();
    rawEmail = (data['email']?? FirebaseAuth.instance.currentUser?.email?? '').toString();

    List<String> types = List<String>.from(data['twoFactorTypes']?? []);

    // فلترة: اذا نوع phone بس الرقم فاضي لا تختاره
    types = types.where((t) {
      if (t == 'phone') return rawPhone.isNotEmpty;
      if (t == 'email') return rawEmail.isNotEmpty;
      return true;
    }).toList();

    // اختار نوع مختلف عن طريقة الدخول الأولى
    List<String> available = types.where((t) => t!= widget.firstLoginType).toList();
    if (available.isNotEmpty) {
      secondType = available.first;
    } else if (types.isNotEmpty) {
      secondType = types.first;
    } else {
      secondType = widget.firstLoginType == 'phone'? 'password' : 'phone';
    }

    if (!mounted) return;
    setState(() {
      if (secondType == 'phone') {
        maskedValue = _maskPhone(rawPhone);
        if (rawPhone.isNotEmpty) _sendPhoneOtp(rawPhone);
      } else if (secondType == 'email') {
        maskedValue = _maskEmail(rawEmail);
        if (rawEmail.isNotEmpty) _sendEmailOtp(rawEmail);
      } else {
        maskedValue = 'كلمة السر';
      }
    });
  }

  String _maskPhone(String phone) {
    if (phone.length < 7) return phone;
    return phone.substring(0, 3) + '****' + phone.substring(phone.length - 3);
  }

  String _maskEmail(String email) {
    if (!email.contains('@')) return email;
    var parts = email.split('@');
    return parts[0].substring(0, 2) + '****@' + parts[1];
  }

  Future<void> _sendPhoneOtp(String phoneNumber) async {
    if (phoneNumber.isEmpty) return;
    setState(() => loading = true);
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        forceResendingToken: _resendToken,
        verificationCompleted: (PhoneAuthCredential credential) async {
          // تحقق تلقائي على اندرويد
          if (mounted) _goHome();
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل ارسال الكود: ${e.message}')));
        },
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
          _resendToken = resendToken;
          if (!mounted) return;
          setState(() {
            codeSent = true;
            loading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم ارسال كود الى $maskedValue')));
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _sendEmailOtp(String email) async {
    if (email.isEmpty) return;
    setState(() => loading = true);
    try {
      final callable = FirebaseFunctions.instanceFor(region: "europe-west1").httpsCallable('sendTwoFactorEmailCode');
      await callable.call({'email': email});
      if (!mounted) return;
      setState(() {
        codeSent = true;
        loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم ارسال كود الى $maskedValue')));
    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل ارسال الكود: $e')));
      }
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _verify() async {
    final input = _controller.text.trim();
    if (input.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اكتب الرمز')));
      return;
    }
    setState(() => loading = true);
    try {
      if (secondType == 'password') {
        final doc = await FirebaseFirestore.instance.collection('users').doc(widget.uid).get();
        final data = doc.data()?? {};
        final email = FirebaseAuth.instance.currentUser?.email?? data['email']?.toString();
        if (email == null || email.isEmpty) throw Exception('ما لقيت ايميل للحساب');
        AuthCredential credential = EmailAuthProvider.credential(email: email, password: input);
        await FirebaseAuth.instance.currentUser!.reauthenticateWithCredential(credential);
        await _goHome(verifiedPassword: input);
        return;
      } else if (secondType == 'phone') {
        if (_verificationId == null) {
          throw Exception('ما تم ارسال الكود بعد');
        }
        PhoneAuthCredential credential = PhoneAuthProvider.credential(
          verificationId: _verificationId!,
          smsCode: input,
        );
        // التحقق الحقيقي من الكود - اذا الكود غلط رح يرمي invalid-verification-code
        await FirebaseAuth.instance.signInWithCredential(credential).catchError((e) async {
          // اذا الحساب مربوط مسبقا رح يطلع credential-already-in-use وهاد معناه الكود صح
          if (e is FirebaseAuthException && e.code == 'credential-already-in-use') {
            return null;
          }
          throw e;
        });
        await _goHome();
        return;
      } else {
        // email OTP - للايميل لازم تعمل Cloud Function ترسل كود
        // هون منتأكد من كود مخزن بـ Firestore twoFactorCode
        final doc = await FirebaseFirestore.instance.collection('users').doc(widget.uid).get();
        final data = doc.data();
        final correctCode = data?['twoFactorCode']?.toString();
        final expiry = data?['twoFactorCodeExpiry'];
        if (expiry!= null && expiry is int && DateTime.now().millisecondsSinceEpoch > expiry) {
          throw Exception('انتهت صلاحية الرمز - اطلب كود جديد');
        }
        if (correctCode!= null && input == correctCode) {
          await _goHome();
          return;
        } else {
          throw Exception('الرمز غلط');
        }
      }
    } on FirebaseAuthException catch (e) {
      String msg = 'فشل التحقق';
      if (e.code == 'invalid-verification-code') msg = 'كود التلفون غلط';
      else if (e.code == 'wrong-password') msg = 'كلمة السر غلط';
      else if (e.code == 'invalid-credential') msg = 'كلمة السر غلط';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل التحقق: $e')));
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _goHome({String? verifiedPassword}) async {
    if (!mounted) return;
    // 1- حفظ الجهاز كموثوق بعد نجاح التحقق
    try {
      await saveActiveSession(widget.uid, loginMethod: widget.firstLoginType);
    } catch (_) {}
    // 2- مزامنة الخزنة مشان silentLogin يشتغل بعد تسجيل الخروج
    try {
      final auth = context.read<custom.AuthProvider>();
      // [ADDITION ONLY - احترام زر حفظ معلومات تسجيل الدخول]
      final prefsCheck = await SharedPreferences.getInstance();
      bool saveInfoCheck = prefsCheck.getBool('saveLoginInfo') ?? true;
      if (saveInfoCheck) {
        await auth.syncCurrentAccountToVault(widget.uid, widget.firstLoginType, phoneNumber: rawPhone.isNotEmpty? rawPhone : null);
        // [الاصلاح الاساسي] حفظ كلمة السر بالخزنة مشان الضغطة على الحساب المحفوظ تشتغل
        if (verifiedPassword!= null && verifiedPassword.isNotEmpty) {
          await auth.savePasswordToVault(widget.uid, verifiedPassword);
        }
      }
    } catch (_) {}
    // 3- حفظ الحساب محليا مشان يطلع بالقائمة المحفوظة ويفوت بضغطة وحدة
    try {
      final prefs = await SharedPreferences.getInstance();
      // [ADDITION ONLY - اذا الزر مطفي لا تحفظ]
      bool saveInfo = prefs.getBool('saveLoginInfo') ?? true;
      if (!saveInfo) {
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const HomeScreen()), (route) => false);
        return;
      }
      List<String> accounts = prefs.getStringList('saved_accounts')?? [];
      accounts.remove(widget.uid);
      accounts.insert(0, widget.uid);
      if (accounts.length > 5) accounts = accounts.sublist(0, 5);
      await prefs.setStringList('saved_accounts', accounts);
      await prefs.setString('last_uid', widget.uid);
      await prefs.setString('account_type_${widget.uid}', widget.firstLoginType);
    } catch (_) {}
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const HomeScreen()), (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1720),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1720),
        elevation: 0,
        title: const Text('تحقق أمان', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () async {
            await FirebaseAuth.instance.signOut();
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('last_uid');
            if (context.mounted) {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            }
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 30),
            const Icon(Icons.security, size: 80, color: Colors.teal),
            const SizedBox(height: 20),
            Text('تم اكتشاف جهاز جديد', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text('مطلوب تأكيد عبر: $secondType\n$maskedValue', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 30),
            TextField(
              controller: _controller,
              obscureText: secondType == 'password',
              keyboardType: secondType == 'phone'? TextInputType.number : TextInputType.text,
              style: const TextStyle(color: Colors.white, fontSize: 18, letterSpacing: 2),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: secondType == 'password'? 'اكتب كلمة السر' : secondType == 'phone'? 'اكتب كود SMS' : 'اكتب رمز التحقق',
                hintStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: const Color(0xFF1A222C),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            if (secondType == 'phone' || secondType == 'email')
              TextButton(
                onPressed: loading? null : () => secondType == 'phone'? _sendPhoneOtp(rawPhone) : _sendEmailOtp(rawEmail),
                child: Text(codeSent? 'اعادة ارسال الكود' : 'ارسال الكود', style: const TextStyle(color: Colors.teal)),
              ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: loading? null : _verify,
                child: loading? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('تأكيد', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            )
          ],
        ),
      ),
    );
  }
}