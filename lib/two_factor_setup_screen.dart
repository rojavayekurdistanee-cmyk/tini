import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth_provider.dart' as custom;
import 'change_email_screen.dart';
import 'change_phone_screen.dart';

class TwoFactorSetupScreen extends StatefulWidget {
  const TwoFactorSetupScreen({super.key});

  @override
  State<TwoFactorSetupScreen> createState() => _TwoFactorSetupScreenState();
}

class _TwoFactorSetupScreenState extends State<TwoFactorSetupScreen> {
  static const bgColor = Color(0xFF0F1720);
  static const surfaceColor = Color(0xFF1A222C);
  static const checkColor = Colors.teal;
  static const mainRed = Color(0xFFFF3B30);

  bool phoneSelected = false;
  bool emailSelected = false;
  bool passwordSelected = false;
  bool _loading = true;
  bool _alreadyEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = doc.data();
    if (data != null) {
      setState(() {
        _alreadyEnabled = data['twoFactorEnabled'] == true;
        phoneSelected = data['twoFactorPhone'] ?? false;
        emailSelected = data['twoFactorEmail'] ?? false;
        passwordSelected = data['twoFactorPassword'] ?? false;
        if (!phoneSelected && !emailSelected && !passwordSelected) {
          final List types = data['twoFactorTypes'] ?? [];
          phoneSelected = types.contains('phone');
          emailSelected = types.contains('email');
          passwordSelected = types.contains('password');
        }
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _enable2FA() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    List<String> types = [];
    if (phoneSelected) types.add('phone');
    if (emailSelected) types.add('email');
    if (passwordSelected) types.add('password');

    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'twoFactorEnabled': true,
      'twoFactorTypes': types,
      'twoFactorPhone': phoneSelected,
      'twoFactorEmail': emailSelected,
      'twoFactorPassword': passwordSelected,
      'twoFactorEnabledAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: surfaceColor,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text("تم تفعيل التحقق بخطوتين بنجاح",
                  textAlign: TextAlign.right,
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(color: Colors.teal, shape: BoxShape.circle),
                child: const Icon(Icons.check, color: Colors.white, size: 16),
              ),
            ],
          ),
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: bgColor,
        body: Center(child: CircularProgressIndicator(color: checkColor)),
      );
    }
    return Consumer<custom.AuthProvider>(
      builder: (context, auth, child) {
        final currentUser = FirebaseAuth.instance.currentUser;
        final hasGoogle = currentUser?.providerData.any((p) => p.providerId == 'google.com') ?? false;
        final hasPassword = currentUser?.providerData.any((p) => p.providerId == 'password') ?? false;
        final hasPhoneProvider = currentUser?.providerData.any((p) => p.providerId == 'phone') ?? false;

        final passwordList = currentUser?.providerData.where((p) => p.providerId == 'password').toList();
        final String passwordEmail = (passwordList != null && passwordList.isNotEmpty) ? (passwordList.first.email ?? "") : "";

        final phoneList = currentUser?.providerData.where((p) => p.providerId == 'phone').toList();
        final String phoneFromProvider = (phoneList != null && phoneList.isNotEmpty) ? (phoneList.first.phoneNumber ?? "") : "";

        // البريد وكلمة السر يعتمدو على hasPassword فقط
        final hasPhone = hasPhoneProvider && (phoneFromProvider.isNotEmpty || auth.phoneNumber.isNotEmpty);
        final hasEmail = hasPassword && (passwordEmail.isNotEmpty || auth.email.isNotEmpty);

        String maskedPhone = hasPhone ? (phoneFromProvider.isEmpty ? auth.phoneNumber : phoneFromProvider) : "لم يتم إضافة رقم هاتف";
        String maskedEmail = hasEmail ? (passwordEmail.isEmpty ? auth.email : passwordEmail) : "لم يتم إضافة بريد";

        int selectedCount = (phoneSelected ? 1 : 0) + (emailSelected ? 1 : 0) + (passwordSelected ? 1 : 0);
        bool canEnable = selectedCount >= 2;

        return Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            backgroundColor: bgColor,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    const SizedBox(height: 10),
                    const Center(
                      child: Text("التحقق بخطوتين",
                          style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "سيتطلب تشغيله استخدام رمز تحقق إضافي عند تسجيل الدخول من جهاز غير موثوق.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.6),
                    ),
                    const SizedBox(height: 30),
                    const Text("حدد طريقتين على الأقل",
                        textAlign: TextAlign.right,
                        style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        children: [
                          _buildOption(
                            title: "الهاتف",
                            subtitle: hasPhone ? "سوف تتلقى رمز التحقق على $maskedPhone." : "أضف رقم هاتف - سيتم إرسال رمز SMS",
                            icon: Icons.phone_android,
                            isSelected: phoneSelected,
                            enabled: true,
                            onTap: () => setState(() => phoneSelected = !phoneSelected),
                          ),
                          _divider(),
                          _buildOption(
                            title: "البريد الإلكتروني",
                            subtitle: hasEmail ? "ستتلقى رمز التحقق على $maskedEmail." : "أضف بريد إلكتروني - سيتم إرسال رابط تحقق",
                            icon: Icons.email,
                            isSelected: emailSelected,
                            enabled: true,
                            onTap: () => setState(() => emailSelected = !emailSelected),
                          ),
                          _divider(),
                          _buildOption(
                            title: "كلمة السر",
                            subtitle: "سيتم طلب كلمة السر الخاصة بك كخطوة إضافية.",
                            icon: Icons.lock,
                            isSelected: passwordSelected,
                            enabled: true,
                            onTap: () => setState(() => passwordSelected = !passwordSelected),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: canEnable
                        ? () {
                            // 1. اذا اختار هاتف وما عندو هاتف -> روح على اضافة هاتف
                            if (phoneSelected && !hasPhone) {
                              Navigator.push(context, MaterialPageRoute(builder: (c) => const ChangePhoneScreen()));
                              return;
                            }
                            // 2. اذا اختار بريد وما عندو بريد -> روح على اضافة بريد
                            if (emailSelected && !hasEmail) {
                              Navigator.push(context, MaterialPageRoute(builder: (c) => const ChangeEmailScreen()));
                              return;
                            }
                            // 3. هون الحل للمشكلة يلي قلت عليها: جوجل + كلمة السر وما عندو كلمة سر -> روح على اضافة بريد/كلمة سر
                            if (passwordSelected && !hasPassword) {
                              Navigator.push(context, MaterialPageRoute(builder: (c) => const ChangeEmailScreen()));
                              return;
                            }
                            // 4. حالات مركبة: هاتف + بريد وما في بريد، او جوجل + بريد وما في بريد، او الكل مع بعض وما في بريد
                            if ((emailSelected || passwordSelected) && !hasEmail) {
                              Navigator.push(context, MaterialPageRoute(builder: (c) => const ChangeEmailScreen()));
                              return;
                            }
                            _enable2FA();
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: canEnable ? mainRed : Colors.white24,
                      disabledBackgroundColor: Colors.white12,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                      elevation: 0,
                    ),
                    child: Text(_alreadyEnabled ? "تحديث" : "تشغيل",
                        style: TextStyle(color: canEnable ? Colors.white : Colors.white38, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOption({required String title, required String subtitle, required IconData icon, required bool isSelected, required bool enabled, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isSelected ? checkColor : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isSelected ? checkColor : Colors.white24, width: 2),
              ),
              child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 10),
                      Icon(icon, color: Colors.white54, size: 22),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(subtitle, textAlign: TextAlign.right, style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() => const Divider(color: Color(0xFF232E3A), height: 1, indent: 16, endIndent: 16);
}