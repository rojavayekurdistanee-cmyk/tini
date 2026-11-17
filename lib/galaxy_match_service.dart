import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'galaxy_match_models.dart';

abstract class GalaxyMatchBackend {
  String? get currentUid;
  Stream<String?> get identityChanges;
  Stream<GalaxyMatchPreferences?> preferences(String uid);
  Stream<List<GalaxyMatchInvite>> inbox(String uid);
  Stream<Set<String>> blocks(String uid, {required bool reverse});
  Future<List<GalaxyMatchInvite>> older(String uid, GalaxyMatchInvite cursor);
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> data);
}

class GalaxyMatchService implements GalaxyMatchBackend {
  final FirebaseFirestore store;
  final FirebaseAuth auth;
  final FirebaseFunctions functions;
  GalaxyMatchService({
    FirebaseFirestore? store,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
  }) : store = store ?? FirebaseFirestore.instance,
       auth = auth ?? FirebaseAuth.instance,
       functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');
  @override
  String? get currentUid => auth.currentUser?.uid;
  @override
  Stream<String?> get identityChanges =>
      auth.authStateChanges().map((u) => u?.uid);
  @override
  Stream<GalaxyMatchPreferences?> preferences(String uid) => store
      .collection('galaxy_match_preferences')
      .doc(uid)
      .snapshots()
      .map((d) => d.exists ? GalaxyMatchPreferences.fromMap(d.data()!) : null);
  Query<Map<String, dynamic>> _inbox(String uid) => store
      .collection('galaxy_match_inbox')
      .doc(uid)
      .collection('galaxy_match_items')
      .orderBy('updatedAt', descending: true)
      .orderBy(FieldPath.documentId, descending: true);
  @override
  Stream<List<GalaxyMatchInvite>> inbox(String uid) => _inbox(uid)
      .limit(100)
      .snapshots()
      .map(
        (s) => s.docs
            .map((d) => GalaxyMatchInvite.fromMap(d.id, d.data()))
            .toList(),
      );
  @override
  Future<List<GalaxyMatchInvite>> older(
    String uid,
    GalaxyMatchInvite cursor,
  ) async =>
      (await _inbox(uid)
              .startAfter([Timestamp.fromDate(cursor.updatedAt), cursor.id])
              .limit(100)
              .get())
          .docs
          .map((d) => GalaxyMatchInvite.fromMap(d.id, d.data()))
          .toList();
  @override
  Stream<Set<String>> blocks(String uid, {required bool reverse}) => store
      .collection('users')
      .doc(uid)
      .collection(reverse ? 'blockedBy' : 'blocked')
      .snapshots()
      .map((s) => s.docs.map((d) => d.id).toSet());
  @override
  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> data,
  ) async {
    final result = await functions
        .httpsCallable(name)
        .call<Map<String, dynamic>>(data);
    return Map<String, dynamic>.from(result.data);
  }
}
