import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:iconsax/iconsax.dart';

class DevicePermissionsScreen extends StatefulWidget {
  const DevicePermissionsScreen({super.key});
  @override
  State<DevicePermissionsScreen> createState() => _DevicePermissionsScreenState();
}

class _DevicePermissionsScreenState extends State<DevicePermissionsScreen> {
  Map<String, bool> perms = {"camera": false, "mic": false, "photos": false, "location": false};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    perms["camera"] = await Permission.camera.isGranted;
    perms["mic"] = await Permission.microphone.isGranted;
    perms["photos"] = await Permission.photos.isGranted || await Permission.storage.isGranted;
    perms["location"] = await Permission.location.isGranted;
    if(mounted) setState(() => loading = false);
  }

  Widget buildTile(String title, String sub, bool granted, Permission perm) {
    return Column(
      children: [
        ListTile(
          leading: Icon(granted ? Iconsax.tick_circle : Iconsax.close_circle, color: granted ? Colors.green : Colors.red, size: 22),
          title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15)),
          subtitle: Text(granted ? "مسموح - $sub" : "غير مسموح - $sub", style: const TextStyle(color: Colors.white54, fontSize: 11)),
          trailing: loading ? null : TextButton(
            onPressed: () async {
              if (granted) {
                await openAppSettings();
              } else {
                var status = await perm.status;
                if (status.isPermanentlyDenied) {
                  await openAppSettings(); // محظور دائم -> لازم اعدادات
                } else {
                  await perm.request(); // هون رح تطلع قائمة (سماح / سماح اثناء الاستخدام)
                }
              }
              await _check();
            },
            child: Text(granted ? "إيقاف" : "سماح", style: TextStyle(color: granted ? Colors.red : Colors.teal)),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        ),
        Divider(height: 1, color: Colors.white.withValues(alpha: 0.05), indent: 60),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1720),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1720),
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context)),
        title: const Text("أذونات الجهاز", style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: loading 
        ? const Center(child: CircularProgressIndicator(color: Colors.teal))
        : ListView(
            physics: const BouncingScrollPhysics(),
            children: [
              const SizedBox(height: 10),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: const Color(0xFF1A222C), borderRadius: BorderRadius.circular(18)),
                child: Column(
                  children: [
                    buildTile("الكاميرا", "للتصوير والستوري", perms["camera"]!, Permission.camera),
                    buildTile("الميكروفون", "للفويس والفيديو", perms["mic"]!, Permission.microphone),
                    buildTile("المعرض", "لنشر الصور والفيديو", perms["photos"]!, Permission.photos),
                    buildTile("الموقع", "لمشاركة الموقع", perms["location"]!, Permission.location),
                  ],
                ),
              ),
            ],
          ),
    );
  }
}