import 'user_documents.dart';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:video_compress/video_compress.dart';
import 'r2_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:gal/gal.dart';
import 'video_processor.dart';
import 'hashtag_service.dart';
import 'moderation_service.dart';
import 'mention_privacy_service.dart';
import 'audience_access.dart';

/*
  [Tini - V30.2 - Full Content Purge Edition]
  تم إضافة نظام الحذف الشامل (deletePost):
    1. حذف الملفات من Firebase Storage (الفيديو والصورة المصغرة).
    2. حذف المستند من Firestore وتحديث إجمالي إعجابات المستخدم.
    3. الحفاظ على استقرار الـ Triple Engines وكافة المميزات السابقة.
*/

class PostProvider extends ChangeNotifier {
  bool _isUploading = false;
  bool get isUploading => _isUploading;

  double _uploadProgress = 0.0;
  double get uploadProgress => _uploadProgress;

  // [Tini] A single publication task owns rendering AND upload. Its lifetime
  // belongs to PostProvider, not to the publish screen that is popped.
  bool _publicationRunning = false;
  bool _publicationRendering = false;
  String _publicationPhase = '';
  String? _publicationError;

  bool get isPublishingInBackground => _publicationRunning || _isUploading;
  String? get publicationError => _publicationError;
  String get publicationStatus => _publicationError != null
      ? 'فشل النشر: $_publicationError'
      : _publicationRunning
          ? (_isUploading && !_publicationRendering
              ? '$_publicationPhase ${(_uploadProgress * 100).toStringAsFixed(0)}%'
              : _publicationPhase)
          : _isUploading
              ? 'جاري رفع الفيديو... ${(_uploadProgress * 100).toStringAsFixed(0)}%'
              : '';
  // No fictional percentage for FFmpeg rendering (which has no progress
  // callback here). Show an indeterminate spinner until upload progress exists.
  double? get publicationProgress => _publicationRunning && _publicationRendering
      ? null : _isUploading ? _uploadProgress : null;

  /// Starts the job only once; it continues when the publish route is removed.
  /// Returns false when another upload/publication is already active.
  bool startPublication(Future<void> Function() job) {
    if (isPublishingInBackground) return false;
    _publicationRunning = true;
    _publicationRendering = true;
    _publicationPhase = 'جاري تجهيز الفيديو...';
    _publicationError = null;
    _lastUploadedPost = null;
    notifyListeners();
    _executePublication(job);
    return true;
  }

  void setPublicationPhase(String phase, {bool rendering = true}) {
    if (!_publicationRunning) return;
    _publicationPhase = phase;
    _publicationRendering = rendering;
    notifyListeners();
  }

  Future<void> _executePublication(Future<void> Function() job) async {
    // Let Navigator.popUntil restore Home before heavy processing begins.
    await Future<void>.delayed(Duration.zero);
    try {
      await job();
    } catch (error) {
      debugPrint('[Tini Publication] $error');
      _publicationError = error.toString();
    } finally {
      _publicationRunning = false;
      _publicationRendering = false;
      _publicationPhase = '';
      notifyListeners();
    }
  }

  String? _videoUrl;
  String? get videoUrl => _videoUrl;

  String _selectedLocation = "";
  String get selectedLocation => _selectedLocation;

  DocumentSnapshot? _lastUploadedPost;
  DocumentSnapshot? get lastUploadedPost => _lastUploadedPost;

  
  final Map<String, String> _fileCache = {};
  
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  int _currentViewedIndex = -1;
  int get currentViewedIndex => _currentViewedIndex;

  List<DocumentSnapshot> _currentPosts = [];
  // [Tini - Instant Open]: كاش السبلاش
  List<DocumentSnapshot> _initialPosts = [];
  List<DocumentSnapshot> get initialPosts =>
      _initialPostsViewerUid == FirebaseAuth.instance.currentUser?.uid
          ? _filterAdultPosts(_initialPosts)
          : [];
  String? _initialPostsViewerUid;
  int _splashRequestGeneration = 0;
  bool _isInitialLoaded = false;
  bool get isInitialLoaded => _isInitialLoaded;

  // --- [قطع متغيرات الهاشتاق] ---
  List<Map<String, dynamic>> _suggestedHashtags = [];
  List<Map<String, dynamic>> get suggestedHashtags => _suggestedHashtags;

    bool _isHashtagLoading = false;
  bool get isHashtagLoading => _isHashtagLoading;

  // [Tini - Block System - NEW] - عدم اقتراح القناة - ما منلمسو
  Set<String> _blockedOwnerIds = {};
  Set<String> get blockedOwnerIds => _blockedOwnerIds;

  // [Tini - HARD BLOCK - Phase 5] - الحظر الكامل من المركز AuthProvider
  Set<String> _hardBlockedIds = {};
  Set<String> get hardBlockedIds => _hardBlockedIds;

  // [Tini - Two Way - Phase 6] - ناس حاظريني - مشان فيديوهاتي ما تطلع عندهم
  Set<String> _blockedByIds = {};
  Set<String> get blockedByIds => _blockedByIds;

  // [AUDIENCE CONTROL - ADDITION] - حالة المشاهد الحالي
  final AudienceAccess _audienceAccess = AudienceAccess.instance;
  String? _audienceViewerUid = FirebaseAuth.instance.currentUser?.uid;

  PostProvider() {
    _audienceAccess.addListener(_onAudienceChanged);
    loadBlockedChannels(); // [NEW] عدم اقتراح - ما منلمسو
    _refreshCurrentViewerAdultStatus();
  }

  // [المركز] - مزامنة الحظر من AuthProvider - لحظي - Two Way
  void syncHardBlockedFromCenter(Set<String> blockedSet, {Set<String>? blockedBySet}) {
    _hardBlockedIds = blockedSet;
    if (blockedBySet != null) {
      _blockedByIds = blockedBySet;
    }
    notifyListeners();
  }

  // [Two Way] - مزامنة blockedBy لحالها
  void syncBlockedByFromCenter(Set<String> blockedBySet) {
    _blockedByIds = blockedBySet;
    notifyListeners();
  }

  


