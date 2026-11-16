import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class GalaxyRecords {
  final Map<String, Map<String, dynamic>> records;
  final bool verified;
  const GalaxyRecords(this.records, {this.verified = true});
}

abstract class GalaxyDiscoveryBackend {
  String? get currentUid;
  Stream<String?> get identityChanges;
  Stream<GalaxyRecords> watchViewer(String uid);
  Stream<GalaxyRecords> watchBlocks(String uid, {required bool reverse});
  Stream<GalaxyRecords> watchProfiles(List<String> ids);
  Stream<Map<String, Map<String, dynamic>>> pages(double pivot);
}

class GalaxyDiscoveryService implements GalaxyDiscoveryBackend {
  final FirebaseFirestore store;
  final FirebaseAuth auth;
  GalaxyDiscoveryService({FirebaseFirestore? store, FirebaseAuth? auth})
    : store = store ?? FirebaseFirestore.instance,
      auth = auth ?? FirebaseAuth.instance;
  @override
  String? get currentUid => auth.currentUser?.uid;
  @override
  Stream<String?> get identityChanges =>
      auth.authStateChanges().map((u) => u?.uid);

  GalaxyRecords _records(QuerySnapshot<Map<String, dynamic>> snapshot) =>
      GalaxyRecords(
        {for (final doc in snapshot.docs) doc.id: doc.data()},
        verified:
            !snapshot.metadata.isFromCache &&
            !snapshot.metadata.hasPendingWrites,
      );

  @override
  Stream<GalaxyRecords> watchViewer(String uid) => store
      .collection('users')
      .doc(uid)
      .snapshots(includeMetadataChanges: true)
      .map(
        (doc) => GalaxyRecords(
          {if (doc.exists) uid: doc.data()!},
          verified: !doc.metadata.isFromCache && !doc.metadata.hasPendingWrites,
        ),
      );
  @override
  Stream<GalaxyRecords> watchBlocks(String uid, {required bool reverse}) =>
      store
          .collection('users')
          .doc(uid)
          .collection(reverse ? 'blockedBy' : 'blocked')
          .snapshots(includeMetadataChanges: true)
          .map(_records);
  @override
  Stream<GalaxyRecords> watchProfiles(List<String> ids) => store
      .collection('public_profiles')
      .where(FieldPath.documentId, whereIn: ids)
      .snapshots(includeMetadataChanges: true)
      .map(_records);

  /// At most 96 documents per window, in pages of 24 including wraparound.
  /// The caller can stop early once enough eligible accounts are selected.
  @override
  Stream<Map<String, Map<String, dynamic>>> pages(double pivot) async* {
    var remaining = 96;
    for (final wrap in [false, true]) {
      Query<Map<String, dynamic>> query = store
          .collection('public_profiles')
          .where('galaxyEligible', isEqualTo: true)
          .where('galaxyRank', isGreaterThanOrEqualTo: wrap ? 0.0 : pivot);
      if (wrap) query = query.where('galaxyRank', isLessThan: pivot);
      query = query.orderBy('galaxyRank').orderBy(FieldPath.documentId);
      DocumentSnapshot<Map<String, dynamic>>? cursor;
      while (remaining > 0) {
        var pageQuery = query.limit(remaining < 24 ? remaining : 24);
        if (cursor != null) pageQuery = pageQuery.startAfterDocument(cursor);
        final result = await pageQuery
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 12));
        if (result.docs.isEmpty) break;
        remaining -= result.docs.length;
        yield {for (final doc in result.docs) doc.id: doc.data()};
        cursor = result.docs.last;
        if (result.docs.length < 24) break;
      }
    }
  }
}
