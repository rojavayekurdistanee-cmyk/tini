import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'tini_chat_read_checkpoint.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'r2_service.dart';
import 'banner_manager.dart'; // [Tini]
import 'group_message_model.dart';

class GroupChatProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final R2Service _r2 = R2Service();
  String? _senderCacheUid;
  DateTime? _senderCacheAt;
  Map<String, dynamic>? _senderCache;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // [Phase 6 - HARD BLOCK ONLY]
  Set<String> _blockedIds = {};
  Set<String> get blockedIds => _blockedIds;

  final BannerManager _bannerManager = BannerManager.instance;

  StreamSubscription? _groupsSub;

  Future<void> loadBlockedIds() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      final List fromField = doc.data()?['blockedUsers']?? doc.data()?['blocked']?? [];
      _blockedIds = fromField.map((e) => e.toString()).toSet();
      final snap = await _firestore.collection('users').doc(uid).collection('blocked').get();
      _blockedIds.addAll(snap.docs.map((d) => d.id));
    } catch (_) {}
  }

  bool isBlocked(String uid) => _blockedIds.contains(uid);

  void initialize() {
    loadBlockedIds();
  }

  Future<bool> canAddUser(String adderId, String targetId) async {
    if (adderId == targetId) return true;
    try {
      final doc = await _firestore.collection('users').doc(targetId).get();
      if (!doc.exists) return true;
      final privacy = doc.data()?['groupAddPrivacy']?? 'following';
      if (privacy == 'all') return true;
      if (privacy == 'following') {
        final following = await _firestore.collection('users').doc(targetId).collection('following').doc(adderId).get();
        if (following.exists) return true;
        final followers = await _firestore.collection('users').doc(targetId).collection('followers').doc(adderId).get();
        if (followers.exists) return true;
        final ids = [adderId, targetId]..sort();
        final roomId = ids.join('_');
        final room = await _firestore.collection('chat_rooms').doc(roomId).get();
        if (room.exists) return true;
        return false;
      }
      return true;
    } catch (e) {
      return true;
    }
  }

  Future<String> createGroup({
    required String name,
    String imageUrl = '',
    required List<String> memberIds,
  }) async {
    final currentUid = _auth.currentUser?.uid;
    if (currentUid == null) return '';
    _isLoading = true;
    notifyListeners();
    try {
      List<String> allowed = [currentUid];
      List<String> needsInvite = [];
      for (var uid in memberIds) {
        if (uid == currentUid) continue;
        if (_blockedIds.contains(uid)) continue;
        bool can = await canAddUser(currentUid, uid);
        if (can) allowed.add(uid); else needsInvite.add(uid);
      }
      final ref = _firestore.collection('group_chats').doc();
      await ref.set({
        'groupId': ref.id,
        'groupName': name,
        'groupImage': imageUrl,
        'createdBy': currentUid,
        'members': allowed,
        'admins': [currentUid],
        'moderators': [],
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': 'تم إنشاء المجموعة',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessageSenderId': currentUid,
        'unreadCount': {for (var m in allowed) m: 0},
        'deletedFor': {},
      });
      for (var uid in needsInvite) {
        await _firestore.collection('group_invites').add({
          'groupId': ref.id,
          'groupName': name,
          'groupImage': imageUrl,
          'fromUid': currentUid,
          'toUid': uid,
          'status': 'pending',
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
      return ref.id;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Stream<QuerySnapshot> getMyGroups(String uid) {
    return _firestore.collection('group_chats').where('members', arrayContains: uid).orderBy('lastMessageTime', descending: true).snapshots().map((snapshot) {
      final docs = snapshot.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final deletedFor = Map<String, dynamic>.from(data['deletedFor']?? {});
        if (deletedFor[uid] == true) return false;
        return true;
      }).toList();

      docs.sort((a, b) {
        final aData = a.data() as Map<String, dynamic>;
        final bData = b.data() as Map<String, dynamic>;
        final aPinned = Map<String, dynamic>.from(aData['pinned']?? {})[uid]?? false;
        final bPinned = Map<String, dynamic>.from(bData['pinned']?? {})[uid]?? false;
        if (aPinned &&!bPinned) return -1;
        if (!aPinned && bPinned) return 1;
        return 0;
      });

      return _FakeQuerySnapshot(docs, snapshot.metadata, snapshot.docChanges);
    });
  }

  Stream<List<GroupMessageModel>> messagesStream(String groupId) {
    return _firestore.collection('group_chats').doc(groupId).collection('messages').orderBy('timestamp', descending: true).snapshots().map((snap) {
      return snap.docs.map((d) => GroupMessageModel.fromDoc(d)).toList();
    });
  }

  Future<void> sendMessage({
    required String groupId,
    required String text,
    String type = 'text',
    String? mediaUrl,
    Map<String, dynamic>? replyTo,
    int? durationSeconds,
    List<int>? waveform,
    bool viewOnce = false,
    List<Map<String, dynamic>>? mediaItems,
  }) async {
    final currentUid = _auth.currentUser?.uid;
    if (currentUid == null) return;
    // The sender identity is short-lived and scoped to the authenticated user.
    // Group membership is still read fresh for every send.
    final now = DateTime.now();
    if (_senderCacheUid != currentUid || _senderCacheAt == null ||
        now.difference(_senderCacheAt!) > const Duration(seconds: 90)) {
      final userDoc = await _firestore.collection('users').doc(currentUid).get();
      _senderCache = userDoc.data() ?? <String, dynamic>{};
      _senderCacheUid = currentUid;
      _senderCacheAt = now;
    }
    final senderName = _senderCache?['fullName'] ?? _senderCache?['username'] ?? 'مستخدم';
    final senderImg = _senderCache?['profileImg'] ?? '';
    final groupDoc = await _firestore.collection('group_chats').doc(groupId).get();
    if (!groupDoc.exists) return;
    final members = List<String>.from(groupDoc.data()?['members']?? []);
    final msgRef = _firestore.collection('group_chats').doc(groupId).collection('messages').doc();
    final batch = _firestore.batch();
    batch.set(msgRef, {
      'senderId': currentUid,
      'senderName': senderName,
      'senderImg': senderImg,
      'text': text,
      'type': type,
      'mediaUrl': mediaUrl,
      if (mediaItems != null) 'mediaItems': mediaItems,
      'timestamp': FieldValue.serverTimestamp(),
      'deliveredTo': [currentUid],
      'readBy': [currentUid],
      'isDelivered': false,
      'isSeen': false,
      if (replyTo!= null) 'replyTo': replyTo,
      if (durationSeconds!= null) 'durationSeconds': durationSeconds,
      if (waveform != null && waveform.isNotEmpty) 'waveform': waveform,
      if (viewOnce) ...{'viewOnce': true, 'viewedBy': <String>[]},
    });
    String preview = text;
    if (type == 'album') preview = '📷 صور وفيديوهات';
    if (type == 'image') preview = '📷 صورة';
    if (type == 'video') preview = '🎥 فيديو';
    if (type == 'video_note') preview = '⭕ ملاحظة فيديو';
    if (type == 'audio') preview = '🎤 صوت';
    if (type == 'location') preview = '📍 موقع';
    if (type == 'document') preview = '📄 مستند';
    Map<String, dynamic> updates = {};
    for (var m in members) {
      if (m!= currentUid) {
        updates['unreadCount.$m'] = FieldValue.increment(1);
        updates['deletedFor.$m'] = FieldValue.delete();
      }
    }
    if (_auth.currentUser?.uid != currentUid) return;
    batch.update(_firestore.collection('group_chats').doc(groupId), {
      'lastMessage': preview,
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastMessageSenderId': currentUid,
...updates,
    });
    // Both writes succeed or fail together: no orphaned message metadata.
    await batch.commit();
    notifyListeners();
  }

  // [Tini]: Prevent overlapping full-history receipt scans for one member.
  final Map<String, Future<void>> _groupReadJobs = {};
  final Set<String> _groupReadAgain = {};

  // [معدل مثل chat_provider]
  Future<void> markAsRead(String groupId, String uid) {
    final key = '$uid/$groupId';
    final running = _groupReadJobs[key];
    if (running != null) {
      _groupReadAgain.add(key);
      return running;
    }
    final operation = _markGroupReadUntilCaughtUp(groupId, uid, key);
    _groupReadJobs[key] = operation;
    return operation.whenComplete(() {
      _groupReadJobs.remove(key);
      _groupReadAgain.remove(key);
    });
  }

  Future<void> _markGroupReadUntilCaughtUp(
      String groupId, String uid, String key) async {
    do {
      _groupReadAgain.remove(key);
      await _markGroupReadOnce(groupId, uid);
    } while (_groupReadAgain.remove(key));
  }

  Future<void> _markGroupReadOnce(String groupId, String uid) async {
    try {
      final groupRef = _firestore.collection('group_chats').doc(groupId);
      await groupRef.update({
        'unreadCount.$uid': 0,
        'deletedFor.$uid': FieldValue.delete(),
      });
      final userDoc = await _firestore.collection('users').doc(uid).get();
      final bool allowRead = userDoc.data()?['showReadReceipts'] ?? true;

      final last = await TiniChatReadCheckpoint.get('read-group', groupId, uid);
      var query = TiniChatReadCheckpoint.since(
        groupRef.collection('messages').orderBy('timestamp'), last);
      QueryDocumentSnapshot<Map<String, dynamic>>? cursor;
      Timestamp? mostRecent = last;
      var allFromServer = true;
      while (true) {
        var pageQuery = query.limit(200);
        if (cursor != null) pageQuery = pageQuery.startAfterDocument(cursor);
        final page = await pageQuery.get();
        if (page.metadata.isFromCache) allFromServer = false;
        if (page.docs.isEmpty) break;
        final batch = _firestore.batch();
        var count = 0;
        for (final doc in page.docs) {
          final data = doc.data();
          final ts = data['timestamp'];
          if (ts is Timestamp &&
              (mostRecent == null || ts.compareTo(mostRecent) > 0)) {
            mostRecent = ts;
          }
          if (data['senderId'] == uid || data['lockedGray'] == true) continue;
          final readBy = List<String>.from(data['readBy'] ?? []);
          final deliveredTo = List<String>.from(data['deliveredTo'] ?? []);
          if (allowRead) {
            if (readBy.contains(uid)) continue;
            batch.update(doc.reference, {
              'isDelivered': true,
              'isSeen': true,
              'readBy': FieldValue.arrayUnion([uid]),
              'deliveredTo': FieldValue.arrayUnion([uid]),
              'deliveredAt': FieldValue.serverTimestamp(),
              'seenAt': FieldValue.serverTimestamp(),
            });
          } else {
            if (deliveredTo.contains(uid)) continue;
            batch.update(doc.reference, {
              'isDelivered': true,
              'deliveredTo': FieldValue.arrayUnion([uid]),
              'deliveredAt': FieldValue.serverTimestamp(),
            });
          }
          count++;
        }
        if (count > 0) await batch.commit();
        cursor = page.docs.last;
        if (page.docs.length < 200) break;
      }
      if (allFromServer) {
        await TiniChatReadCheckpoint.save(
            'read-group', groupId, uid, mostRecent);
        await TiniChatReadCheckpoint.save(
            'delivered-group', groupId, uid, mostRecent);
      }
      notifyListeners();
    } catch (error) {
      debugPrint('Error marking group as read: $error');
    }
  }

  // ✅ الإضافة اللي كانت ناقصة وتسبب Error Ln 31 Col 39
  Future<void> markAsDelivered(String groupId, String uid) async {
    try {
      final groupRef = _firestore.collection('group_chats').doc(groupId);
      final last = await TiniChatReadCheckpoint.get('delivered-group', groupId, uid);
      final query = TiniChatReadCheckpoint.since(
          groupRef.collection('messages').orderBy('timestamp'), last);
      QueryDocumentSnapshot<Map<String, dynamic>>? cursor;
      Timestamp? mostRecent = last;
      var allFromServer = true;
      while (true) {
        var pageQuery = query.limit(200);
        if (cursor != null) pageQuery = pageQuery.startAfterDocument(cursor);
        final page = await pageQuery.get();
        if (page.metadata.isFromCache) allFromServer = false;
        if (page.docs.isEmpty) break;
        final batch = _firestore.batch();
        var count = 0;
        for (final doc in page.docs) {
          final data = doc.data();
          final ts = data['timestamp'];
          if (ts is Timestamp &&
              (mostRecent == null || ts.compareTo(mostRecent) > 0)) {
            mostRecent = ts;
          }
          if (data['senderId'] == uid || data['isDelivered'] == true) continue;
          if (List<String>.from(data['deliveredTo'] ?? []).contains(uid)) continue;
          batch.update(doc.reference, {
            'isDelivered': true,
            'deliveredTo': FieldValue.arrayUnion([uid]),
            'deliveredAt': FieldValue.serverTimestamp(),
          });
          count++;
        }
        if (count > 0) await batch.commit();
        cursor = page.docs.last;
        if (page.docs.length < 200) break;
      }
      if (allFromServer) {
        await TiniChatReadCheckpoint.save(
            'delivered-group', groupId, uid, mostRecent);
      }
    } catch (error) {
      debugPrint('Error marking group as delivered: $error');
    }
  }

  Future<void> hideGroup(String groupId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _firestore.collection('group_chats').doc(groupId).update({'deletedFor.$uid': true, 'unreadCount.$uid': 0});
    notifyListeners();
  }

  // ===== [Tini]: نفس منطق الشات العادي - تثبيت / كتم / حذف / أرشفة للجروبات =====

  Future<void> pinGroupChat(String groupId, bool pin) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      await _firestore.collection('group_chats').doc(groupId).update({
        'pinned.$uid': pin,
        'pinnedAt.$uid': pin? FieldValue.serverTimestamp() : FieldValue.delete(),
      });
      notifyListeners();
    } catch (e) {
      debugPrint('Error pin group: $e');
    }
  }

  Future<void> muteGroupChat(String groupId, bool mute) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      await _firestore.collection('group_chats').doc(groupId).update({
        'muted.$uid': mute,
      });
      notifyListeners();
    } catch (e) {
      debugPrint('Error mute group: $e');
    }
  }

  Future<void> hideGroupChats(List<String> groupIds) async {
    if (groupIds.isEmpty) return;
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final batch = _firestore.batch();
      for (final id in groupIds) {
        batch.update(_firestore.collection('group_chats').doc(id), {
          'deletedFor.$uid': true,
          'unreadCount.$uid': 0,
        });
      }
      await batch.commit();
      notifyListeners();
    } catch (e) {
      debugPrint('Error hiding groups: $e');
    }
  }

  Future<void> archiveGroupChat(String groupId, bool archive) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      await _firestore.collection('group_chats').doc(groupId).update({
        'archivedBy': archive? FieldValue.arrayUnion([uid]) : FieldValue.arrayRemove([uid]),
        'unreadCount.$uid': 0,
      });
      notifyListeners();
    } catch (e) {
      debugPrint('Error archive group: $e');
    }
  }

  // ===== [نظام الإشراف الجديد - حماية المالك] =====

  Future<String> getRole(String groupId, String uid) async {
    final doc = await _firestore.collection('group_chats').doc(groupId).get();
    if (!doc.exists) return 'عضو';
    final data = doc.data()!;
    final createdBy = data['createdBy']?? '';
    final admins = List<String>.from(data['admins']?? []);
    final moderators = List<String>.from(data['moderators']?? []);
    if (createdBy == uid) return 'المالك';
    if (admins.contains(uid)) return 'مسؤول';
    if (moderators.contains(uid)) return 'مشرف';
    return 'عضو';
  }

  Future<bool> canRemoveMember({required String groupId, required String targetUid}) async {
    final myUid = _auth.currentUser?.uid;
    if (myUid == null) return false;
    if (myUid == targetUid) return false;
    final doc = await _firestore.collection('group_chats').doc(groupId).get();
    if (!doc.exists) return false;
    final data = doc.data()!;
    final createdBy = data['createdBy']?? '';
    final admins = List<String>.from(data['admins']?? []);
    final moderators = List<String>.from(data['moderators']?? []);
    if (targetUid == createdBy) return false; // مستحيل حدا يشيل المالك
    if (myUid == createdBy) return true; // المالك بيشيل الكل
    if (admins.contains(myUid) &&!admins.contains(targetUid) && targetUid!= createdBy) return true;
    if (moderators.contains(myUid)) {
      // المشرف بيشيل عضو عادي بس
      if (!admins.contains(targetUid) &&!moderators.contains(targetUid) && targetUid!= createdBy) return true;
    }
    return false;
  }

  Future<void> promoteToModerator({required String groupId, required String targetUid}) async {
    final myUid = _auth.currentUser?.uid;
    if (myUid == null) return;
    final doc = await _firestore.collection('group_chats').doc(groupId).get();
    if (!doc.exists) return;
    final createdBy = doc.data()?['createdBy']?? '';
    final admins = List<String>.from(doc.data()?['admins']?? []);
    if (myUid!= createdBy &&!admins.contains(myUid)) return; // بس المالك والمسؤول
    if (targetUid == createdBy) return;
    if (admins.contains(targetUid)) return;
    await _firestore.collection('group_chats').doc(groupId).update({
      'moderators': FieldValue.arrayUnion([targetUid]),
    });
    notifyListeners();
  }

  Future<void> demoteModerator({required String groupId, required String targetUid}) async {
    final myUid = _auth.currentUser?.uid;
    if (myUid == null) return;
    final doc = await _firestore.collection('group_chats').doc(groupId).get();
    if (!doc.exists) return;
    final createdBy = doc.data()?['createdBy']?? '';
    final admins = List<String>.from(doc.data()?['admins']?? []);
    if (myUid!= createdBy &&!admins.contains(myUid)) return;
    await _firestore.collection('group_chats').doc(groupId).update({
      'moderators': FieldValue.arrayRemove([targetUid]),
    });
    notifyListeners();
  }

  Future<void> removeMemberSecure({required String groupId, required String targetUid}) async {
    bool allowed = await canRemoveMember(groupId: groupId, targetUid: targetUid);
    if (!allowed) return;
    await _firestore.collection('group_chats').doc(groupId).update({
      'members': FieldValue.arrayRemove([targetUid]),
      'admins': FieldValue.arrayRemove([targetUid]),
      'moderators': FieldValue.arrayRemove([targetUid]),
    });
    notifyListeners();
  }

  Future<void> banFromGroup({required String groupId, required String targetUid}) async {
    bool allowed = await canRemoveMember(groupId: groupId, targetUid: targetUid);
    if (!allowed) return;
    await _firestore.collection('group_chats').doc(groupId).update({
      'members': FieldValue.arrayRemove([targetUid]),
      'admins': FieldValue.arrayRemove([targetUid]),
      'moderators': FieldValue.arrayRemove([targetUid]),
      'banned': FieldValue.arrayUnion([targetUid]),
    });
    notifyListeners();
  }

  // ===== [نظام التقييد المؤقت - مع احترام الرتبة] =====
  Future<void> restrictMember({required String groupId, required String targetUid, required Duration duration}) async {
    final myUid = _auth.currentUser?.uid;
    if (myUid == null) return;
    bool allowed = await canRemoveMember(groupId: groupId, targetUid: targetUid);
    if (!allowed) return;
    final until = Timestamp.fromDate(DateTime.now().add(duration));
    await _firestore.collection('group_chats').doc(groupId).update({
      'restricted.$targetUid': until,
      'restrictedBy.$targetUid': myUid,
    });
    notifyListeners();
  }

  Future<void> unrestrictMember({required String groupId, required String targetUid}) async {
    final myUid = _auth.currentUser?.uid;
    if (myUid == null) return;
    final doc = await _firestore.collection('group_chats').doc(groupId).get();
    if (!doc.exists) return;
    final data = doc.data()!;
    final createdBy = data['createdBy']?? '';
    final admins = List<String>.from(data['admins']?? []);
    final moderators = List<String>.from(data['moderators']?? []);
    final restrictedBy = Map<String, dynamic>.from(data['restrictedBy']?? {});
    final byUid = restrictedBy[targetUid]?.toString();

    // فك القيد: المالك يفك الكل، المسؤول يفك المشرف والعضو، المشرف يفك العضو فقط
    // وما حدا بيقدر يفك تقييد عامله رتبة اعلى منو
    bool canUnrestrict = false;
    if (myUid == createdBy) {
      canUnrestrict = true;
    } else if (admins.contains(myUid)) {
      // المسؤول ما بيفك تقييد المالك ولا مسؤول تاني
      if (byUid == null || byUid!= createdBy &&!admins.contains(byUid)) {
        canUnrestrict = true;
      }
      // حتى لو ما عرفنا مين قيد، المسؤول بيقدر يفك عضو ومشرف
      if (await canRemoveMember(groupId: groupId, targetUid: targetUid)) {
        canUnrestrict = true;
      }
    } else if (moderators.contains(myUid)) {
      // المشرف بس بيفك عضو عادي قيده مشرف تاني او هو نفسو
      if (!admins.contains(targetUid) && targetUid!= createdBy &&!moderators.contains(targetUid)) {
        if (byUid == null || byUid == myUid || moderators.contains(byUid) || (!admins.contains(byUid!) && byUid!= createdBy)) {
          canUnrestrict = true;
        }
      }
    }

    if (!canUnrestrict) return;

    await _firestore.collection('group_chats').doc(groupId).update({
      'restricted.$targetUid': FieldValue.delete(),
      'restrictedBy.$targetUid': FieldValue.delete(),
    });
    notifyListeners();
  }

  Future<bool> isMemberRestricted({required String groupId, required String uid}) async {
    final doc = await _firestore.collection('group_chats').doc(groupId).get();
    if (!doc.exists) return false;
    final restricted = Map<String, dynamic>.from(doc.data()?['restricted']?? {});
    if (!restricted.containsKey(uid)) return false;
    final ts = restricted[uid];
    if (ts is Timestamp) {
      if (ts.toDate().isAfter(DateTime.now())) {
        return true;
      } else {
        // انتهت المدة - فك تلقائي
        try {
          await _firestore.collection('group_chats').doc(groupId).update({
            'restricted.$uid': FieldValue.delete(),
            'restrictedBy.$uid': FieldValue.delete(),
          });
        } catch (_) {}
        return false;
      }
    }
    return false;
  }
    // ===== [نقل ميزات الخاص للجروب - بدون لمس القديم] =====
  Future<void> sendAlbum({required String groupId, required List<Map<String, dynamic>> mediaItems, String caption = ''}) async {
    if (mediaItems.isEmpty) return;
    await sendMessage(groupId: groupId, text: caption, type: 'album', mediaItems: mediaItems);
  }

  Future<void> sendImage({required String groupId, required String mediaUrl, String caption = '', bool viewOnce = false}) async {
    await sendMessage(groupId: groupId, text: viewOnce ? '' : caption, type: 'image', mediaUrl: mediaUrl, viewOnce: viewOnce);
  }

  Future<void> sendVideo({required String groupId, required String mediaUrl, String caption = '', int? durationSeconds, bool viewOnce = false}) async {
    await sendMessage(groupId: groupId, text: viewOnce ? '' : caption, type: 'video', mediaUrl: mediaUrl, durationSeconds: durationSeconds, viewOnce: viewOnce);
  }

  Future<void> sendVideoNote({required String groupId, required String mediaUrl, int? durationSeconds}) async {
    await sendMessage(groupId: groupId, text: '', type: 'video_note', mediaUrl: mediaUrl, durationSeconds: durationSeconds);
  }

  Future<void> sendVoice({required String groupId, required String mediaUrl, required int durationSeconds, List<int>? waveform}) async {
    await sendMessage(groupId: groupId, text: '', type: 'audio', mediaUrl: mediaUrl, durationSeconds: durationSeconds, waveform: waveform);
  }

  // ===== [عرض مرة واحدة] =====
  /// يسجّل فتح المستخدم للرسالة (مرة واحدة فقط) قبل عرض المحتوى.
  /// بتستخدم Transaction عشان ما يقدر يفتحها مرتين حتى من جهازين.
  Future<bool> claimViewOnce({required String groupId, required String messageId}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    final ref = _firestore.collection('group_chats').doc(groupId).collection('messages').doc(messageId);
    try {
      return await _firestore.runTransaction<bool>((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) return false;
        final data = snap.data() as Map<String, dynamic>;
        if (data['viewOnce'] != true) return false;
        if (data['senderId'] == uid) return false;
        if ((data['mediaUrl'] ?? '').toString().isEmpty) return false;
        final viewed = List<String>.from(data['viewedBy'] ?? []);
        if (viewed.contains(uid)) return false;
        tx.update(ref, {'viewedBy': FieldValue.arrayUnion([uid])});
        return true;
      });
    } catch (e) {
      debugPrint('claimViewOnce error: $e');
      return false;
    }
  }

  /// بعد إغلاق العارض: إذا كل الأعضاء (غير المرسل) فتحوها، نحذف الملف من R2.
  Future<void> cleanupViewOnce({required String groupId, required String messageId}) async {
    try {
      final groupRef = _firestore.collection('group_chats').doc(groupId);
      final msgRef = groupRef.collection('messages').doc(messageId);
      final groupDoc = await groupRef.get();
      final msgDoc = await msgRef.get();
      if (!groupDoc.exists || !msgDoc.exists) return;
      final msg = msgDoc.data() as Map<String, dynamic>;
      if (msg['viewOnce'] != true) return;
      final url = (msg['mediaUrl'] ?? '').toString();
      if (url.isEmpty) return;
      final members = List<String>.from(groupDoc.data()?['members'] ?? []);
      final sender = msg['senderId'];
      final viewed = List<String>.from(msg['viewedBy'] ?? []);
      final stillPending = members.where((m) => m != sender && !viewed.contains(m));
      if (stillPending.isNotEmpty) return;
      await _r2.deleteByUrl(url);
      await msgRef.update({'mediaUrl': null, 'mediaDeleted': true});
    } catch (e) {
      debugPrint('cleanupViewOnce error: $e');
    }
  }

  void setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  @override
  void dispose() {
    _groupsSub?.cancel();
    super.dispose();
  }
}

class _FakeQuerySnapshot implements QuerySnapshot {
  final List<QueryDocumentSnapshot> _docs;
  @override
  final SnapshotMetadata metadata;
  @override
  final List<DocumentChange> docChanges;
  _FakeQuerySnapshot(this._docs, this.metadata, this.docChanges);
  @override
  List<QueryDocumentSnapshot> get docs => _docs;
  @override
  int get size => _docs.length;
}