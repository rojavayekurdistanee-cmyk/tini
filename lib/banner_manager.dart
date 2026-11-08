import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum BannerType { story, activity, like, comment, follow, mention, visit }

class BannerItem {
  final BannerType type;
  final Map<String, dynamic> data;
  final int id; // id ثابت مشان ما يتكرر
  BannerItem(this.type, this.data) : id = DateTime.now().microsecondsSinceEpoch;
}

class BannerManager {
  BannerManager._();
  static final instance = BannerManager._();
  final _firestore = FirebaseFirestore.instance;

  final ValueNotifier<BannerItem?> currentBanner = ValueNotifier(null);

  final List<BannerItem> _queue = [];
  Timer? _hideTimer;
  Timer? _gapTimer;
  bool _isShowing = false;

  static const _showDuration = Duration(seconds: 6); // مدة ظهور البانر
  static const _gap = Duration(seconds: 2); // الفراغ 1 ثانية اللي بدك ياه
  static const _maxQueue = 15;

  void _enqueue(BannerType type, Map<String, dynamic> data) {
    if (_queue.length >= _maxQueue) _queue.removeAt(0);
    _queue.add(BannerItem(type, data));
    if (!_isShowing) _process();
  }

  void _process() {
    if (_queue.isEmpty) {
      _isShowing = false;
      return;
    }
    _isShowing = true;
    final next = _queue.removeAt(0);
    currentBanner.value = next;

    _hideTimer?.cancel();
    _hideTimer = Timer(_showDuration, () {
      currentBanner.value = null;
      _gapTimer?.cancel();
      _gapTimer = Timer(_gap, _process);
    });
  }

  void showLikeBanner({required String fromUid, required String name, required String img, required String postId, String? postImage}) => _enqueue(BannerType.like, {'uid':fromUid,'name':name,'img':img,'postId':postId});
  void showCommentBanner({required String fromUid, required String name, required String img, required String postId, String? commentId}) => _enqueue(BannerType.comment, {'uid':fromUid,'name':name,'img':img,'postId':postId,'commentId':commentId});
  void showFollowBanner({required String fromUid, required String name, required String img}) => _enqueue(BannerType.follow, {'uid':fromUid,'name':name,'img':img});
  void showMentionBanner({required String fromUid, required String name, required String img, required String postId}) => _enqueue(BannerType.mention, {'uid':fromUid,'name':name,'img':img,'postId':postId});
  void showVisitBanner({required String fromUid, required String name, required String img}) => _enqueue(BannerType.visit, {'uid':fromUid,'name':name,'img':img});
  void addActivityOnlineBanner(Map<String, dynamic> data) => _enqueue(BannerType.activity, data);

  Future<void> addStoryActivities(List<QueryDocumentSnapshot> activities) async {
    final prefs = await SharedPreferences.getInstance();
    final shown = (prefs.getStringList('shown_banners')?? []).toSet();
    for (var doc in activities) {
      if (shown.contains(doc.id)) continue;
      final data = doc.data() as Map<String, dynamic>;
      final fromUid = data['fromUid']; if (fromUid==null) continue;
      try {
        final userDoc = await _firestore.collection('users').doc(fromUid).get();
        if (!userDoc.exists) continue;
        final u = userDoc.data()!;
        _enqueue(BannerType.story, {'uid':fromUid,'name':u['fullName']??u['username']??'مستخدم','img':u['profileImg']??'','text':'نشر قصة'});
        shown.add(doc.id);
      } catch(_){}
    }
    await prefs.setStringList('shown_banners', shown.toList());
  }

  void clearAllQueues() { _hideTimer?.cancel(); _gapTimer?.cancel(); _queue.clear(); _isShowing=false; currentBanner.value=null; }
  void dispose() { _hideTimer?.cancel(); _gapTimer?.cancel(); currentBanner.dispose(); }
}