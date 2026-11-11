import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Full account data is owner-only. Other accounts expose a server-maintained
/// allowlist in public_profiles. Never fall back to users for another account.
class UserDocuments {
  static DocumentReference<Map<String, dynamic>> readable(
    FirebaseFirestore store,
    String? uid,
  ) {
    if (uid == null || uid.isEmpty) {
      throw ArgumentError.value(uid, 'uid', 'A user ID is required');
    }
    final ownAccount = FirebaseAuth.instance.currentUser?.uid == uid;
    return store.collection(ownAccount ? 'users' : 'public_profiles').doc(uid);
  }
}
