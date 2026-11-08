import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_provider.dart' as custom;
import 'account_management_screen.dart';
import 'login_screen.dart';
import 'private_account_screen.dart';
import 'security_and_permissions_screen.dart';
import 'share_profile_sheet.dart'; // إضافة الاستيراد للشيت المنفصل
import 'notifications_settings_page.dart';
import 'audience_control_screen.dart';
import 'blocked_accounts_screen.dart'; // [إضافة جديدة] شاشة الحسابات المحظورة

/*
  [Tini Project Rules]:
    1. File Name: settings_screen.dart
    2. Concept: Grouped Sections (Exposed, not hidden).
    3. UI Style: Teal Accents, Dark Surface, Clear Headers.
    4. Anti-Flicker: Optimized for smooth navigation and fixed background.
    5. Rule: Complete code return with additions only.
*/

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  final Color bgColor = const Color(0xFF0F1720);
  final Color surfaceColor = const Color(0xFF1A222C);
  final Color titiTeal = Colors.teal;

  // دالة فتح شيت المشاركة
  void _showShareProfileSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const ShareProfileSheet(
  showBlockButton: false, // من الإعدادات لا يظهر زر الحظر
),
    );
  }

      // دالة فتح شيت تبديل الحساب - مثل تيك توك - V2 مصحح
  void _showSwitchAccountSheet(BuildContext context) {
    final authProvider = Provider.of<custom.AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.only(bottom: 30, top: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 15),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, color: Colors.white, size: 22),
                    ),
                    const Text("تبديل الحساب", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 22),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // الحساب الحالي - مصحح
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.white10,
                    backgroundImage: (currentUser!= null && currentUser.profileImg!= null && currentUser.profileImg!.isNotEmpty)? NetworkImage(currentUser.profileImg!) : null,
                    child: (currentUser == null || currentUser.profileImg == null || currentUser.profileImg!.isEmpty)
                       ? Text(
                            (currentUser?.fullName!= null && currentUser!.fullName.isNotEmpty)? currentUser.fullName[0].toUpperCase() : authProvider.fullName[0].toUpperCase(),
                            style: const TextStyle(color: Colors.white),
                          )
                        : null,
                  ),
                  title: Text(currentUser?.username?? authProvider.username, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  subtitle: Text(currentUser?.fullName?? authProvider.fullName, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  trailing: Icon(Icons.check, color: titiTeal, size: 22),
                ),
              ),
              const SizedBox(height: 12),
              // إضافة حساب - يذهب لصفحة الحسابات المسجلة
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(color: Colors.white10, shape: BoxShape.circle),
                    child: const Icon(Icons.add, color: Colors.white),
                  ),
                  title: const Text("إضافة حساب", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const LoginScreen()),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor, // اللون ثابت لمنع الوميض
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
          "الإعدادات والخصوصية",
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          // --- المجموعة الأولى: الحساب ---
          _buildSectionHeader("الحساب"),
          _buildSettingsGroup([
            _buildSettingsTile(
              Iconsax.user,
              "الحساب",
              onTap: () {
                // الربط الاحترافي بصفحة إدارة الحساب
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        const AccountManagementScreen(),
                    transitionsBuilder:
                        (context, animation, secondaryAnimation, child) {
                          return FadeTransition(
                            opacity: animation,
                            child: child,
                          );
                        },
                  ),
                );
              },
            ),
            _buildSettingsTile(
              Iconsax.lock,
              "الخصوصية",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const PrivateAccountScreen()),
                );
              },
            ),
            _buildSettingsTile(
              Iconsax.forbidden_2,
              "الحسابات المحظورة",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const BlockedAccountsScreen()),
                );
              },
            ),
            _buildSettingsTile(
              Iconsax.shield_security,
              "الأمان والأذونات",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SecurityAndPermissionsScreen()),
                );
              },
            ),
            _buildSettingsTile(
              Iconsax.share,
              "مشاركة الملف الشخصي",
              onTap: () => _showShareProfileSheet(context), // تم التفعيل
            ),
          ]),

          // --- المجموعة الثانية: المحتوى والعرض ---
          _buildSectionHeader("المحتوى والعرض"),
          _buildSettingsGroup([
            _buildSettingsTile(
  Iconsax.notification,
  "الإشعارات",
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const NotificationsSettingsPage(),
      ),
    );
  },
),
                        _buildSettingsTile(Iconsax.people, "عناصر التحكم في الجمهور", onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AudienceControlScreen()),
              );
            }),
            _buildSettingsTile(Iconsax.mask, "الإعلانات"),
            _buildSettingsTile(Iconsax.eye, "العرض"),
            _buildSettingsTile(Iconsax.language_square, "اللغة"),
            _buildSettingsTile(Iconsax.unlimited, "صلاحية الوصول"),
          ]),

          // --- المجموعة الثالثة: الدعم والقانون ---
          _buildSectionHeader("الدعم والقانون"),
          _buildSettingsGroup([
            _buildSettingsTile(Iconsax.info_circle, "مركز المساعدة"),
            _buildSettingsTile(Iconsax.document_text, "مركز الخصوصية"),
            _buildSettingsTile(Iconsax.judge, "الشروط والسياسات"),
          ]),

          // --- المجموعة الرابعة: تسجيل ---
          _buildSectionHeader("تسجيل"),
          _buildSettingsGroup([
            _buildSettingsTile(
              Iconsax.user_edit,
              "تبديل الحساب",
              onTap: () => _showSwitchAccountSheet(context),
            ),
            _buildSettingsTile(
              Iconsax.logout,
              "تسجيل الخروج",
              isDestructive: true,
              onTap: () async {
                final auth = Provider.of<custom.AuthProvider>(
                  context,
                  listen: false,
                );
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

                if (!context.mounted) return;

                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const LoginScreen(),
                  ),
                  (route) => false,
                );
              },
            ),
          ]),
        ],
      ),
    );
  }

  // بناء عنوان القسم العلوي
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 25, bottom: 10),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.teal.shade300,
          fontSize: 13,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // بناء حاوية المجموعة (الكتلة المكشوفة)
  Widget _buildSettingsGroup(List<Widget> tiles) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(children: tiles),
    );
  }

  // بناء الخيار الفردي داخل المجموعة
  Widget _buildSettingsTile(
    IconData icon,
    String title, {
    bool isDestructive = false,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        onTap: onTap ?? () {},
        leading: Icon(
          icon,
          color: isDestructive ? Colors.redAccent : Colors.white70,
          size: 22,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isDestructive ? Colors.redAccent : Colors.white,
            fontSize: 15,
          ),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          color: Colors.white10,
          size: 14,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      ),
    );
  }
}