  void _onAudienceChanged() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (_audienceViewerUid != uid) {
      _audienceViewerUid = uid;
      _splashRequestGeneration++;
      _initialPosts = [];
      _currentPosts = [];
      _initialPostsViewerUid = uid;
      _isInitialLoaded = false;
      _blockedOwnerIds = {};
      loadBlockedChannels();
    }
    // Keep original candidates: a live account toggle can hide AND restore
    // ordinary posts without rewriting a post or refetching its media.
    notifyListeners();
  }

  @override
  void dispose() {
    _audienceAccess.removeListener(_onAudienceChanged);
    super.dispose();
  }

  // [ACTIVITY HELPER] - نسخة تمنع التكرار وتدعم commentId
Future<void> _logActivity(String toUid, String type, String text, String postId, {String? commentId, String? replyToCommentId}) async {
  final currentUid = FirebaseAuth.instance.currentUser?.uid ?? "";
  if (currentUid.isEmpty || currentUid == toUid) return;
  try {
    final userDoc = await UserDocuments.readable(_firestore, currentUid).get();
    final userName = userDoc.data()?['fullName'] ?? userDoc.data()?['username'] ?? 'مستخدم';
    
    // لو تعليق، خلي الـ ID فريد لكل تعليق
    String docId;
    if ((type == 'comment' || type == 'reply') && commentId != null && commentId.isNotEmpty) {
      docId = '${postId}_${currentUid}_${type}_$commentId';
    } else {
      docId = '${postId}_${currentUid}_$type';
    }
    
    await _firestore.collection('activities').doc(docId).set({
      'toUid': toUid,
      'fromUid': currentUid,
      'type': type,
      'text': '$userName $text',
      'postId': postId,
      'commentId': commentId ?? "",
      'replyToCommentId': replyToCommentId ?? "",
      'timestamp': FieldValue.serverTimestamp(),
      'seen': false,
    }, SetOptions(merge: true));
  } catch (e) {}
}

        
  
// [Tini]: جلب شارة المستخدم مع cache
final Map<String, Map<String, dynamic>> _userBadgesCache = {};

