import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// [Tini]: Hashtag Service (نسخة مدمجة ومستقرة + تحديث تلقائي)
class HashtagService {
  static final HashtagService _instance = HashtagService._internal();
  factory HashtagService() => _instance;
  HashtagService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// [لشاشة العرض]: معالجة الضغط على الهاشتاق
  void handleHashtagTap(BuildContext context, String hashtag) {
    final String cleanTag = hashtag.replaceAll('#', '').trim().toLowerCase();
    debugPrint("Tini: الانتقال إلى صفحة الهاشتاق: $cleanTag");
    // سيتم تفعيل الـ Navigator هنا فور إنشاء شاشة النتائج
  }

  /// [لشاشة النشر]: استخراج الهاشتاقات من النص قبل الرفع
  /// هذه الدالة هي المحرك الذي يحول النص إلى بيانات مرتبة في Firestore
  List<String> extractHashtags(String text) {
    if (text.isEmpty) return [];
    // تعبير برمجى (Regex) لالتقاط الكلمات التي تبدأ بـ # وتجنب الرموز الخاصة
    final RegExp hashtagRegExp = RegExp(r"#[^\s!@#$%^&*()=+.\/,\[\]{\}:;?><]+");
    Iterable<Match> matches = hashtagRegExp.allMatches(text);
    // نرجعهم بدون # وبأحرف صغيرة عشان البحث
    return matches.map((match) => match.group(0)!.replaceAll('#', '').toLowerCase()).toList();
  }

  /// [جديد ومهم] تحديث جدول الهاشتاقات بعد رفع الفيديو
  /// لازم تستدعي هاي الدالة بعد ما ترفع البوست بنجاح
  Future<void> updateHashtagsCollection(List<String> hashtags) async {
    if (hashtags.isEmpty) return;

    final WriteBatch batch = _firestore.batch();

    for (String tag in hashtags) {
      final String tagLower = tag.toLowerCase().trim();
      if (tagLower.isEmpty) continue;

      final DocumentReference hashtagRef = _firestore.collection('hashtags').doc(tagLower);

      // نستخدم set مع merge عشان اذا موجود يزيد العداد، واذا جديد يعمله
      batch.set(hashtagRef, {
        'name': tag, // نحفظ الاسم الأصلي للعرض
        'name_lowercase': tagLower, // للبحث
        'count': FieldValue.increment(1), // زيادة العداد تلقائي
        'lastUsed': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    try {
      await batch.commit();
      debugPrint("Tini: تم تحديث ${hashtags.length} هاشتاق بنجاح");
    } catch (e) {
      debugPrint("Tini: خطأ بتحديث الهاشتاقات: $e");
    }
  }

  /// [لشاشة النتائج]: جلب المنشورات المرتبطة بهاشتاق معين
  Stream<QuerySnapshot> getPostsByHashtag(String hashtag) {
    final String cleanTag = hashtag.replaceAll('#', '').trim().toLowerCase();
    return _firestore
        .collection('posts')
        .where('hashtags_lowercase', arrayContains: cleanTag) // [تعديل البحث]
        .orderBy('createdAt', descending: true)
        .snapshots();
  }
}