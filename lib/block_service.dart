import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'auth_provider.dart' as custom;

/*
  [Tini Project Rules]:
    1. File Name: block_service.dart
    2. Concept: Centralized Block Logic - Reusable everywhere (Profile, Chat, etc)
    3. UI Style: Dark Surface 0xFF1A222C, Teal Accent
    4. Logic: users/{myUid}/blocked/{blockedUid} + arrays for compatibility
*/

class BlockService {
  static const Color surfaceColor = Color(0xFF1A222C);

  /// حظر مستخدم - يستخدم في كل مكان
  /// حظر مستخدم - يستخدم في كل مكان - Two Way + لحظي
  static Future<bool> blockUser(BuildContext context, String targetUid) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid?? '';
    if (myUid.isEmpty || targetUid.isEmpty) return false;
    if (myUid == targetUid) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("لا يمكنك حظر نفسك"), backgroundColor: Colors.redAccent),
        );
      }
      return false;
    }

    // تأكيد
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("تأكيد الحظر", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text("هل أنت متأكد من حظر هذا المستخدم؟ لن يتمكن من رؤية ملفك أو مراسلتك.", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("إلغاء", style: TextStyle(color: Colors.white70))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("حظر", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
        ],
      ),
    );

    if (confirm!= true) return false;

    try {
      final targetDoc = await FirebaseFirestore.instance.collection('users').doc(targetUid).get();
      final targetData = targetDoc.data()?? {};

      final String fullName = targetData['fullName']?? targetData['username']?? 'مستخدم';
      final String username = targetData['username']?? 'user';
      final String profileImg = targetData['profileImg']?? '';

      // [لحظي مركزي] - تحديث Set قبل الفايربيز
      try {
        if (context.mounted) {
          final auth = Provider.of<custom.AuthProvider>(context, listen: false);
          auth.blockedUsersSet.add(targetUid);
          auth.blockedUsers.add(targetUid);
        }
      } catch (_) {}

      // 1. إضافة إلى subcollection
      await FirebaseFirestore.instance.collection('users').doc(myUid).collection('blocked').doc(targetUid).set({
        'uid': targetUid,
        'fullName': fullName,
        'username': username,
        'profileImg': profileImg,
        'blockedAt': FieldValue.serverTimestamp(),
      });

      // 2. arrays للتوافق
      await FirebaseFirestore.instance.collection('users').doc(myUid).set({
        'blockedUsers': FieldValue.arrayUnion([targetUid]),
        'blocked': FieldValue.arrayUnion([targetUid]),
      }, SetOptions(merge: true));

      // 3. [مهم - حل مشكلة الفيد] اكتب عند الطرف الثاني انه انحظر - مشان فيديوهاتك ما تطلع عنده بالـ For You / رائج
      try {
        await FirebaseFirestore.instance.collection('users').doc(targetUid).collection('blockedBy').doc(myUid).set({
          'by': myUid,
          'blockedByAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}

      // 4. إلغاء المتابعة
      try {
        await FirebaseFirestore.instance.collection('users').doc(myUid).collection('following').doc(targetUid).delete();
        await FirebaseFirestore.instance.collection('users').doc(targetUid).collection('followers').doc(myUid).delete();
      } catch (_) {}

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("تم حظر @$fullName", textAlign: TextAlign.center), backgroundColor: Colors.teal),
        );
      }
      return true;
    } catch (e) {
      debugPrint('Block error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("فشل الحظر: $e"), backgroundColor: Colors.redAccent),
        );
      }
      return false;
    }
  }

  /// إلغاء الحظر - يستخدم في شاشة الحسابات المحظورة - Two Way
  static Future<bool> unblockUser(String blockedUid, {BuildContext? context}) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return false;
    try {
      // [لحظي] امسح من الذاكرة قبل الفايربيس - مشان الفيد يرجع فورا
      if (context!= null && context.mounted) {
        try {
          final auth = Provider.of<custom.AuthProvider>(context, listen: false);
          auth.removeFromBlockedLocally(blockedUid);
        } catch (_) {}
      }

      await FirebaseFirestore.instance.collection('users').doc(myUid).collection('blocked').doc(blockedUid).delete();
      await FirebaseFirestore.instance.collection('users').doc(myUid).set({
        'blockedUsers': FieldValue.arrayRemove([blockedUid]),
        'blocked': FieldValue.arrayRemove([blockedUid]),
      }, SetOptions(merge: true));

      // [مهم جدا] امسح blockedBy من عنده - هاد اللي مخلي فيديوهاتك ما تطلع عنده
      await FirebaseFirestore.instance.collection('users').doc(blockedUid).collection('blockedBy').doc(myUid).delete();

      return true;
    } catch (e) {
      // حتى لو فشل الـ update امسح الـ docs
      try {
        await FirebaseFirestore.instance.collection('users').doc(myUid).collection('blocked').doc(blockedUid).delete();
        await FirebaseFirestore.instance.collection('users').doc(blockedUid).collection('blockedBy').doc(myUid).delete();
        if (context!= null && context.mounted) {
          try {
            final auth = Provider.of<custom.AuthProvider>(context, listen: false);
            auth.removeFromBlockedLocally(blockedUid);
          } catch (_) {}
        }
      } catch (_) {}
      return true;
    }
  }

  // ================== [Phase 2 - المنطق المركزي - Set مركزي] ==================

  // [1] فحص سريع هل محظور عندي - Set مركزي من AuthProvider
  static bool isBlockedLocal(String targetUid, Set<String> myBlockedSet) {
    if (targetUid.isEmpty) return false;
    return myBlockedSet.contains(targetUid);
  }

  // [2] isBlocked() - الدالة الأساسية - Set مركزي
  static bool isBlocked(String targetUid, Set<String> myBlockedSet) {
    if (targetUid.isEmpty) return false;
    return myBlockedSet.contains(targetUid);
  }

  // [3] فحص متزامن بدون Future - للـ UI مباشرة
  static bool isBlockedSync(String targetUid, Set<String> myBlockedSet) {
    if (targetUid.isEmpty) return false;
    return myBlockedSet.contains(targetUid);
  }

  // [4] هل البوست من شخص محظور - Set مركزي
  static bool isPostBlocked(Map<String, dynamic> postData, Set<String> myBlockedSet) {
    final uid = postData['uid']?.toString()?? '';
    if (uid.isEmpty) return false;
    return myBlockedSet.contains(uid);
  }

  // [5] فحص متبادل (أنا حاظرو أو هو حاظرني) - للبروفايل
  static Future<bool> isBlockedMutual(String targetUid) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid?? '';
    if (myUid.isEmpty || targetUid.isEmpty) return false;
    try {
      final myDoc = await FirebaseFirestore.instance.collection('users').doc(myUid).get();
      final List myBlocked = myDoc.data()?['blockedUsers']?? myDoc.data()?['blocked']?? [];
      if (myBlocked.contains(targetUid)) return true;
      final targetDoc = await FirebaseFirestore.instance.collection('users').doc(targetUid).get();
      final List targetBlocked = targetDoc.data()?['blockedUsers']?? targetDoc.data()?['blocked']?? [];
      if (targetBlocked.contains(myUid)) return true;
      return false;
    } catch (_) {
      return false;
    }
  }

  // [6] فحص هل أنا محظور عنده - للبروفايل
  static Future<bool> isBlockedByOther(String targetUid) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid?? '';
    if (myUid.isEmpty) return false;
    try {
      final targetDoc = await FirebaseFirestore.instance.collection('users').doc(targetUid).get();
      final List targetBlocked = targetDoc.data()?['blockedUsers']?? targetDoc.data()?['blocked']?? [];
      return targetBlocked.contains(myUid);
    } catch (_) {
      return false;
    }
  }

  // [7] filterBlockedUsers() - الدالة الأساسية المطلوبة - فلترة عامة لأي ليست
  static List<T> filterBlockedUsers<T>(List<T> items, Set<String> myBlockedSet, String Function(T) getUid) {
    if (myBlockedSet.isEmpty) return items;
    return items.where((item) =>!myBlockedSet.contains(getUid(item))).toList();
  }

  // [8] فلترة للـ Docs - للـ posts والـ search - Set مركزي
  static List<QueryDocumentSnapshot> filterBlockedDocs(List<QueryDocumentSnapshot> docs, Set<String> myBlockedSet) {
    if (myBlockedSet.isEmpty) return docs;
    return docs.where((d) {
      final data = d.data() as Map<String, dynamic>?;
      final uid = data?['uid']?.toString()?? '';
      return!myBlockedSet.contains(uid);
    }).toList();
  }

  // [9] فلترة Maps - للـ users search - Set مركزي
  static List<Map<String, dynamic>> filterBlockedMaps(List<Map<String, dynamic>> users, Set<String> myBlockedSet) {
    if (myBlockedSet.isEmpty) return users;
    return users.where((u) {
      final uid = u['uid']?.toString()?? u['id']?.toString()?? '';
      return!myBlockedSet.contains(uid);
    }).toList();
  }
}
