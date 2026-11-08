import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';
import 'auth_provider.dart' as custom;
import 'profile_screen.dart';
import 'home_screen.dart';

class VisitsScreen extends StatefulWidget {
  const VisitsScreen({super.key});

  @override
  State<VisitsScreen> createState() => _VisitsScreenState();
}

class _VisitsScreenState extends State<VisitsScreen> {
  // تم اصلاح كراش الـ Null check هنا
  final String myId = FirebaseAuth.instance.currentUser?.uid ?? '';

  // الوانك الثابتة
  static const bgColor = Color(0xFF0F1720);
  static const surfaceColor = Color(0xFF1A222C);
  static const fieldFillColor = Color(0xFF1C1C1E);

  @override
  void initState() {
    super.initState();
    if (myId.isNotEmpty) {
      _markAllAsSeen();
    }
  }

  Future<void> _markAllAsSeen() async {
    if (myId.isEmpty) return;
    final myDoc = await FirebaseFirestore.instance.collection('users').doc(myId).get();
    final isEnabled = (myDoc.data()?['isVisitsEnabled'] ?? true) as bool;
    if (!isEnabled) return;

    final batch = FirebaseFirestore.instance.batch();
    final snaps = await FirebaseFirestore.instance
        .collection('users')
        .doc(myId)
        .collection('visits')
        .where('isSeen', isEqualTo: false)
        .get();
    
    for (var doc in snaps.docs) {
      batch.update(doc.reference, {'isSeen': true});
    }
    if (snaps.docs.isNotEmpty) {
      await batch.commit();
    }
  }

