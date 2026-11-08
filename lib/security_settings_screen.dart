import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_provider.dart' as custom;
// [Tini]: إضافة استيراد صفحة إدارة كلمة السر الجديدة
import 'password_management_screen.dart';

/*
  [Tini Project Rules]:
  1. File Name: security_settings_screen.dart
  2. Logic: Fixed Switch Toggle & Active Click Listeners.
  3. UI: Dark Surface (0xFF1A222C), Background (0xFF0F1720), Teal Accents.
*/

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  final Color bgColor = const Color(0xFF0F1720);
  final Color surfaceColor = const Color(0xFF1A222C);

  bool _isOneTapEnabled = true;
  bool _isRepairing = false;

  Future<void> _handleVaultRepair(custom.AuthProvider auth) async {
    setState(() => _isRepairing = true);

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        String loginType = 'email';
        if (user.providerData.any((p) => p.providerId == 'google.com')) {
          loginType = 'google';
        } else if (user.providerData.any((p) => p.providerId == 'phone')) {
          loginType = 'phone';
        }

        await auth.syncCurrentAccountToVault(user.uid, loginType);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("تم تأمين حسابك ($loginType) في الخزنة بنجاح!"),
              backgroundColor: Colors.teal,
            ),
          );
        }
      } else {
        throw "لا يوجد مستخدم نشط حالياً";
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("فشل التحديث: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRepairing = false);
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
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "الأمان وكلمة السر",
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  _buildSecurityTile(
                    Iconsax.shield_tick,
                    "دخول بلمسة واحدة",
                    subtitle: "تفعيل حفظ بيانات الجهاز",
                    isSwitch: true,
                    switchValue: _isOneTapEnabled,
                    onChanged: (val) {
                      setState(() {
                        _isOneTapEnabled = val;
                      });
                    },
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  _buildSecurityTile(
                    Iconsax.refresh,
                    "تحديث وتصحيح الخزنة",
                    subtitle: _isRepairing
                        ? "جاري المعالجة..."
                        : "اضغط هنا لإصلاح مشكلة الدخول الصامت",
                    onTap: () => _handleVaultRepair(auth),
                    trailing: _isRepairing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.teal,
                            ),
                          )
                        : const Icon(
                            Icons.arrow_forward_ios,
                            color: Colors.white10,
                            size: 14,
                          ),
                  ),
                  const Divider(color: Colors.white10, height: 1),

                  // [Tini]: تم ربط الزر بصفحة إدارة كلمة السر بنجاح
                  _buildSecurityTile(
                    Iconsax.key,
                    "إدارة كلمة السر",
                    subtitle: "تغيير أو تحديث كلمة المرور الخاصة بك",
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              const PasswordManagementScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityTile(
    IconData icon,
    String title, {
    String? subtitle,
    bool isSwitch = false,
    bool switchValue = false,
    Function(bool)? onChanged,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: Colors.teal, size: 22),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 15),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            )
          : null,
      trailing: isSwitch
          ? Switch(
              value: switchValue,
              onChanged: onChanged,
              activeThumbColor: Colors.teal,
              activeTrackColor: Colors.teal.withValues(alpha: 0.3),
            )
          : (trailing ??
                const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white10,
                  size: 14,
                )),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
    );
  }
}
