import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/cupertino.dart';

class BrowserSettingsScreen extends StatefulWidget {
  const BrowserSettingsScreen({super.key});
  @override
  State<BrowserSettingsScreen> createState() => _BrowserSettingsScreenState();
}

class _BrowserSettingsScreenState extends State<BrowserSettingsScreen> {
  bool openInApp = true;
  bool showWarning = true;
  bool loaded = false;

  final Color bgColor = const Color(0xFF0F1720);
  final Color surfaceColor = const Color(0xFF1A222C);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      openInApp = p.getBool('browser_in_app') ?? true;
      showWarning = p.getBool('browser_warning') ?? true;
      loaded = true;
    });
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('browser_in_app', openInApp);
    await p.setBool('browser_warning', showWarning);
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return Scaffold(backgroundColor: bgColor, body: const Center(child: CircularProgressIndicator(color: Colors.teal)));
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context)),
        title: const Text("إعدادات المتصفح", style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(18)),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Iconsax.global, color: Colors.white70, size: 22),
                  title: const Text("فتح الروابط داخل التطبيق", style: TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: Text(
                    openInApp ? "سيتم فتح الروابط في المتصفح الداخلي" : "سيتم فتح الروابط في المتصفح الخارجي",
                    style: const TextStyle(color: Colors.white54, fontSize: 11)
                  ),
                  trailing: CupertinoSwitch(value: openInApp, activeTrackColor: Colors.teal, onChanged: (v) { setState(() => openInApp = v); _save(); }),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                ),
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.05), indent: 60),
                ListTile(
                  leading: const Icon(Iconsax.warning_2, color: Colors.white70, size: 22),
                  title: const Text("إظهار تنبيه قبل فتح الرابط", style: TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: const Text("عرض رسالة تأكيد قبل الانتقال إلى الرابط", style: TextStyle(color: Colors.white54, fontSize: 11)),
                  trailing: CupertinoSwitch(value: showWarning, activeTrackColor: Colors.teal, onChanged: (v) { setState(() => showWarning = v); _save(); }),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}