  void _showSettingsBottomSheet(bool currentValue) {
    showModalBottomSheet(
      context: context,
      backgroundColor: surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        bool tempValue = currentValue;
        return StatefulBuilder(
          builder: (context, setStateSheet) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "المشاهدون",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54),
                        onPressed: () => Navigator.pop(context),
                      )
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: fieldFillColor,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: SwitchListTile(
                      value: tempValue,
                      activeColor: Colors.teal,
                      activeTrackColor: Colors.teal.withValues(alpha:0.4),
                      inactiveThumbColor: Colors.white54,
                      inactiveTrackColor: Colors.white10,
                      title: const Text("سجل المشاهدين", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          "اعرف من شاهد ملفك الشخصي في آخر 30 يوما. إذا أوقفت هذه الميزة، لن تتمكن من معرفة من شاهد ملفك، ولن يتمكن الآخرون من معرفة أنك شاهدت ملفاتهم.",
                          style: TextStyle(color: Colors.grey.withValues(alpha:0.9), fontSize: 12.5, height: 1.4),
                        ),
                      ),
                      onChanged: (val) async {
                        setStateSheet(() => tempValue = val);
                        setState(() {});
                        await FirebaseFirestore.instance.collection('users').doc(myId).update({'isVisitsEnabled': val});
                        if (mounted) Navigator.pop(context);
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatTime(Timestamp? ts) {
    if (ts == null) return "الآن";
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inMinutes < 1) return "الآن";
    if (diff.inMinutes < 60) return "منذ ${diff.inMinutes}د";
    if (diff.inHours < 24) return "منذ ${diff.inHours}س";
    if (diff.inDays < 7) return "منذ ${diff.inDays}ي";
    return "${ts.toDate().day}/${ts.toDate().month}";
  }

  // ⭐ ويدجت زر الحالة الجديد - نفس منطق البروفايل - بألوان تيتي ستار
  Widget _buildFollowStatusButton(String visitorId) {
    if (myId.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(myId).collection('following').doc(visitorId).snapshots(),
      builder: (context, myFollowingSnap) {
        final bool amFollowing = myFollowingSnap.data?.exists ?? false;
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(visitorId).collection('following').doc(myId).snapshots(),
          builder: (context, hisFollowingSnap) {
            final bool isFollower = hisFollowingSnap.data?.exists ?? false;

            String btnText;
            Color btnBg;
            Color btnFg;
            Color borderColor = Colors.transparent;

            if (amFollowing && isFollower) {
              btnText = "صديق ✓";
              btnBg = surfaceColor;
              btnFg = Colors.white70;
              borderColor = Colors.white24;
            } else if (!amFollowing && isFollower) {
              btnText = "رد المتابعة";
              btnBg = Colors.teal; // Titi Teal
              btnFg = Colors.white;
            } else if (amFollowing) {
              btnText = "أتابع";
              btnBg = surfaceColor;
              btnFg = Colors.white70;
              borderColor = Colors.white24;
            } else {
              btnText = "متابعة";
              btnBg = Colors.teal; // Titi Teal
              btnFg = Colors.white;
            }

            return SizedBox(
              height: 32,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: btnBg,
                  foregroundColor: btnFg,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  side: borderColor != Colors.transparent ? BorderSide(color: borderColor, width: 0.8) : BorderSide.none,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  minimumSize: const Size(0, 32),
                ),
                onPressed: () async {
                  await Provider.of<custom.AuthProvider>(context, listen: false).toggleFollow(visitorId);
                },
                child: Text(btnText, style: TextStyle(color: btnFg, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (myId.isEmpty) {
      return const Scaffold(
        backgroundColor: bgColor,
        body: Center(child: CircularProgressIndicator(color: Colors.teal)),
      );
    }
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
  icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
  onPressed: () {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => HomeScreen()),
        (route) => false,
      );
    }
  },
),
        title: const Text("من زار بروفايلك", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('users').doc(myId).snapshots(),
            builder: (context, snap) {
              final isEnabled = (snap.data?.data() as Map<String, dynamic>?)?['isVisitsEnabled'] ?? true;
              return Row(
                children: [
                  if (isEnabled)
                    IconButton(
                      icon: const Icon(Iconsax.trash, color: Colors.white54, size: 20),
                      onPressed: () async {
                        final batch = FirebaseFirestore.instance.batch();
                        final snaps = await FirebaseFirestore.instance.collection('users').doc(myId).collection('visits').get();
                        for (var doc in snaps.docs) {
                          batch.delete(doc.reference);
                        }
                        await batch.commit();
                      },
                    ),
                  IconButton(
                    icon: const Icon(Iconsax.setting_2, color: Colors.white54, size: 20),
                    onPressed: () => _showSettingsBottomSheet(isEnabled),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(myId).snapshots(),
        builder: (context, mySnap) {
          if (!mySnap.hasData) {
            return const Center(child: CircularProgressIndicator(color: Colors.teal));
          }
          final myData = mySnap.data!.data() as Map<String, dynamic>?;
          final isVisitsEnabled = (myData?['isVisitsEnabled'] ?? true) as bool;

          if (!isVisitsEnabled) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(28),
                      decoration: const BoxDecoration(color: fieldFillColor, shape: BoxShape.circle),
                      child: const Icon(Iconsax.eye_slash, color: Colors.white54, size: 50),
                    ),
                    const SizedBox(height: 18),
                    const Text("سجل المشاهدين متوقف", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
                    const SizedBox(height: 8),
                    const Text(
                      "عند إيقاف سجل المشاهدين، لن تتمكن من معرفة من زار بروفايلك ولن تظهر زياراتك عند الآخرين.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                      ),
                      onPressed: () async {
                        await FirebaseFirestore.instance.collection('users').doc(myId).update({'isVisitsEnabled': true});
                      },
                      child: const Text("تفعيل سجل المشاهدين", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    )
                  ],
                ),
              ),
            );
          }

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(myId)
                .collection('visits')
                .orderBy('timestamp', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Colors.teal));
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(25),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha:0.05), shape: BoxShape.circle),
                        child: const Icon(Iconsax.eye_slash, color: Colors.white24, size: 45),
                      ),
                      const SizedBox(height: 15),
                      const Text("لا يوجد زوار بعد", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 5),
                      Text("لما حدا يزور بروفايلك رح يظهر هون", style: TextStyle(color: Colors.white.withValues(alpha:0.4), fontSize: 13)),
                    ],
                  ),
                );
              }

              final visits = snapshot.data!.docs;

              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: visits.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final visitDoc = visits[index];
                  final data = visitDoc.data() as Map<String, dynamic>;
                  final visitorId = data['visitorId'];
                  final ts = data['timestamp'] as Timestamp?;

                  return FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance.collection('users').doc(visitorId).get(),
                    builder: (context, userSnap) {
                      if (!userSnap.hasData) return const SizedBox();
                      if (!userSnap.data!.exists) return const SizedBox();
                      final userData = userSnap.data!.data() as Map<String, dynamic>;
                      final name = userData['fullName'] ?? 'مستخدم';
                      final photo = userData['profileImg'] ?? '';
                      final username = userData['username'] ?? '';

                      return Container(
                        decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(14)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          leading: CircleAvatar(
                            radius: 24,
                            backgroundColor: Colors.teal.withValues(alpha:0.2),
                            backgroundImage: photo.isNotEmpty ? CachedNetworkImageProvider(photo) : null,
                            child: photo.isEmpty ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white)) : null,
                          ),
                          title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                          subtitle: Text("@$username • ${_formatTime(ts)}", style: const TextStyle(color: Colors.white38, fontSize: 12)),
                          // ⭐ التعديل الوحيد هنا: زر الحالة + زر الحذف القديم
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildFollowStatusButton(visitorId),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Iconsax.close_circle, color: Colors.white24, size: 20),
                                onPressed: () => visitDoc.reference.delete(),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: visitorId)));
                          },
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}