import 'package:cloud_firestore/cloud_firestore.dart';

// [Tini - Owner Reactions Overlay] - بيانات العرض فقط، لا يتم تعديل التعليقات أو الإعجابات هنا.
class VideoReaction {
  final String uid;
  final String userName;
  final String userImage;
  final String? comment;
  // [Tini - Owner Reactions Overlay] - معرّف التعليق لفتحه وتمييزه في الشيت الأصلي.
  final String? commentId;
  final bool isLiked;
  final DateTime timestamp;

  const VideoReaction({
    required this.uid,
    required this.userName,
    required this.userImage,
    required this.comment,
    this.commentId,
    required this.isLiked,
    required this.timestamp,
  });
}

class VideoReactionsService {
  final FirebaseFirestore _db;

  VideoReactionsService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  // قراءات محدودة وعند فتح فيديو صاحب الحساب فقط؛ لا يوجد listener دائم.
  Future<List<VideoReaction>> getReactions(String postId) async {
    final post = _db.collection('posts').doc(postId);
    final results = await Future.wait([
      post.collection('likes').orderBy('createdAt', descending: true).limit(60).get(),
      post.collection('comments').orderBy('timestamp', descending: true).limit(40).get(),
    ]);

    final likesDocs = results[0].docs;
    final commentsDocs = results[1].docs;
    final Map<String, VideoReaction> byUser = {};
    final Set<String> sampledLikeIds = {};

    for (final doc in likesDocs) {
      final data = doc.data();
      final uid = (data['uid'] ?? doc.id).toString();
      if (uid.isEmpty) continue;
      sampledLikeIds.add(uid);
      final time = data['createdAt'];
      byUser[uid] = VideoReaction(
        uid: uid,
        userName: (data['userName'] ?? 'مستخدم').toString(),
        userImage: (data['userImage'] ?? '').toString(),
        comment: null,
        isLiked: true,
        timestamp: time is Timestamp ? time.toDate() : DateTime.fromMillisecondsSinceEpoch(0),
      );
    }

    // أحدث تعليق لكل شخص؛ الإعجاب والتعليق من نفس الشخص يظهران بفقاعة واحدة.
    for (final doc in commentsDocs) {
      final data = doc.data();
      final uid = (data['uid'] ?? '').toString();
      final commentText = (data['text'] ?? '').toString().trim();
      if (uid.isEmpty || commentText.isEmpty) continue;
      final existing = byUser[uid];
      if (existing?.comment != null) continue;
      final time = data['timestamp'];
      final timestamp = time is Timestamp ? time.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
      byUser[uid] = VideoReaction(
        uid: uid,
        userName: (data['userName'] ?? existing?.userName ?? 'مستخدم').toString(),
        userImage: (data['userImage'] ?? existing?.userImage ?? '').toString(),
        comment: commentText,
        commentId: doc.id,
        isLiked: existing?.isLiked ?? false,
        timestamp: timestamp,
      );
    }

    // قد يكون الإعجاب أقدم من آخر 60 إعجاباً؛ نتحقق فقط لمعلّقي العينة دون تحميل الجميع.
    final commentUsers = byUser.values
        .where((reaction) => reaction.comment != null && !sampledLikeIds.contains(reaction.uid))
        .map((reaction) => reaction.uid)
        .toList();
    if (commentUsers.isNotEmpty) {
      final individualLikes = await Future.wait(
        commentUsers.map((uid) => post.collection('likes').doc(uid).get()),
      );
      for (var i = 0; i < commentUsers.length; i++) {
        if (!individualLikes[i].exists) continue;
        final current = byUser[commentUsers[i]]!;
        byUser[commentUsers[i]] = VideoReaction(
          uid: current.uid,
          userName: current.userName,
          userImage: current.userImage,
          comment: current.comment,
          commentId: current.commentId,
          isLiked: true,
          timestamp: current.timestamp,
        );
      }
    }

    final reactions = byUser.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return reactions.take(60).toList();
  }
}
