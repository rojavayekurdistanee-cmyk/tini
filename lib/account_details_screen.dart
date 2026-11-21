import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_provider.dart' as custom;

import 'change_phone_screen.dart';
import 'change_email_screen.dart';
import 'change_google_link_screen.dart';
import 'remove_info_screen.dart';

/*
  [Tini Project Rules]:
    1. File Name: account_details_screen.dart
    2. Concept: Account Details with Real-Time Data + Google (3 Keys One Account)
    3. UI Style: Dark Surface (0xFF1A222C), Background (0xFF0F1720).
    4. Fix V7.5: as custom + fixed google_play + fixed const
*/

class AccountDetailsScreen extends StatefulWidget {
  const AccountDetailsScreen({super.key});

  @override
  State<AccountDetailsScreen> createState() => _AccountDetailsScreenState();
}

class _AccountDetailsScreenState extends State<AccountDetailsScreen> with WidgetsBindingObserver {
  final Color bgColor = const Color(0xFF0F1720);
  final Color surfaceColor = const Color(0xFF1A222C);
  String? _pendingEmail;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshData());
  }

  Future<void> _refreshData() async {
    final auth = context.read<custom.AuthProvider>();
    try {
      await FirebaseAuth.instance.currentUser?.reload();
      await auth.syncAccountProvidersFromFirebase();
    } catch (_) {
      // لا نخفي فشل مزامنة وسائل الدخول؛ نوضح للمطوّر أن التحديث لم يكتمل.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("تعذرت مزامنة وسائل تسجيل الدخول. تحقق من الاتصال وحاول تحديث الصفحة."),
          ),
        );
      }
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final snapshot = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        final pending = snapshot.data()?['pendingEmail'];
        if (mounted) setState(() => _pendingEmail = pending is String && pending.isNotEmpty ? pending : null);
      } catch (_) {}
    }
    if (!mounted) return;
    await auth.fetchUserData();
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshData();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "تفاصيل الحساب",
          style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
        ),
      ),
      body: Consumer<custom.AuthProvider>(
        builder: (context, auth, child) {
          final currentUser = FirebaseAuth.instance.currentUser;
          final providers = currentUser?.providerData ?? <UserInfo>[];
          final googleProviders = providers.where((p) => p.providerId == 'google.com').toList();
          final passwordProviders = providers.where((p) => p.providerId == 'password').toList();
          final phoneProviders = providers.where((p) => p.providerId == 'phone').toList();
          final hasGoogle = googleProviders.isNotEmpty;
          final hasPassword = passwordProviders.isNotEmpty;
          final hasPhoneProvider = phoneProviders.isNotEmpty;
          final googleEmail = hasGoogle ? (googleProviders.first.email ?? "") : "";
          final passwordEmail = hasPassword ? (passwordProviders.first.email ?? currentUser?.email ?? "") : "";
          final phoneFromProvider = hasPhoneProvider
              ? (phoneProviders.first.phoneNumber ?? currentUser?.phoneNumber ?? "")
              : "";
          final emailVerificationStatus = _pendingEmail != null
              ? "\nبانتظار تأكيد: $_pendingEmail"
              : (currentUser?.emailVerified == false ? "\nبانتظار تأكيد البريد" : "");
          final emailDisplay = !hasPassword
              ? "غير مرتبط"
              : "${passwordEmail.isEmpty ? "مرتبط" : passwordEmail}$emailVerificationStatus";
          final phoneDisplay = !hasPhoneProvider
              ? "غير مرتبط"
              : (phoneFromProvider.isEmpty ? "مرتبط" : phoneFromProvider);
          final phoneActionValue = hasPhoneProvider ? (phoneFromProvider.isEmpty ? "مرتبط" : phoneFromProvider) : "";
          final emailActionValue = hasPassword ? (passwordEmail.isEmpty ? "مرتبط" : passwordEmail) : "";

          return RefreshIndicator(
            onRefresh: () => _refreshData(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              padding: const EdgeInsets.only(top: 10),
              children: [
                _buildInfoGroup([
                  _buildInfoTile(
                    context,
                    Iconsax.call, 
                    "رقم الهاتف", 
                    phoneDisplay,
                    () => _showActionSheet(context, "رقم الهاتف", Iconsax.call, phoneActionValue, isPhone: true),
                  ),
                  _buildInfoTile(
                    context,
                    Iconsax.sms, 
                    "البريد الإلكتروني", 
                    emailDisplay,
                    () => _showActionSheet(context, "البريد الإلكتروني", Iconsax.sms, emailActionValue, isPhone: false),
                  ),
                  _buildInfoTile(
                    context,
                    Iconsax.link, 
                    "حساب Google", 
                    hasGoogle ? (googleEmail.isEmpty ? "مرتبط" : googleEmail) : "غير مرتبط",
                    () => _showGoogleActionSheet(context, hasGoogle, googleEmail),
                  ),
                ]),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 25, vertical: 15),
                  child: Text(
                    "تُستخدم هذه المعلومات لتأمين حسابك وتسهيل عملية التواصل واسترداد الحساب.",
                    style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.5),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showGoogleActionSheet(BuildContext context, bool hasGoogle, String googleEmail) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Iconsax.link, color: Colors.white, size: 40),
              ),
              const SizedBox(height: 15),
              const Text(
                "حساب Google",
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              Text(
                hasGoogle ? (googleEmail.isEmpty ? "مرتبط" : googleEmail) : "غير مرتبط",
                style: const TextStyle(color: Colors.white38, fontSize: 14),
              ),
              const SizedBox(height: 30),
              _buildSheetButton(
                hasGoogle ? "تغيير حساب Google" : "ربط حساب Google", 
                Iconsax.link, 
                () async {
                  Navigator.pop(context);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ChangeGoogleLinkScreen()),
                  );
                  await _refreshData();
                },
              ),
              if (hasGoogle) ...[
                const SizedBox(height: 12),
                _buildSheetButton("إلغاء ربط Google", Iconsax.trash, () async {
                  Navigator.pop(context);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => RemoveInfoScreen(title: "حساب Google"),
                    ),
                  );
                  await _refreshData();
                }, isDestructive: true),
              ],
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("إلغاء", style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  void _showActionSheet(BuildContext context, String title, IconData icon, String value, {required bool isPhone}) {
    final bool isLinked = value.isNotEmpty;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 40),
              ),
              const SizedBox(height: 15),
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              Text(
                value.isEmpty ? "غير مرتبط" : value,
                style: const TextStyle(color: Colors.white38, fontSize: 14),
              ),
              const SizedBox(height: 30),
              if (isLinked) ...[
                _buildSheetButton("تغيير $title", Iconsax.edit, () async {
                  Navigator.pop(context);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => isPhone ? const ChangePhoneScreen() : const ChangeEmailScreen(),
                    ),
                  );
                  await _refreshData();
                }),
                const SizedBox(height: 12),
                _buildSheetButton("إلغاء ربط $title", Iconsax.trash, () async {
                  Navigator.pop(context);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => RemoveInfoScreen(title: title),
                    ),
                  );
                  await _refreshData();
                }, isDestructive: true),
              ] else ...[
                _buildSheetButton("ربط $title", Iconsax.link, () async {
                  Navigator.pop(context);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => isPhone ? const ChangePhoneScreen() : const ChangeEmailScreen(),
                    ),
                  );
                  await _refreshData();
                }),
              ],
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("إلغاء", style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSheetButton(String label, IconData icon, VoidCallback onTap, {bool isDestructive = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            Icon(icon, color: isDestructive ? Colors.redAccent : Colors.white70, size: 22),
            const SizedBox(width: 15),
            Text(
              label,
              style: TextStyle(
                color: isDestructive ? Colors.redAccent : Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios, color: Colors.white10, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoGroup(List<Widget> tiles) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(children: tiles),
    );
  }

  Widget _buildInfoTile(BuildContext context, IconData icon, String title, String value, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: Colors.white70, size: 22),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
        subtitle: Text(
          value,
          style: const TextStyle(color: Colors.white38, fontSize: 13),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white10, size: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      ),
    );
  }
}