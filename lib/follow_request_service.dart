import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FollowRequestService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _currentUserId => _auth.currentUser?.uid ?? '';

  /// 1. عدد الطلبات المعلقة
  Stream<int> getPendingCount() {
    if (_currentUserId.isEmpty) return Stream.value(0);
    
    return _firestore
        .collection('follow_requests')
        .where('toUserId', isEqualTo: _currentUserId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// 2. آخر شخص بعت طلب - يرجع Map مباشرة
  Stream<Map<String, dynamic>?> getLastRequester() {
    if (_currentUserId.isEmpty) return Stream.value(null);

    return _firestore
        .collection('follow_requests')
        .where('toUserId', isEqualTo: _currentUserId)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .asyncMap((snapshot) async {
          if (snapshot.docs.isEmpty) return null;
          
          final fromUserId = snapshot.docs.first.data()['fromUserId'] as String;
          final userDoc = await _firestore.collection('users').doc(fromUserId).get();
          
          if (!userDoc.exists) return null;
          
          return {
            'uid': userDoc.id,
            'fullName': userDoc.data()?['fullName'] ?? '',
            'username': userDoc.data()?['username'] ?? '',
            'profileImg': userDoc.data()?['profileImg'] ?? '',
          };
        });
  }

  /// 3. قبول الطلب
  Future<void> acceptRequest(String requestId, String fromUserId) async {
    if (_currentUserId.isEmpty) return;
    
    final batch = _firestore.batch();
    final now = FieldValue.serverTimestamp();

    // احذف الطلب
    batch.delete(_firestore.collection('follow_requests').doc(requestId));

    // ضيف في followers
    batch.set(
      _firestore.collection('users').doc(_currentUserId).collection('followers').doc(fromUserId),
      {'createdAt': now}
    );

    // ضيف في following
    batch.set(
      _firestore.collection('users').doc(fromUserId).collection('following').doc(_currentUserId),
      {'createdAt': now}
    );

    batch.update(_firestore.collection('users').doc(fromUserId), {
      'following': FieldValue.increment(1),
    });

    batch.update(_firestore.collection('users').doc(_currentUserId), {
      'followers': FieldValue.increment(1),
    });

    await batch.commit();
  }

  /// 4. رفض الطلب
  Future<void> rejectRequest(String requestId) async {
    await _firestore.collection('follow_requests').doc(requestId).delete();
  }

  /// 5. كل الطلبات - يرجع List<Map>
  Stream<List<Map<String, dynamic>>> getPendingRequests() {
    if (_currentUserId.isEmpty) return Stream.value([]);

    return _firestore
        .collection('follow_requests')
        .where('toUserId', isEqualTo: _currentUserId)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
          final List<Map<String, dynamic>> requests = [];
          
          for (var doc in snapshot.docs) {
            final fromUserId = doc.data()['fromUserId'] as String;
            final userDoc = await _firestore.collection('users').doc(fromUserId).get();
            
            if (!userDoc.exists) continue;
            
            final data = userDoc.data()!;
            requests.add({
              'requestId': doc.id,
              'uid': userDoc.id,
              'fullName': data['fullName'] ?? '',
              'username': data['username'] ?? '',
              'profileImg': data['profileImg'] ?? '',
              'createdAt': doc.data()['createdAt'],
            });
          }
          return requests;
        });
  }
}