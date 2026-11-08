import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'account_details_screen.dart';
import 'security_settings_screen.dart';
import 'data_archive_screen.dart';
// 1. إضافة استيراد شاشة إغلاق الحساب
import 'close_account_screen.dart';

/*
  [Tini Project Rules]:
  1. File Name: account_management_screen.dart
  2. Concept: Account Sub-options (Linked to Security & Details).
  3. UI Style: Dark Surface (0xFF1A222C), Background (0xFF0F1720), Teal Accents.
  4. Update: Linked CloseAccountScreen to the destructive button.
*/

class AccountManagementScreen extends StatelessWidget {
  const AccountManagementScreen({super.key});

  final Color bgColor = const Color(0xFF0F1720);
  final Color surfaceColor = const Color(0xFF1A222C);
  final Color titiTeal = Colors.teal;

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
          "الحساب",
          style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(top: 10),
        children: [
          _buildOptionsGroup([
            _buildOptionTile(
              Iconsax.user_tick, 
              "تفاصيل الحساب",
              onTap: () {
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) => const AccountDetailsScreen(),
                    transitionsBuilder: (context, animation, secondaryAnimation, child) {
                      return FadeTransition(opacity: animation, child: child);
                    },
                  ),
                );
              },
            ),
            _buildOptionTile(
              Iconsax.shield_security, 
              "الأمان وكلمة السر",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SecuritySettingsScreen()),
                );
              },
            ),
            _buildOptionTile(
              Iconsax.archive_1, 
              "أرشيف البيانات",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const DataArchiveScreen()),
                );
              },
            ),
            // 2. تفعيل زر إغلاق الحساب وربطه بالشاشة
            _buildOptionTile(
              Iconsax.user_remove, 
              "إغلاق الحساب", 
              isDestructive: true,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CloseAccountScreen()),
                );
              },
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildOptionsGroup(List<Widget> tiles) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(children: tiles),
    );
  }

  Widget _buildOptionTile(IconData icon, String title, {bool isDestructive = false, VoidCallback? onTap}) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: isDestructive ? Colors.redAccent : Colors.white70, size: 22),
      title: Text(
        title,
        style: TextStyle(
          color: isDestructive ? Colors.redAccent : Colors.white,
          fontSize: 15,
        ),
      ),
      trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white10, size: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
    );
  }
}