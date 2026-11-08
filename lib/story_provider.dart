import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'r2_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'auth_provider.dart' as custom;

class StoryProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
    final R2Service _r2 = R2Service();

  // متغير للـ progress - تقدر تستخدمه بالـ UI
  double uploadProgress = 0.0;

  // رفع ستوري جديد - نفس منطق PostProvider
  Future<String?> uploadStory({
    required File file,
    required bool isVideo,
    required custom.AuthProvider auth,
    String? thumbnailPath, // <-- 1. ضفنا الباراميتر الجديد
  }) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return null;

      // بيانات المستخدم من auth_provider
      final String username = auth.username?? 'user';
      final String fullName = auth.fullName?? 'مستخدم جديد';
      final String profileImg = auth.profileImg?? '';

      // اسم الملف مثل post_provider
      final String storyId = DateTime.now().millisecondsSinceEpoch.toString();
      final String extension = isVideo? 'mp4' : 'jpg';
      final String folder = isVideo? 'videos' : 'images';

            // مسار R2
      final String storagePath = 'stories/$uid/$folder/$storyId.$extension';
      File fileToUpload = file;

      // ضغط الفيديو إذا كان فيديو
      if (isVideo) {
        try {
          uploadProgress = 0.0;
          notifyListeners();
          final MediaInfo? info = await VideoCompress.compressVideo(
            file.path,
            quality: VideoQuality.MediumQuality,
            deleteOrigin: false,
            includeAudio: true,
          );
          if (info?.file!= null) {
            fileToUpload = File(info!.file!.path);
          }
        } catch (e) {
          fileToUpload = file;
        }
      }

      // رفع الملف بدون بروغرس حقيقي للسرعة
      uploadProgress = 0.5;
      notifyListeners();
      final String mediaUrl = await _r2.uploadFile(fileToUpload, storagePath);
      uploadProgress = 0.9;
      notifyListeners();

      // ✅ توليد/رفع thumbnail للفيديو - معدل
      String? thumbnailUrl;
      if (isVideo) {
        try {
          Uint8List? thumbData;

          // 2. لو انبعت thumbnailPath من MediaPreviewScreen استخدمه، وإلا ولده
          if (thumbnailPath!= null && File(thumbnailPath).existsSync()) {
            debugPrint('Tini: استخدام thumbnail جاهز من MediaPreviewScreen');
            thumbData = await File(thumbnailPath).readAsBytes();
          } else {
            debugPrint('Tini: توليد thumbnail جديد');
            thumbData = await VideoThumbnail.thumbnailData(
              video: fileToUpload.path,
              imageFormat: ImageFormat.JPEG,
              maxWidth: 720,
              quality: 75,
            );
          }

                    if (thumbData!= null) {
            final String thumbPath = 'stories/$uid/thumbnails/$storyId.jpg';
            // نحفظ مؤقتا ثم نرفع للـ R2
            final tempDir = await File(thumbData as dynamic).parent;
            // اسهل حل: اكتب البيانات لملف مؤقت وارفعه
            final thumbFile = File('${fileToUpload.parent.path}/thumb_$storyId.jpg');
            await thumbFile.writeAsBytes(thumbData);
            thumbnailUrl = await _r2.uploadFile(thumbFile, thumbPath);
            try { await thumbFile.delete(); } catch(_){}
            debugPrint('تم رفع thumbnail للـ R2');
          }
        } catch (e) {
          debugPrint('فشل thumbnail: $e');
        }
      }

      // تنظيف ملف الضغط المؤقت
      if (isVideo && fileToUpload.path!= file.path) {
        try {
          await VideoCompress.deleteAllCache();
        } catch (_) {}
      }

      // إعادة تعيين التقدم
      uploadProgress = 0.0;
      notifyListeners();

            // حفظ في Firestore - بنية stories/uid/items/storyId
      await _firestore
         .collection('stories')
         .doc(uid)
         .collection('items')
         .doc(storyId)
         .set({
        'mediaUrl': mediaUrl,
        'thumbnailUrl': thumbnailUrl ?? '',
        'type': isVideo ? 'video' : 'image',
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(hours: 24)),
        ),
        'views': [],
        'viewedBy': [],
        'uid': uid,
        'username': username,
        'fullName': fullName,
        'profileImg': profileImg,
      });

      // [Tini] إشعار الأصدقاء فقط - داخلي بدون Push
      _notifyFriendsAboutNewStory(uid, storyId, fullName, profileImg);

      notifyListeners();
      return storyId;
    } catch (e) {
      uploadProgress = 0.0;
      notifyListeners();
      debugPrint('Story upload error: $e');
      return null;
    }
  }

  // ✅ دالة جديدة - تسجيل المشاهدة
  Future<void> markStoryAsSeen(String ownerUid, String storyId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await _firestore
       .collection('stories')
       .doc(ownerUid)
       .collection('items')
       .doc(storyId)
       .update({
      'viewedBy': FieldValue.arrayUnion([uid]),
      'views': FieldValue.arrayUnion([uid]),
    });
  }

  // حذف ستوري
  Future<void> deleteStory(String storyId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // حذف من Firestore أولاً - يرجع فوراً للـ UI
    await _firestore
       .collection('stories')
       .doc(uid)
       .collection('items')
       .doc(storyId)
       .delete();

    notifyListeners();

        // حذف من R2 بالخلفية
    _r2.deleteByUrl('stories/$uid/videos/$storyId.mp4').catchError((_) {});
    _r2.deleteByUrl('stories/$uid/images/$storyId.jpg').catchError((_) {});
    _r2.deleteByUrl('stories/$uid/thumbnails/$storyId.jpg').catchError((_) {});
  }

  // جلب ستوريز مستخدم - مع فلتر expiresAt
  Stream<QuerySnapshot> getUserStories(String uid) {
    return _firestore
       .collection('stories')
       .doc(uid)
       .collection('items')
       .where('expiresAt', isGreaterThan: Timestamp.now())
       .orderBy('expiresAt', descending: false)
       .orderBy('createdAt', descending: true)
       .snapshots();
  }

  // جلب كل الستوريز للأشخاص اللي بتابعهم
  Stream<QuerySnapshot> getFollowingStories(List<String> followingList) {
    if (followingList.isEmpty) {
      return const Stream.empty();
    }

    // Firestore لا يدعم whereIn مع subcollections مباشرة
    // نرجع ستوريز كل واحد على حدة في الـ UI
    return _firestore
       .collectionGroup('items')
       .where('uid', whereIn: followingList.take(10).toList()) // حد أقصى 10
       .where('expiresAt', isGreaterThan: Timestamp.now())
       .orderBy('expiresAt')
       .orderBy('createdAt', descending: true)
       .snapshots();
  }
    // [Tini] إشعار الأصدقاء عند نشر ستوري - متابعة متبادلة فقط + Throttle ساعة
      // [Tini] إشعار الأصدقاء عند نشر ستوري - متابعة متبادلة فقط
  Future<void> _notifyFriendsAboutNewStory(String myUid, String storyId, String myName, String myImg) async {
    try {
      final followingSnap = await _firestore.collection('users').doc(myUid).collection('following').get();
      final followersSnap = await _firestore.collection('users').doc(myUid).collection('followers').get();

      final friendsIds = followingSnap.docs.map((d) => d.id).toSet().intersection(followersSnap.docs.map((d) => d.id).toSet());
      if (friendsIds.isEmpty) return;

      for (final friendUid in friendsIds) {
        await _firestore.collection('activities').add({
          'toUid': friendUid,
          'fromUid': myUid,
          'type': 'story_new',
          'text': '$myName نشر قصة',
          'postId': storyId,
          'timestamp': FieldValue.serverTimestamp(),
          'seen': false,
        });
      }
    } catch (e) {
      debugPrint('notify friends error: $e');
    }
  }
}