Future<Map<String, dynamic>> getUserBadge(String uid) async {
  if (_userBadgesCache.containsKey(uid)) return _userBadgesCache[uid]!;

  try {
    final doc = await UserDocuments.readable(_firestore, uid).get();
    if (!doc.exists) return {};

    final data = doc.data()!;
    final badge = data['badge'] as String?;
    final badgeEndsAt = data['badgeEndsAt'] as Timestamp?;

    // شيك إذا الشارة انتهت
    if (badgeEndsAt!= null && badgeEndsAt.toDate().isBefore(DateTime.now())) {
      return {};
    }

    final result = {'badge': badge, 'badgeEndsAt': badgeEndsAt};
    _userBadgesCache[uid] = result;
    return result;
  } catch (e) {
    return {};
  }
}

  Future<void> toggleLike(String postId, String postOwnerId) async {
    final String currentUserId = FirebaseAuth.instance.currentUser?.uid?? "";
    if (currentUserId.isEmpty) return;

    final postRef = FirebaseFirestore.instance.collection('posts').doc(postId);

    try {
      final doc = await postRef.get();
      if (!doc.exists) return;

      final postData = doc.data() as Map<String, dynamic>;
      final List<String> postHashtags = List<String>.from(postData['hashtags']?? []);
      final String actualOwnerId = postData['uid']?? postOwnerId;
      final userLikedRef = FirebaseFirestore.instance.collection('users').doc(currentUserId).collection('likedPosts').doc(postId);
      final currentUserRef = FirebaseFirestore.instance.collection('users').doc(currentUserId);
      // [Tini - Owner Reactions Overlay] - فهرس إعجابات خاص بكل فيديو، بدون كشف likedPosts الشخصية.
      final postLikeRef = postRef.collection('likes').doc(currentUserId);

      // تحميل بيانات الملف الشخصي مرة واحدة عند الضغط على الإعجاب، وليس عند تحريك كل فقاعة.
      final actorDoc = await currentUserRef.get();
      final actorData = actorDoc.data()?? {};
      final actorName = (actorData['fullName']?? actorData['username']?? 'مستخدم').toString();
      final actorImage = (actorData['profileImg']?? actorData['photoUrl']?? actorData['avatarUrl']?? '').toString();

      // [Tini - Atomic Like] - تسجيل الإعجاب وعداده وفهرس الفيديو معاً أو التراجع عنهم جميعاً.
      // تحديث إجمالي إعجابات صاحب الفيديو يتم في onPostUpdated على السيرفر حسب فارق likesCount.
      final bool isNowLiked = await FirebaseFirestore.instance.runTransaction<bool>((transaction) async {
        final latestPost = await transaction.get(postRef);
        final likedDoc = await transaction.get(userLikedRef);
        if (!latestPost.exists || latestPost.data()?['isDeleted'] == true) {
          return likedDoc.exists;
        }

        final int currentLikes = (latestPost.data()?['likesCount'] as num?)?.toInt()?? 0;
        if (likedDoc.exists) {
          transaction.delete(userLikedRef);
          transaction.delete(postLikeRef);
          transaction.update(postRef, {
            'likesCount': FieldValue.increment(currentLikes > 0? -1 : 0),
          });
          return false;
        }

        transaction.set(userLikedRef, {
          'postId': postId,
          'createdAt': FieldValue.serverTimestamp(),
          'hashtags': postHashtags, // نحفظ هاشتاغات الفيديو مع اللايك
        }, SetOptions(merge: true));
        transaction.set(postLikeRef, {
          'uid': currentUserId,
          'userName': actorName,
          'userImage': actorImage,
          'createdAt': FieldValue.serverTimestamp(),
        });
        transaction.update(postRef, {
          'likesCount': FieldValue.increment(1),
        });
        return true;
      });

      // [Titi Hashtag Interest] - نفس نقاط اهتمام الهاشتاغ السابقة، بعد نجاح العملية الذرية.
      if (postHashtags.isNotEmpty) {
        for (String tag in postHashtags) {
          String cleanTag = tag.toLowerCase().trim();
          if (cleanTag.isEmpty) continue;
          if (isNowLiked) {
            // [Titi Hashtag Interest] - زود اهتمام الهاشتاغ عند اللايك
            await currentUserRef.collection('hashtagInterests').doc(cleanTag).set({
              'name': cleanTag,
              'count': FieldValue.increment(1),
              'lastLiked': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          } else {
            // [Titi Hashtag Interest] - نقص اهتمام الهاشتاغ عند إلغاء اللايك
            await currentUserRef.collection('hashtagInterests').doc(cleanTag).set({
              'count': FieldValue.increment(-1),
              'lastLiked': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
        }
      }

      // [ACTIVITY] تسجيل إعجاب
      if (isNowLiked) {
        await _logActivity(actualOwnerId, 'like', 'أعجب بمنشورك', postId);
      }
    } catch (e) {
      debugPrint("❌ [Titi Error]: $e");
    }
  }

  // [Tini - V31 - Trash System] - الحذف المؤقت 30 يوم + الاستعادة
  Future<void> moveToTrash(String postId) async {
    final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? "";
    if (currentUserId.isEmpty) return;
    try {
      final now = DateTime.now();
      final expire = now.add(const Duration(days: 30));
      await _firestore.collection('posts').doc(postId).update({
        'isDeleted': true,
        'deletedAt': Timestamp.fromDate(now),
        'expireAt': Timestamp.fromDate(expire),
      });
      debugPrint("🗑 [Titi Trash]: تم نقل $postId للمحذوفات حتى $expire");
      notifyListeners();
    } catch (e) {
      debugPrint("🚨 [Titi Trash Error]: $e");
      rethrow;
    }
  }

  Future<void> restorePost(String postId) async {
    try {
      await _firestore.collection('posts').doc(postId).update({
        'isDeleted': FieldValue.delete(),
        'deletedAt': FieldValue.delete(),
        'expireAt': FieldValue.delete(),
      });
      debugPrint("♻️ [Titi Restore]: تمت استعادة $postId");
      notifyListeners();
    } catch (e) {
      debugPrint("🚨 [Titi Restore Error]: $e");
      rethrow;
    }
  }

  // [Titi Mechanical]: الحذف النهائي الحقيقي - يستخدم فقط من Cloud Function بعد 30 يوم
  Future<void> deletePost(String postId) async {
    final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? "";
    if (currentUserId.isEmpty) return;
    debugPrint("🚮 [Titi Purge]: بدء عملية حذف المنشور $postId...");
    try {
      final postRef = _firestore.collection('posts').doc(postId);
      final doc = await postRef.get();
      if (!doc.exists) return;
      final postData = doc.data() as Map<String, dynamic>;
      final String? videoUrl = postData['videoUrl'];
      final String? thumbUrl = postData['thumbnailUrl'];
      final int likesCount = postData['likesCount'] ?? 0;
      final String ownerId = postData['uid'] ?? "";
      final r2 = R2Service();
      if (videoUrl != null && videoUrl.isNotEmpty) {
        try { await r2.deleteByUrl(videoUrl); } catch (e) { debugPrint("⚠ R2 Video Delete Warning: $e"); }
      }
      if (thumbUrl != null && thumbUrl.isNotEmpty) {
        try { await r2.deleteByUrl(thumbUrl); } catch (e) { debugPrint("⚠ R2 Thumb Delete Warning: $e"); }
      }
      if (ownerId.isNotEmpty && likesCount > 0) {
        await _firestore.collection('users').doc(ownerId).update({
          'likes': FieldValue.increment(-likesCount)
        });
      }
      await _firestore.collection('users').doc(currentUserId).collection('favorites').doc(postId).delete();
      await _firestore.collection('users').doc(currentUserId).collection('sharedPosts').doc(postId).delete();
      await postRef.delete();
      debugPrint("✅ [Titi Purge]: تم حذف بيانات المنشور نهائياً من Firestore.");
      notifyListeners();
    } catch (e) {
      debugPrint("🚨 [Titi Error]: فشل حذف المنشور: $e");
      rethrow;
    }
  }

  // [تعديل Tini V30.3]: دالة الرفع المحدثة لدعم صمامات الأمان والخصوصية والموقع ومنطق الديو
Future<String?> uploadPost({
    required BuildContext context,
    required String videoPath,
    // True only for a completed, locally FFmpeg-encoded MP4 (never a raw input).
    bool finalVideoAlreadyEncoded = false,
    required String thumbnailPath,
    required double videoWidth,
    required double videoHeight,
    required String description,
    required String fullName,
    required String username,
    required String profileImg,
    required String uid,
    required bool ownerIsPrivateAccount, // <-- اضافة 1
    // [Titi Security]: المعاملات الجديدة المطلوبة
    required String privacy,
    String commentPrivacy = 'comment_everyone',
    required bool allowDownload,
    required bool allowDuet,
    required bool isAgeRestricted,
    required bool saveToDevice,
    required bool showWatermark,
    required List<String> mentions,
    required String songTitle,
    required String songArtist,
    required String songCover,
    required String songSource,
    // [Titi Location]: إضافة معامل الموقع
    required String location,
    List<String>? hashtags,
    String? originalAuthorName, // [إضافة فقط]
    String? originalUsername,
    // [Tini Duet]: المعاملات المضافة لدعم الديو برمجياً
    bool isDuet = false,
    String? duetFrom,
    String? duetOriginalOwnerId, // <-- جديد مشان المستقبل
  }) async {
    if (uid.isEmpty || videoPath.isEmpty) return null;

    // [Tini - Mention Privacy]: فحص أخير قبل رفع الفيديو لجهة التخزين.
    final verifiedMentionMap = await MentionPrivacyService.validateMentions(
      text: description, selected: mentions, senderUid: uid,
    );
    final verifiedMentions = verifiedMentionMap.keys.toList();

    // [Titi Moderation] فحص النص قبل الرفع: فشل الخدمة ليس موافقة.
    final descriptionCheck = await ModerationService.checkTextDetailed(description);
    if (descriptionCheck.isUnavailable) {
      throw StateError('تعذّر فحص وصف المنشور قبل الرفع. حاول مجدداً.');
    }
    if (!descriptionCheck.allowed) {
      throw Exception("المحتوى غير مسموح");
    }


    _isUploading = true;
    _uploadProgress = 0.05;
    notifyListeners();

    var compressedOriginal = false;
    DocumentReference<Map<String, dynamic>>? reservedPost;
    try {
      // 1. Compress unprocessed source videos as before. Edited videos from
      // VideoProcessor (including duet) are already H.264 MP4; a second
      // VideoCompress pass wastes CPU, heats the device and loses quality.
      // Only the publish pipeline can set finalVideoAlreadyEncoded after
      // verifying its FFmpeg output. Do not infer this from the file name.
      final sourceFile = File(videoPath);
      if (!await sourceFile.exists() || await sourceFile.length() == 0) {
        throw StateError('ملف الفيديو النهائي غير موجود أو فارغ');
      }
      File fileToUpload;
      if (finalVideoAlreadyEncoded && videoPath.toLowerCase().endsWith('.mp4')) {
        fileToUpload = sourceFile;
        debugPrint('[Tini Upload] Reusing verified FFmpeg MP4 (no second compression)');
      } else {
        final info = await VideoCompress.compressVideo(
          videoPath, quality: VideoQuality.MediumQuality);
        fileToUpload = info?.file ?? sourceFile;
        compressedOriginal = info?.file != null;
        debugPrint('[Tini Upload] Original video compression path');
      }
      if (!await fileToUpload.exists() || await fileToUpload.length() == 0) {
        throw StateError('ملف الفيديو المخصص للرفع غير موجود أو فارغ');
      }
      _uploadProgress = 0.15;
      notifyListeners();

      // 2. رفع الصورة المصغرة (Thumbnail) إلى R2
      String random4() {
        const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
        final rnd = Random();
        return String.fromCharCodes(Iterable.generate(8, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
      }

      String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      String randomSuffix = random4();

      String thumbUrl = "";
      final r2Service = R2Service();
      if (thumbnailPath.isNotEmpty) {
      String thumbName = 'thumbnails/$uid/thumb_${timestamp}_${randomSuffix}.webp';
      thumbUrl = await r2Service.uploadThumbnail(File(thumbnailPath), thumbName);
        _uploadProgress = 0.20;
        notifyListeners();
      }

      // 3. [تطوير Titi]: حجز المستند في Firestore "قبل" رفع الفيديو لضمان التزامن
      String videoFileName = '${uid}_${timestamp}_${randomSuffix}.mp4';

      // [التعديل الجوهري V30.3 Final]: كل شي في posts
      final postDocRef = FirebaseFirestore.instance
          .collection('posts')
          .doc(videoFileName);
      reservedPost = postDocRef;

                        // جلب صورة البروفايل الفريش من السيرفر مشان ما ينحفظ قديم
            String freshProfileImg = profileImg;
            try {
              final freshUserDoc = await UserDocuments.readable(FirebaseFirestore.instance, uid).get(const GetOptions(source: Source.server));
              if (freshUserDoc.exists) {
                freshProfileImg = freshUserDoc.data()?['profileImg'] ?? profileImg;
              }
            } catch (_) {}

            await postDocRef.set({
        'postId': videoFileName,
        'uid': uid,
        'ownerIsPrivateAccount': ownerIsPrivateAccount,
        'videoWidth': videoWidth,
        'videoHeight': videoHeight,
        'aspectRatio': videoWidth / videoHeight,
        'username': username,
        'fullName': fullName,
        'profileImg': freshProfileImg,
        'videoUrl': '',
        'hlsPath': '',
        // The video is not publicly ready until R2 confirms the upload.
        'processingStatus': 'uploading',
        'thumbnailUrl': thumbUrl,
        'description': description,
        'description_lowercase': description.toLowerCase(),

        "hashtags": hashtags?? [],
        'hashtags_lowercase': (hashtags?? []).map((h) => h.toLowerCase()).toList(),
        'mentions': verifiedMentions,
        // [Titi Location]: حفظ حقل الموقع في المستند
        'location': location,
        'likesCount': 0,
        'songTitle': songTitle,
        'songTitle_lowercase': songTitle.toLowerCase(),
        'songArtist': songArtist,
        'songCover': songCover,
        'songSource': songSource,
        'comments': 0,
        'shares': 0,
        'views': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'videoFileName': videoFileName,
        // [Titi Logic]: حفظ إعدادات الخصوصية المختارة من قبل المستخدم
        'privacy': privacy,
        'commentPrivacy': commentPrivacy,
        'allowDownload': allowDownload,
        'allowDuet': allowDuet,
        // The automatic content verdict is independent of the owner's live
        // audience setting. Existing unversioned posts remain conservative.
        'ageRestrictionVersion': 2,
        'isAgeRestricted': isAgeRestricted,
        'isAdultContent': isAgeRestricted,
        'audience_18plus': isAgeRestricted,
        'saveToDevice': saveToDevice,
        'showWatermark': showWatermark,
        'originalAuthorName': originalAuthorName?? "", // [إضافة فقط]
        'originalUsername': originalUsername?? "", // [إضافة فقط]
        // [Tini Duet]: تسجيل بيانات الديو في قاعدة البيانات
        'isDuet': isDuet,
        'duetFrom': duetFrom?? '',
        'duetOriginalOwnerId': duetOriginalOwnerId?? '', // <-- جديد مشان المستقبل
      }, SetOptions(merge: true)); // الالتزام بقاعدة الإضافة فقط عبر Merge

      debugPrint("📝 [Titi System]: تم حجز مستند المنشور بالمعرف المتطابق: $videoFileName");

                  // 4. رفع الفيديو إلى R2
      String objectName = 'raw_videos/$videoFileName';
      _uploadProgress = 0.30;
      notifyListeners();
      _videoUrl = await r2Service.uploadFile(
        fileToUpload,
        objectName,
        onProgress: (sentBytes, totalBytes) {
          if (totalBytes <= 0) return;
          final fraction = (sentBytes / totalBytes).clamp(0.0, 1.0);
          // Reserve the last percentage for R2 acknowledgement and Firestore.
          final progress = (0.30 + fraction * 0.64).clamp(0.30, 0.94).toDouble();
          if (progress - _uploadProgress >= 0.01 ||
              (sentBytes == totalBytes && progress > _uploadProgress)) {
            _uploadProgress = progress;
            notifyListeners();
          }
        },
      );
      _uploadProgress = 0.95;
      notifyListeners();

            // 5. تحديث المستند برابط الفيديو النهائي - مع R2 ما في تحويل HLS
      await postDocRef.update({
        'videoUrl': _videoUrl,
        'hlsPath': '', // فاضي - لان R2 ما بيعمل m3u8
        'processingStatus': 'ready',
      });
      if (hashtags != null && hashtags.isNotEmpty) {
  await HashtagService().updateHashtagsCollection(hashtags);
}

      _uploadProgress = 1.0;
      debugPrint("✅ [Titi System]: اكتمل الرفع والسيرفر سيجد المستند الآن بسهولة بالاسم: $videoFileName");

      try {
        final freshSnap = await postDocRef.get();
        if (freshSnap.exists) {
          _lastUploadedPost = freshSnap;
        }
      } catch (_) {}

      return videoFileName;

    } catch (e) {
      debugPrint("--- Upload Error: $e ---");
      // A reserved Firestore placeholder must not masquerade as a ready post.
      // If deleting the placeholder fails, mark it as failed for recovery.
      if (reservedPost != null) {
        try {
          await reservedPost.delete();
        } catch (cleanupError) {
          debugPrint('[Tini Upload] Failed to remove pending post: $cleanupError');
          try {
            await reservedPost.update({'processingStatus': 'failed'});
          } catch (_) {}
        }
      }
      rethrow; // PostProvider reports the actual failure on Home.
    } finally {
      _isUploading = false;
      _uploadProgress = 0.0;
      if (compressedOriginal) {
        VideoCompress.deleteAllCache();
      }
      notifyListeners();
    }
  }

  Stream<QuerySnapshot> getLikedPostsIdsStream(String userId) {
    if (userId.isEmpty) return const Stream.empty();
    return FirebaseFirestore.instance
      .collection('users')
      .doc(userId)
      .collection('likedPosts')
      .orderBy('createdAt', descending: true)
      .snapshots();
  }

  

  Future<void> toggleFavorite(String postId) async {
    final String currentUserId = FirebaseAuth.instance.currentUser?.uid?? "";
    if (currentUserId.isEmpty) return;

    final favRef = FirebaseFirestore.instance.collection('users').doc(currentUserId).collection('favorites').doc(postId);
    final postRef = FirebaseFirestore.instance.collection('posts').doc(postId);
    final currentUserRef = FirebaseFirestore.instance.collection('users').doc(currentUserId);

    try {
      final doc = await favRef.get();
      final postDoc = await postRef.get();
      List<String> postHashtags = [];
      if (postDoc.exists) {
        postHashtags = List<String>.from((postDoc.data() as Map<String, dynamic>)['hashtags']?? []);
      }

      if (doc.exists) {
        await favRef.delete();
        if (postDoc.exists) {
          final postData = postDoc.data() as Map<String, dynamic>;
          int currentCount = postData['favoritesCount']?? 0;
          await postRef.update({'favoritesCount': currentCount <= 0? 0 : FieldValue.increment(-1)});
        }
        for (String tag in postHashtags) {
          String cleanTag = tag.toLowerCase().trim();
          if (cleanTag.isEmpty) continue;
          await currentUserRef.collection('hashtagInterests').doc(cleanTag).set({
            'count': FieldValue.increment(-2),
            'lastLiked': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      } else {
        if (postDoc.exists) {
          final postData = postDoc.data() as Map<String, dynamic>;
          await favRef.set({
            'postId': postId,
            'videoUrl': postData['videoUrl']?? '',
            'hlsPath': postData['hlsPath']?? '',
            'processingStatus': postData['processingStatus']?? 'ready',
            'thumbnailUrl': postData['thumbnailUrl']?? '',
            'username': postData['username']?? 'User',
            'fullName': postData['fullName']?? '',
            'profileImg': postData['profileImg']?? '',
            'description': postData['description']?? '',
            'views': postData['views']?? 0,
            'likesCount': postData['likesCount']?? 0,
            'savedAt': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          await postRef.update({'favoritesCount': FieldValue.increment(1)});
          for (String tag in postHashtags) {
            String cleanTag = tag.toLowerCase().trim();
            if (cleanTag.isEmpty) continue;
            await currentUserRef.collection('hashtagInterests').doc(cleanTag).set({
              'name': cleanTag,
              'count': FieldValue.increment(2),
              'lastLiked': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
          final ownerId = postData['uid']?? '';
          await _logActivity(ownerId, 'favorite', 'حفظ منشورك', postId);
        }
      }
      Future.microtask(() { notifyListeners(); });
    } catch (e) {
      debugPrint("❌ [Favorite Error]: $e");
    }
  }

  Future<void> sharePost(String postId) async {
    print("🚀 [Titi Debug]: تم ضغط زر المشاركة للمنشور: $postId");
    final String currentUserId = FirebaseAuth.instance.currentUser?.uid?? "";
    if (currentUserId.isEmpty) {
      print("⚠ [Titi Debug]: فشل العملية - المستخدم غير مسجل دخول (UID فارغ)");
      return;
    }
    print("👤 [Titi Debug]: UID المستخدم الحالي: $currentUserId");
    final postRef = FirebaseFirestore.instance.collection('posts').doc(postId);
    final shareRef = FirebaseFirestore.instance.collection('users').doc(currentUserId).collection('sharedPosts').doc(postId);
    final currentUserRef = FirebaseFirestore.instance.collection('users').doc(currentUserId);
    try {
      print("🔎 [Titi Debug]: جاري التحقق من وجود المنشور في مجلد sharedPosts...");
      final shareDoc = await shareRef.get();
      final postDoc = await postRef.get();
      List<String> postHashtags = [];
      if (postDoc.exists) {
        postHashtags = List<String>.from((postDoc.data() as Map<String, dynamic>)['hashtags']?? []);
      }
      if (shareDoc.exists) {
        print("🗑 [Titi Debug]: المنشور موجود مسبقاً. جاري تنفيذ (إلغاء المشاركة)...");
        await postRef.update({'shares': FieldValue.increment(-1)});
        print("📉 [Titi Debug]: تم إنقاص العداد من منشور posts الرئيسي.");
        await shareRef.delete();
        print("✅ [Titi Debug]: تم حذف المنشور من مجلد sharedPosts.");
        for (String tag in postHashtags) {
          String cleanTag = tag.toLowerCase().trim();
          if (cleanTag.isEmpty) continue;
          await currentUserRef.collection('hashtagInterests').doc(cleanTag).set({
            'count': FieldValue.increment(-3),
            'lastLiked': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      } else {
        print("➕ [Titi Debug]: المنشور غير موجود. جاري تنفيذ (إضافة مشاركة)...");
        if (postDoc.exists) {
          print("📄 [Titi Debug]: تم العثور على بيانات المنشور الأصلي.");
          final postData = postDoc.data() as Map<String, dynamic>;
          await postRef.update({'shares': FieldValue.increment(1)});
          print("📈 [Titi Debug]: تم زيادة العداد في منشور posts الرئيسي.");
          await shareRef.set({
            'postId': postId,
            'videoUrl': postData['videoUrl']?? '',
            'hlsPath': postData['hlsPath']?? '',
            'thumbnailUrl': postData['thumbnailUrl']?? '',
            'username': postData['username']?? 'User',
            'fullName': postData['fullName']?? '',
            'profileImg': postData['profileImg']?? '',
            'description': postData['description']?? '',
            'likesCount': postData['likesCount']?? 0,
            'comments': postData['comments']?? 0,
            'favoritesCount': postData['favoritesCount']?? 0,
            'shares': (postData['shares']?? 0) + 1,
            'sharedAt': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          print("✅ [Titi Debug]: تم حفظ النسخة في مجلد sharedPosts بنجاح.");
          for (String tag in postHashtags) {
            String cleanTag = tag.toLowerCase().trim();
            if (cleanTag.isEmpty) continue;
            await currentUserRef.collection('hashtagInterests').doc(cleanTag).set({
              'name': cleanTag,
              'count': FieldValue.increment(3),
              'lastLiked': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
          final ownerId = postData['uid']?? '';
          await _logActivity(ownerId, 'share', 'شارك منشورك', postId);
        } else {
          print("❌ [Titi Debug]: خطأ - المنشور الأصلي غير موجود في مجموعة posts!");
        }
      }
      notifyListeners();
      print("🔔 [Titi Debug]: تم إرسال notifyListeners لتحديث الواجهة.");
    } catch (e) {
      print("🚨 [Titi Debug] خطأ قاتل أثناء العملية: $e");
    }
  }

Stream<bool> isSharedStream(String postId) {
  final String uid = FirebaseAuth.instance.currentUser?.uid ?? "";
  if (uid.isEmpty) {
    return Stream.value(false);
  }
  return FirebaseFirestore.instance
    .collection('users')
    .doc(uid)
       .collection('sharedPosts')
       .doc(postId)
       .snapshots()
       .map((snap) => snap.exists)
       .distinct();
  }

  Stream<bool> isFavoriteStream(String postId) {
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    if (uid.isEmpty) {
      return Stream.value(false);
    }
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .doc(postId)
        .snapshots()
        .map((snap) => snap.exists);
  }

  Stream<QuerySnapshot> getFavoritesStream(String userId) {
    if (userId.isEmpty) return const Stream.empty();
    return FirebaseFirestore.instance
       .collection('users')
       .doc(userId)
       .collection('favorites')
       .orderBy('savedAt', descending: true)
       .snapshots();
  }

  Stream<QuerySnapshot> getSharedPostsStream(String userId) {
    if (userId.isEmpty) return const Stream.empty();
    return FirebaseFirestore.instance
       .collection('users')
       .doc(userId)
       .collection('sharedPosts')
       .orderBy('sharedAt', descending: true)
       .snapshots();
  }

  Future<void> addToWatchHistory(
    String postId,
    Map<String, dynamic> postData, {
    required String viewerUid,
  }) async {
    if (FirebaseAuth.instance.currentUser?.uid != viewerUid) return;
    try {
      final ref = _firestore.collection('users').doc(viewerUid)
          .collection('watchHistory').doc(postId);
      await ref.set({
        'postId': postId,
        'thumbnailUrl': postData['thumbnailUrl'] ?? '',
        'videoUrl': postData['videoUrl'] ?? '',
        'hlsPath': postData['hlsPath'] ?? '',
        'views': postData['views'] ?? 0,
        'likesCount': postData['likesCount'] ?? 0,
        'uid': postData['uid'] ?? '',
        'username': postData['username'] ?? '',
        'fullName': postData['fullName'] ?? '',
        'isAdultContent': postData['isAdultContent'] ?? false,
        'audience_18plus': postData['audience_18plus'] ?? false,
        'watchedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("WatchHistory Error: $e");
    }
  }

  Future<void> incrementView(String postId) async {
    try {
      await _firestore.collection('posts').doc(postId).update({
        'views': FieldValue.increment(1),
      });
    } catch (e) {
      debugPrint("❌ [Titi Error]: فشل تحديث عداد العين: $e");
    }
  }

  Stream<DocumentSnapshot> getPostLiveStream(String postId) {
    return _firestore.collection('posts').doc(postId).snapshots();
  }
  // [Titi Mechanical]: محرك تنزيل الفيديوهات الذكي لـ Tini مع العلامة المائية الإلزامية
  Future<void> downloadVideo(Map<String, dynamic> postData) async {
    try {
      // 1. استخراج الرابط الصحيح (نفضل الـ MP4 الأصلي للتنزيل)
      // سنحاول جلب الرابط من videoUrl (الذي رأيناه في الصورة 5 ينتهي بـ.mp4)
      String? downloadUrl = postData['videoUrl'];
      String postId = postData['id']?? DateTime.now().millisecondsSinceEpoch.toString();

      if (downloadUrl == null || downloadUrl.contains('.m3u8')) {
        // إذا كان videoUrl هو رابط HLS، سنبحث عن رابط الـ raw فيديو إذا توفر
        // أو نُعلم المستخدم أن هذا النوع من البث لا يدعم التنزيل المباشر حالياً
        debugPrint("⚠ [Titi Download]: الرابط الحالي HLS، نحتاج لرابط MP4 للتنزيل.");
        return;
      }

      // 2. طلب الأذونات (Storage & Photos)
      PermissionStatus status = await Permission.storage.request();
      if (!status.isGranted) status = await Permission.photos.request();

      if (status.isGranted) {
        debugPrint("📥 [Titi Download]: بدء التحميل من الرابط المباشر...");

        final tempDir = await getTemporaryDirectory();
        final String tempPath = "${tempDir.path}/titi_star_$postId.mp4";

        // 3. التحميل الفعلي
        await Dio().download(
          downloadUrl,
          tempPath,
          onReceiveProgress: (count, total) {
            if (total!= -1) {
              double progress = (count / total * 100);
              debugPrint("⏳ [Titi Download]: تم تحميل ${progress.toStringAsFixed(0)}%");
            }
          },
        );

        // [Tini - إضافة معالج العلامة المائية الإجباري قبل الحفظ]:
        debugPrint("🎨 [Titi Download]: جاري دمج العلامة المائية الاحترافية...");
        String ownerUsername = postData['username']?? 'user';

        // استدعاء الدالة المعتمدة من كلاس المعالج لطباعة الحقوق
        final String? watermarkedPath = await VideoProcessor.createSaveableVideoWithWatermark(
          inputPath: tempPath,
          username: ownerUsername,
        );

        // 4. الحفظ في الاستوديو (استخدام ملف الحقوق إذا نجحت العملية، أو الملف الأصلي كصمام أمان)
        final String finalPathToSave = (watermarkedPath!= null && watermarkedPath.isNotEmpty)
           ? watermarkedPath
            : tempPath;

        await Gal.putVideo(finalPathToSave);
        debugPrint("✅ [Titi Download]: الفيديو الآن في معرض الصور.");

        // [ACTIVITY] تسجيل تنزيل
        final ownerId = postData['uid']?? '';
        await _logActivity(ownerId, 'download', 'نزّل فيديوك', postId);
      } else {
        debugPrint("🚫 [Titi Download]: العميل رفض إذن الوصول.");
      }
    } catch (e) {
      debugPrint("🚨 [Titi Error]: فشل محرك التنزيل: $e");
      rethrow;
    }
  }
  List<String> _extractHashtags(String text) {
    final RegExp hashtagRegExp = RegExp(r'#(\w+)');
    final Iterable<RegExpMatch> matches = hashtagRegExp.allMatches(text);
    return matches.map((m) => m.group(1)!).toList();
  }
  Future<void> _processHashtags(String description) async {
    List<String> tags = _extractHashtags(description);
    for (String tag in tags) {
      final docRef = FirebaseFirestore.instance.collection('hashtags').doc(tag);
      await docRef.set({
        'name': tag,
        'name_lowercase': tag.toLowerCase(), // [إضافة البحث]
        'count': FieldValue.increment(1), // ينشئ المجموعة والمستند أو يزيد العداد تلقائياً
        'lastUsed': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }
  Future<void> searchHashtags(String query) async {
    if (query.isEmpty || !query.contains('#')) {
      _suggestedHashtags = [];
      notifyListeners();
      return;
    }

    String cleanQuery = query.split('#').last.trim().toLowerCase();

    // [التعديل هنا] إذا كان المستخدم حاطط # بس ولسه ما كتب حروف
    if (cleanQuery.isEmpty) {
      // نعرض له هاشتاجات مشهورة فوراً بدل ما نعمل return
      _suggestedHashtags = [
        {'name': 'تيتي_ستار', 'count': '1.2M'},
        {'name': 'لايف', 'count': '850K'},
        {'name': 'اكسبلور', 'count': '2.5M'},
      ];
      _isHashtagLoading = false;
      notifyListeners();
      return; // نخرج بعد ما عرضنا المشهور
    }

    // إذا بدأ يكتب حروف، نكمل البحث في Firestore كالمعتاد
    _isHashtagLoading = true;
    notifyListeners();

    try {
      final snapshot = await FirebaseFirestore.instance
         .collection('hashtags')
         .where('name_lowercase', isGreaterThanOrEqualTo: cleanQuery)
         .where('name_lowercase', isLessThanOrEqualTo: '$cleanQuery\uf8ff')
         .limit(10).get();

      _suggestedHashtags = snapshot.docs.map((doc) => {
        'name': doc['name'],
        'count': doc['count']
      }).toList();
    } catch (e) {
      debugPrint("Error: $e");
    }

    _isHashtagLoading = false;
    notifyListeners();
  }

void updateLocation(String location) {
  _selectedLocation = location;
  notifyListeners();
}
// [Tini Update]: دالة مسح الموقع المختار للتراجع عن النشر
  void clearLocation() {
    _selectedLocation = ""; // تصفير المتغير
    notifyListeners(); // إرسال إشارة للواجهة لتحديث نفسها فوراً
    debugPrint("📍 [Titi System]: تم إزالة الموقع المختار.");
  }

  // [Tini - Block System - NEW] - عدم اقتراح القناة - ما منلمسو
  Future<void> loadBlockedChannels() async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;
    try {
      final snap = await _firestore.collection('users').doc(myUid).collection('blockedChannels').get();
      if (FirebaseAuth.instance.currentUser?.uid != myUid) return;
      _blockedOwnerIds = snap.docs.map((d) => d.id).toSet();
      notifyListeners();
    } catch (e) {}
  }

   // [Tini - Instant Open]: كاش اولاً 0 ثانية بعدين سيرفر
  Future<void> fetchInitialPostsForSplash() async {
    final viewerUid = FirebaseAuth.instance.currentUser?.uid;
    if (_initialPostsViewerUid == viewerUid &&
        _isInitialLoaded && _initialPosts.isNotEmpty) return;
    final generation = ++_splashRequestGeneration;
    bool isCurrentRequest() => generation == _splashRequestGeneration &&
        FirebaseAuth.instance.currentUser?.uid == viewerUid;
    try {
      await _refreshCurrentViewerAdultStatus();
      if (!isCurrentRequest()) return;
      final cacheSnap = await _firestore.collection('posts').orderBy('createdAt', descending: true).limit(10).get(const GetOptions(source: Source.cache));
      if (!isCurrentRequest()) return;
      if (cacheSnap.docs.isNotEmpty) {
        _initialPosts = cacheSnap.docs;
        _initialPostsViewerUid = viewerUid;
        _currentPosts = _initialPosts;
        _isInitialLoaded = true;
        notifyListeners();
      }
      final serverSnap = await _firestore.collection('posts').orderBy('createdAt', descending: true).limit(10).get(const GetOptions(source: Source.server));
      if (!isCurrentRequest()) return;
      _initialPosts = serverSnap.docs;
      _initialPostsViewerUid = viewerUid;
      _currentPosts = _initialPosts;
      _isInitialLoaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint("Splash fetch error: $e");
    }
  }

  Future<void> blockOwner(String ownerId) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null || ownerId.isEmpty) return;
    if (_blockedOwnerIds.contains(ownerId)) return;
    _blockedOwnerIds.add(ownerId);
    _currentPosts.removeWhere((p) => (p.data() as Map<String, dynamic>)['uid'] == ownerId);
    await _firestore.collection('users').doc(myUid).collection('blockedChannels').doc(ownerId).set({
      'blockedAt': FieldValue.serverTimestamp(),
    });
    notifyListeners(); // هاد اللي بيخلي الرائج والتوصيات يحذفو سوا بنفس اللحظة
  }

  bool isOwnerBlocked(String ownerId) => _blockedOwnerIds.contains(ownerId);
  // [تطوير صمام أمان Tini النهائي]: فحص حقيقي، ديناميكي، وصارم لنوع البيانات
  bool verifyAgeRestrictionField(DocumentSnapshot postDoc) {
    if (!postDoc.exists) return false;

    final data = postDoc.data() as Map<String, dynamic>?;
    if (data == null) return false;

    // جلب الحقل بأعلى درجات الأمان
    final dynamic fieldValue = data['isAgeRestricted'];

    if (fieldValue == null) return false;

    // إذا كان القيمة بولين حقيقي، نعيدها مباشرة
    if (fieldValue is bool) {
      return fieldValue;
    }

    // صمام أمان إضافي: إذا كان مخزناً كنص بالخطأ "true" أو "false"
    if (fieldValue is String) {
      return fieldValue.trim().toLowerCase() == 'true';
    }

    return false;
  }

  // [AUDIENCE CONTROL - ADDITION] - فلترة 18+ على مستوى الحساب - FIXED V2
  Future<void> _refreshCurrentViewerAdultStatus() async {
    // [إصلاح] اذا age = 0 حاول احسبه من birthDate او dob
    // المصدر الموحد يراجع التاريخ نفسه ولا يستخدم age أو isUserAdult كإثبات.
    await _audienceAccess.refresh();
  }

  List<DocumentSnapshot> _filterAdultPosts(List<DocumentSnapshot> posts) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? "";
    List<DocumentSnapshot> filtered = posts.where((doc) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) return true;
      if (data['isDeleted'] == true) return false;
      final String privacy = (data['privacy'] ?? data['defaultPrivacy'] ?? 'everyone').toString();
      // كاش البداية لازم يكون الجميع فقط
      if (privacy == 'only_me' || privacy == 'private') {
        if (data['uid'] != currentUid) return false;
      }
      if (privacy == 'friends') {
        // بالكاش العام ما نطلع الأصدقاء فقط
        if (data['uid'] != currentUid) return false;
      }
      return true;
    }).toList();
    filtered = filtered.where((doc) {
      final data = doc.data() as Map<String, dynamic>?;
      return data != null && _audienceAccess.canViewPost(data, postId: doc.id);
    }).toList();
    // عدم اقتراح القناة - ما منلمسو
    if (_blockedOwnerIds.isNotEmpty) {
      filtered = filtered.where((doc) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) return true;
        final uid = data['uid'] as String? ?? '';
        if (_blockedOwnerIds.contains(uid)) return false;
        return true;
      }).toList();
    }
    // [Phase 5 - HARD BLOCK] - الحظر الكامل - ميزة لحالها
    if (_hardBlockedIds.isNotEmpty) {
      filtered = filtered.where((doc) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) return true;
        final uid = data['uid'] as String? ?? '';
        if (_hardBlockedIds.contains(uid)) return false;
        return true;
      }).toList();
    }
    // [Phase 6 - Two Way] - اذا هو حاظرني لا تطلع فيديوهاتي عنده
    if (_blockedByIds.isNotEmpty) {
      filtered = filtered.where((doc) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) return true;
        final uid = data['uid'] as String? ?? '';
        if (_blockedByIds.contains(uid)) return false;
        return true;
      }).toList();
    }
    return filtered;
  }

  // [AUDIENCE CONTROL] - للاستخدام في home_screen و post_view_screen
  bool isCurrentViewerAdult() => _audienceAccess.isViewerAdult;
  bool shouldHidePostForCurrentViewer(Map<String, dynamic> postData) {
    return !_audienceAccess.canViewPost(postData);
  }
}