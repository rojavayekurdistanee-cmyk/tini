import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'security_alerts.dart';
import 'security_check_screen.dart';
import 'two_factor_setup_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/cupertino.dart';
import 'passkey_service.dart';
import 'device_permissions_screen.dart';
import 'browser_settings_screen.dart';

/*
  [Tini Project Rules]:
    1. File Name: sec_perms.dart
    2. Location: lib/ directly
    3. Concept: Security & Permissions - Phase 1 Empty UI
    4. Colors: Your exact palette
*/

class SecurityAndPermissionsScreen extends StatelessWidget {
  const SecurityAndPermissionsScreen({super.key});

  final Color bgColor = const Color(0xFF0F1720); // BG
  final Color surfaceColor = const Color(0xFF1A222C); // Surface
  final Color fieldFill = const Color(0xFF1C1C1E); // Field Fill

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
        title: const Text("الأمان والأذونات", style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          // الكارد الأول: الأمان
          _buildSectionHeader("الأمان"),
          _buildGroup([
            _buildTile(context, Iconsax.shield_tick, "تنبيهات الأمان", "securityAlerts", const SecurityAlertsScreen()),
            _buildTile(context, Iconsax.security_safe, "فحص الأمان", "فحص شامل لنسبة الأمان", const SecurityCheckScreen()),
            _buildTile(context, Iconsax.monitor_mobbile, "أجهزتك", "activeSessions", const UserDevicesScreen()),
            _buildTile(context, Iconsax.lock_1, "التحقق بخطوتين", "twoFactorEnabled", const TwoFactorSetupScreen()),
            _buildSaveLoginTile(),
          ]),

          // الكارد الثاني: الأذونات
          _buildSectionHeader("الأذونات"),
          _buildGroup([
            _buildTile(context, Iconsax.global, "إعدادات المتصفح", "البايو والإعلانات", const BrowserSettingsScreen()),
            _buildTile(context, Iconsax.mobile, "أذونات الجهاز", "الكاميرا، الميكروفون، المعرض، الموقع", const DevicePermissionsScreen(), isLast: true),
          ]),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 25, bottom: 10),
      child: Text(title, style: TextStyle(color: Colors.teal.shade300, fontSize: 13, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildGroup(List<Widget> tiles) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(18)),
      child: Column(children: tiles),
    );
  }

  Widget _buildSaveLoginTile() {
    return const _SaveLoginTile();
  }

  Widget _buildTile(BuildContext context, IconData icon, String title, String subtitle, Widget page, {bool isLast = false}) {
    return Column(
      children: [
        ListTile(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
          leading: Icon(icon, color: Colors.white70, size: 22),
          title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15)),
          subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          trailing: Icon(Icons.arrow_forward_ios, color: Colors.white.withValues(alpha: 0.1), size: 14),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        ),
        if (!isLast) Divider(height: 1, color: Colors.white.withValues(alpha: 0.05), indent: 60),
      ],
    );
  }
}

class _SaveLoginTile extends StatefulWidget {
  const _SaveLoginTile();
  @override
  State<_SaveLoginTile> createState() => _SaveLoginTileState();
}

class _SaveLoginTileState extends State<_SaveLoginTile> {
  bool isOn = true;
  String userText = 'حسابك';
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final p = await SharedPreferences.getInstance();
    String username = '';
    try {
      final accounts = p.getStringList('saved_accounts') ?? [];
      if (accounts.isNotEmpty) {
        username = p.getString('acc_${accounts.first}_username') ?? '';
      }
      if (username.isEmpty) {
        username = p.getString('last_username') ?? '';
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      isOn = p.getBool('saveLoginInfo') ?? true;
      userText = username.isNotEmpty ? username : 'حسابك';
      loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return const SizedBox(height: 68);
    }
    return Column(
      children: [
        ListTile(
          leading: const Icon(Iconsax.save_2, color: Colors.white70, size: 22),
          title: const Text("حفظ معلومات تسجيل الدخول", style: TextStyle(color: Colors.white, fontSize: 15)),
          subtitle: Text(isOn ? "سجل الدخول إلى $userText على هذا الجهاز دون الحاجة إلى إدخال معلوماتك مرة أخرى" : "لن يتم حفظ معلومات تسجيل دخولك على هذا الجهاز", style: const TextStyle(color: Colors.white54, fontSize: 11)),
trailing: CupertinoSwitch(
            value: isOn,
            activeTrackColor: Colors.teal,
            onChanged: (v) async {
              setState(() => isOn = v);
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('saveLoginInfo', v);
              if (!v) {
                final uids = prefs.getStringList('saved_accounts') ?? [];
                final vaultKeys = prefs.getKeys().where((k) => k.startsWith('account_type_')).toList();
                final allUids = {...uids, ...vaultKeys.map((k) => k.replaceAll('account_type_', ''))}.toSet().toList();
                for (var uid in allUids) {
                  await PasskeyService.disableForUid(uid);
                }
                await prefs.remove('saved_accounts');
              }
            },
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        ),
      ],
    );
  }
}