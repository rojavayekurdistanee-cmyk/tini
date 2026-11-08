import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class SecurityAlertsScreen extends StatelessWidget {
  const SecurityAlertsScreen({super.key});

  final Color bgColor = const Color(0xFF0F1720);
  final Color surfaceColor = const Color(0xFF1A222C);

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        backgroundColor: bgColor,
        body: const Center(child: Text("سجل دخول أولاً", style: TextStyle(color: Colors.white54))),
      );
    }
    final uid = user.uid;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_forward, color: Colors.white),
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Iconsax.shield_tick, size: 55, color: Colors.black),
            ),
          ),
          const SizedBox(height: 20),
          const Center(child: Text("الأمان", style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold))),
          const SizedBox(height: 10),
          const Center(child: Text("عرض وإدارة الإعدادات للحفاظ على حسابك آمناً", style: TextStyle(color: Colors.white54, fontSize: 13))),
          const SizedBox(height: 40),

          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
               .collection('users').doc(uid).collection('securityAlerts')
               .orderBy('date', descending: true)
               .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const SizedBox();
              }
              if (!snapshot.hasData) return const SizedBox();
              
              // فلترة آخر 7 أيام بالكود مشان ما تحتاج Index
              final now = DateTime.now();
              final sevenDaysAgo = now.subtract(const Duration(days: 7));
              final filteredDocs = snapshot.data!.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final ts = data['date'];
                if (ts is Timestamp) {
                  return ts.toDate().isAfter(sevenDaysAgo);
                }
                return false;
              }).toList();

              bool hasAlerts = filteredDocs.isNotEmpty;
              return Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SecurityAlertsDetailScreen(hasAlerts: hasAlerts, docs: filteredDocs))),
                    title: const Align(alignment: Alignment.centerRight, child: Text("تنبيهات الأمان", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600))),
                    subtitle: const Align(alignment: Alignment.centerRight, child: Text("نشاط الحساب خلال الـ 7 أيام الماضية", style: TextStyle(color: Colors.white38, fontSize: 12))),
                    trailing: const Icon(Icons.arrow_back_ios, color: Colors.white24, size: 14),
                  ),
                  const SizedBox(height: 10),
                  if (!hasAlerts)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const Text("لم يتم العثور على مشكلات أمنية", style: TextStyle(color: Colors.white, fontSize: 14)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(border: Border.all(color: Colors.white), borderRadius: BorderRadius.circular(6)),
                          child: const Icon(Iconsax.shield_tick, size: 16, color: Colors.white),
                        )
                      ],
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text("تم العثور على ${filteredDocs.length} تنبيه", style: const TextStyle(color: Color(0xFFE53935), fontSize: 14)),
                          const SizedBox(width: 8),
                          const Icon(Iconsax.warning_2, color: Color(0xFFE53935), size: 18),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),

          const SizedBox(height: 35),

          ListTile(
            contentPadding: EdgeInsets.zero,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserDevicesScreen())),
            title: const Align(alignment: Alignment.centerRight, child: Text("أجهزتك", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600))),
            subtitle: const Align(alignment: Alignment.centerRight, child: Text("إدارة الأجهزة التي سجلت الدخول", style: TextStyle(color: Colors.white38, fontSize: 12))),
            trailing: const Icon(Icons.arrow_back_ios, color: Colors.white24, size: 14),
          ),
          const SizedBox(height: 15),

          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('activeSessions').orderBy('date', descending: true).limit(2).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return const SizedBox();
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFFE53935), strokeWidth: 2));
              if (snapshot.data!.docs.isEmpty) {
                return const Align(alignment: Alignment.centerRight, child: Text("لا يوجد أجهزة", style: TextStyle(color: Colors.white38)));
              }
              return Column(
                children: snapshot.data!.docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 15),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(data['deviceName']?? '', style: const TextStyle(color: Colors.white, fontSize: 14)),
                          const SizedBox(width: 8),
                          Icon(data['isWeb'] == true? Iconsax.monitor : Iconsax.mobile, color: Colors.white70, size: 18),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class SecurityAlertsDetailScreen extends StatelessWidget {
  final bool hasAlerts;
  final List<QueryDocumentSnapshot> docs;
  const SecurityAlertsDetailScreen({super.key, this.hasAlerts = false, this.docs = const []});

  String formatDate(dynamic ts) {
    if (ts == null) return 'الآن';
    if (ts is Timestamp) {
      return DateFormat('d MMMM، yyyy h:mm a').format(ts.toDate());
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1720),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1720),
        elevation: 0,
        actions: [IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_forward, color: Colors.white))],
      ),
      body: hasAlerts == false
         ? Column(
              children: [
                const Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check, color: Color(0xFF00D09C), size: 70),
                      SizedBox(height: 20),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 40),
                        child: Text("لم يتم اكتشاف أي نشاط غير عادي في الحساب في آخر 7 أيام.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 14, height: 1.6)),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: SizedBox(
                    width: double.infinity, height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE53935), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      onPressed: () => Navigator.pop(context),
                      child: const Text("تم", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                ),
                const SizedBox(height: 25),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              itemBuilder: (context, i) {
                final data = docs[i].data() as Map<String, dynamic>;
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFF1A222C), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE53935).withValues(alpha:0.3))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(data['title']?? 'تنبيه أمان', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          const Icon(Iconsax.warning_2, color: Color(0xFFE53935), size: 18),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(data['deviceName']?? '', style: const TextStyle(color: Colors.white, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(data['loginMethod']?? '', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(formatDate(data['date']), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class UserDevicesScreen extends StatelessWidget {
  const UserDevicesScreen({super.key});

  String formatDate(dynamic ts) {
    if (ts == null) return 'الآن';
    if (ts is Timestamp) {
      return DateFormat('d MMMM، yyyy h:mm a').format(ts.toDate());
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F1720),
        body: const Center(child: Text("سجل دخول أولاً", style: TextStyle(color: Colors.white54))),
      );
    }
    final uid = user.uid;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1720),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1720),
        elevation: 0,
        centerTitle: true,
        title: const Text("إدارة الأجهزة", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('activeSessions').orderBy('date', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text("خطأ: ${snapshot.error}\nتأكد من قواعد Firestore", textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
            ));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFFE53935)));
          }
          
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) return const Center(child: Text("لا يوجد أجهزة مسجلة", style: TextStyle(color: Colors.white54)));

          final currentDevice = docs.first;
          final otherDevices = docs.skip(1).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Align(alignment: Alignment.centerRight, child: Text("الجهاز الحالي", style: TextStyle(color: Colors.white54, fontSize: 13))),
              const SizedBox(height: 10),
              _deviceCardReal(doc: currentDevice, isCurrent: true, formatDate: formatDate),
              const SizedBox(height: 25),
              if (otherDevices.isNotEmpty) ...[
                const Row(mainAxisAlignment: MainAxisAlignment.end, children: [Text("الأجهزة الأخرى التي سجلت الدخول عليها", style: TextStyle(color: Colors.white, fontSize: 14)), SizedBox(width: 6), Icon(Icons.info_outline, color: Colors.white38, size: 16)]),
                const SizedBox(height: 10),
                ...otherDevices.map((d) => _deviceCardReal(doc: d, showDelete: true, formatDate: formatDate)),
              ]
            ],
          );
        },
      ),
    );
  }

  Widget _deviceCardReal({required QueryDocumentSnapshot doc, bool isCurrent = false, bool showDelete = false, required String Function(dynamic) formatDate}) {
    final data = doc.data() as Map<String, dynamic>;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1A222C), borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showDelete)
            InkWell(
              onTap: () async {
                await doc.reference.delete();
              },
              child: const Padding(padding: EdgeInsets.only(top: 10), child: Icon(Iconsax.trash, color: Colors.white38, size: 20)),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text(data['deviceName']?? 'جهاز غير معروف', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Icon(data['isWeb'] == true? Iconsax.monitor : Iconsax.mobile, color: Colors.white54, size: 18)
                ]),
                const SizedBox(height: 6),
                Text(data['app']?? 'Tini تطبيق', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 4),
                Text(data['loginMethod']?? 'طريقة تسجيل دخول غير معروفة', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                const SizedBox(height: 4),
                Text(formatDate(data['date']), style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}