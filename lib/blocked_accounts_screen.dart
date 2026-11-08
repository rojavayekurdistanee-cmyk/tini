import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'auth_provider.dart' as custom;

/*
  [Tini Project Rules]:
    1. File Name: blocked_accounts_screen.dart
    2. Concept: Blocked Accounts List - TikTok Style with Titi Colors
    3. UI Style: Dark Surface 0xFF1A222C, Bg 0xFF0F1720, Teal Accent
    4. Logic: users/{myUid}/blocked subcollection
*/

class BlockedAccountsScreen extends StatefulWidget {
  const BlockedAccountsScreen({super.key});

  @override
  State<BlockedAccountsScreen> createState() => _BlockedAccountsScreenState();
}

class _BlockedAccountsScreenState extends State<BlockedAccountsScreen> {
  final Color bgColor = const Color(0xFF0F1720);
  final Color surfaceColor = const Color(0xFF1A222C);
  final Color titiTeal = Colors.teal;

  Future<void> _unblockUser(String blockedUid, {String fullName = "مستخدم"}) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;

    // [Two-Way لحظي] امسح من الذاكرة فورا قبل الفايربيس
    if (mounted) {
      try {
        final auth = Provider.of<custom.AuthProvider>(context, listen: false);
        auth.removeFromBlockedLocally(blockedUid);
      } catch (_) {}
    }

    try {
      await FirebaseFirestore.instance.collection('users').doc(myUid).collection('blocked').doc(blockedUid).delete();

      await FirebaseFirestore.instance.collection('users').doc(myUid).set({
        'blockedUsers': FieldValue.arrayRemove([blockedUid]),
        'blocked': FieldValue.arrayRemove([blockedUid]),
      }, SetOptions(merge: true));

      // [الاصلاح الذهبي] احذف blockedBy من عند الطرف التاني - هاد اللي مخلي فيديوهاتك ما تطلع عنده بعد فك الحظر
      await FirebaseFirestore.instance.collection('users').doc(blockedUid).collection('blockedBy').doc(myUid).delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("تم إلغاء حظر $fullName"),
            backgroundColor: Colors.teal,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(myUid).collection('blocked').doc(blockedUid).delete();
        await FirebaseFirestore.instance.collection('users').doc(blockedUid).collection('blockedBy').doc(myUid).delete();
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("تم إلغاء حظر $fullName"),
            backgroundColor: Colors.teal,
          ),
        );
      }
    }
  }

  Future<void> _unblockAll(List<QueryDocumentSnapshot> blockedDocs) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null || blockedDocs.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1A222C),
        title: const Text('إلغاء حظر الجميع؟', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('هل تريد إلغاء حظر ${blockedDocs.length} حساب؟', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('تأكيد', style: TextStyle(color: Color(0xFFFF3B30)))),
        ],
      ),
    );

    if (confirm!= true) return;

    // [Two-Way لحظي] امسح الكل من الذاكرة فورا
    if (mounted) {
      try {
        final auth = Provider.of<custom.AuthProvider>(context, listen: false);
        for (var doc in blockedDocs) {
          auth.removeFromBlockedLocally(doc.id);
        }
      } catch (_) {}
    }

    for (var doc in blockedDocs) {
      final String blockedUid = doc.id;
      try {
        await FirebaseFirestore.instance.collection('users').doc(myUid).collection('blocked').doc(blockedUid).delete();
        await FirebaseFirestore.instance.collection('users').doc(myUid).set({
          'blockedUsers': FieldValue.arrayRemove([blockedUid]),
          'blocked': FieldValue.arrayRemove([blockedUid]),
        }, SetOptions(merge: true));
        await FirebaseFirestore.instance.collection('users').doc(blockedUid).collection('blockedBy').doc(myUid).delete();
      } catch (_) {}
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("تم إلغاء حظر الجميع"),
          backgroundColor: Colors.teal,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid?? "";

    // [إصلاح 2] حماية لو مو مسجل دخول
    if (myUid.isEmpty) {
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
            "الحسابات المحظورة",
            style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 60, color: Colors.white24),
              const SizedBox(height: 15),
              const Text("سجل دخول أولاً", style: TextStyle(color: Colors.white54, fontSize: 15)),
            ],
          ),
        ),
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
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "الحسابات المحظورة",
          style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        // [إصلاح 1] شلنا orderBy blockedAt - ما عاد يعلق لو الحقل مو موجود
        stream: FirebaseFirestore.instance
          .collection('users')
          .doc(myUid)
          .collection('blocked')
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
                  Icon(Icons.block, size: 60, color: Colors.white24),
                  const SizedBox(height: 15),
                  const Text("لا يوجد حسابات محظورة", style: TextStyle(color: Colors.white54, fontSize: 15)),
                ],
              ),
            );
          }

          final blockedDocs = snapshot.data!.docs;
          // [إصلاح 1] Sort بالكود بدل orderBy - يتحمل null
          blockedDocs.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aTime = aData['blockedAt'] as Timestamp?;
            final bTime = bData['blockedAt'] as Timestamp?;
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return bTime.compareTo(aTime);
          });

          return Column(
            children: [
              // [جديد] زر إلغاء حظر الكل
              if (blockedDocs.length > 1)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      GestureDetector(
                        onTap: () => _unblockAll(blockedDocs),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Text(
                            "إلغاء حظر الكل (${blockedDocs.length})",
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: ListView.separated(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: blockedDocs.length,
                    separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1, indent: 20, endIndent: 20),
                    itemBuilder: (context, index) {
                      final data = blockedDocs[index].data() as Map<String, dynamic>;
                      final String blockedUid = blockedDocs[index].id;
                      final String fullName = data['fullName']?? data['username']?? "مستخدم";
                      final String username = data['username']?? "user";
                      final String profileImg = data['profileImg']?? "";

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: () => _unblockUser(blockedUid, fullName: fullName),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white10,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: const Text(
                                  "إلغاء الحظر",
                                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    fullName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    "@$username",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            profileImg.isNotEmpty
                              ? CachedNetworkImage(
                                    imageUrl: profileImg,
                                    imageBuilder: (context, imageProvider) => CircleAvatar(
                                      radius: 28,
                                      backgroundImage: imageProvider,
                                      backgroundColor: Colors.white10,
                                    ),
                                    placeholder: (context, url) => const CircleAvatar(radius: 28, backgroundColor: Colors.white10),
                                    errorWidget: (context, url, error) => CircleAvatar(
                                      radius: 28,
                                      backgroundColor: Colors.white10,
                                      child: Text(fullName.isNotEmpty? fullName[0].toUpperCase() : "?", style: const TextStyle(color: Colors.white)),
                                    ),
                                  )
                                : CircleAvatar(
                                    radius: 28,
                                    backgroundColor: Colors.white10,
                                    child: Text(fullName.isNotEmpty? fullName[0].toUpperCase() : "?", style: const TextStyle(color: Colors.white)),
                                  ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}