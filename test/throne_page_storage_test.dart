// Firebase's bundled platform test helpers exercise the real widget without network access.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart'
    as platform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:titi_star/crown_provider.dart';
import 'package:titi_star/throne_social.dart';

class _CrownFixture extends ChangeNotifier implements CrownProvider {
  bool reigning = false;
  void crown() {
    reigning = true;
    notifyListeners();
  }

  @override
  bool get isThroneLocked => reigning;
  @override
  String get auctionId => 'test-auction';
  @override
  String? get coronationId => null;
  @override
  String? get availabilityMessage => null;
  @override
  bool get hasPendingBid => false;
  @override
  int get currentBid => reigning ? 10000 : 500;
  @override
  String get leaderName => 'Test king';
  @override
  String get leaderUid => 'test-king';
  @override
  int get reservedPoints => reigning ? 0 : 500;
  @override
  Timestamp get auctionEndsAt =>
      Timestamp.fromDate(DateTime.now().add(const Duration(days: 1)));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FirestoreFixture extends platform.FirebaseFirestorePlatform {
  _FirestoreFixture() : super(appInstance: Firebase.app());
  @override
  platform.FirebaseFirestorePlatform delegateFor({
    required FirebaseApp app,
    required String databaseId,
  }) => this;
  @override
  platform.DocumentReferencePlatform doc(String path) =>
      _DocumentFixture(this, path);
  @override
  platform.CollectionReferencePlatform collection(String path) =>
      _CollectionFixture(this, path);
}

class _DocumentFixture extends platform.DocumentReferencePlatform {
  _DocumentFixture(super.firestore, super.path);
  @override
  Stream<platform.DocumentSnapshotPlatform> snapshots({
    bool includeMetadataChanges = false,
    required platform.ListenSource listenSource,
  }) => Stream.value(
    platform.DocumentSnapshotPlatform(
      firestore,
      path,
      {
        'reactions': {'crown': 0, 'heart': 0, 'fire': 0},
      },
      platform.InternalSnapshotMetadata(
        hasPendingWrites: false,
        isFromCache: false,
      ),
    ),
  );
}

class _CollectionFixture extends platform.CollectionReferencePlatform {
  _CollectionFixture(super.firestore, super.path) {
    parameters.addAll({
      'where': <List<dynamic>>[],
      'orderBy': <List<dynamic>>[],
      'startAt': null,
      'startAfter': null,
      'endAt': null,
      'endBefore': null,
    });
  }
  @override
  platform.DocumentReferencePlatform doc([String? path]) =>
      _DocumentFixture(firestore, '${this.path}/${path ?? 'test'}');
  @override
  platform.QueryPlatform orderBy(Iterable<List<dynamic>> orders) {
    parameters['orderBy'] = orders.toList();
    return this;
  }

  @override
  platform.QueryPlatform limit(int limit) => this;
  @override
  platform.QueryPlatform where(List<List<dynamic>> conditions) {
    parameters['where'] = conditions;
    return this;
  }

  @override
  Future<platform.QuerySnapshotPlatform> get([
    platform.GetOptions options = const platform.GetOptions(),
  ]) async => _empty;
  @override
  Stream<platform.QuerySnapshotPlatform> snapshots({
    bool includeMetadataChanges = false,
    platform.ServerTimestampBehavior serverTimestampBehavior =
        platform.ServerTimestampBehavior.none,
    required platform.ListenSource listenSource,
  }) => Stream.value(_empty);
  platform.QuerySnapshotPlatform get _empty => platform.QuerySnapshotPlatform(
    [],
    [],
    platform.SnapshotMetadataPlatform(false, false),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async {
    await Firebase.initializeApp();
    platform.FirebaseFirestorePlatform.instance = _FirestoreFixture();
  });
  const scrollKey = PageStorageKey<String>('tini_throne_full_screen_scroll');
  Widget page(
    PageStorageBucket bucket,
    _CrownFixture crown,
    ScrollController controller,
  ) => MaterialApp(
    home: Scaffold(
      body: PageStorage(
        bucket: bucket,
        child: ChangeNotifierProvider<CrownProvider>.value(
          value: crown,
          child: SingleChildScrollView(
            key: scrollKey,
            controller: controller,
            child: const Column(
              children: [
                SizedBox(height: 200),
                ThroneSocial(),
                SizedBox(height: 1000),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'coronation after scrolling never reads a double as an expansion bool',
    (tester) async {
      final bucket = PageStorageBucket();
      final crown = _CrownFixture();
      final controller = ScrollController();
      addTearDown(crown.dispose);
      addTearDown(controller.dispose);
      await tester.pumpWidget(page(bucket, crown, controller));
      await tester.pump();
      controller.jumpTo(125);
      await tester.pump();
      expect(bucket.readState(tester.element(find.byKey(scrollKey))), 125.0);
      crown.crown();
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('فترة حكم الملك — المزايدات مغلقة'), findsOneWidget);
      expect(find.text('👑 0'), findsOneWidget);
      expect(find.text('❤️ 0'), findsOneWidget);
      expect(find.text('🔥 0'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'sections retain independent expansion state and scroll position after remount',
    (tester) async {
      final bucket = PageStorageBucket();
      final crown = _CrownFixture();
      final controller = ScrollController();
      addTearDown(crown.dispose);
      addTearDown(controller.dispose);
      await tester.pumpWidget(page(bucket, crown, controller));
      await tester.pump();
      await tester.tap(find.text('أقوى ثلاثة منافسين'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('لا توجد مشاركات بعد'), findsOneWidget);
      controller.jumpTo(150);
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(page(bucket, crown, controller));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(controller.offset, 150.0);
      await tester.pumpAndSettle();
      expect(find.text('لا توجد مشاركات بعد'), findsOneWidget);
      expect(find.text('لا توجد فترات حكم مكتملة'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
