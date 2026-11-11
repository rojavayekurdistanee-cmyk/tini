import 'user_documents.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'audience_access.dart';

class SearchProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final AudienceAccess _audience = AudienceAccess.instance;
  StreamSubscription<User?>? _authSubscription;
  int _searchVersion = 0;
  bool _disposed = false;

  SearchProvider() {
    _myUid = _auth.currentUser?.uid ?? '';
    _audience.addListener(_onAudienceChanged);
    _authSubscription = _auth.authStateChanges().listen((user) {
      if (_myUid != (user?.uid ?? '')) _resetForViewer(user?.uid ?? '');
    });
  }

  bool get _sameViewer => _myUid == (_auth.currentUser?.uid ?? '');

  void _onAudienceChanged() {
    if (_disposed) return;
    if (!_sameViewer) {
      _resetForViewer(_auth.currentUser?.uid ?? '');
      return;
    }
    notifyListeners();
  }

  void _resetForViewer(String uid) {
    _myUid = uid;
    _myFollowingList = [];
    _myFollowersList = [];
    _myBlockedList = [];
    _recentSearches = [];
    _recentSearchesDetailed = [];
    clearSearch();
  }

  bool _requestIsCurrent(int version, String uid) =>
      !_disposed && version == _searchVersion &&
      uid == (_auth.currentUser?.uid ?? '') && uid == _myUid;

  @override
  void dispose() {
    _disposed = true;
    _searchVersion++;
    _authSubscription?.cancel();
    _audience.removeListener(_onAudienceChanged);
    super.dispose();
  }

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String _currentQuery = '';
  String get currentQuery => _currentQuery;

  // النتائج الأربعة
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _posts = [];
  List<Map<String, dynamic>> _hashtags = [];
  List<Map<String, dynamic>> _songs = [];

  // احتفظ بالنتائج الأصلية؛ تغير جمهور الحساب يعيد تقييم العرض فوراً.
  List<Map<String, dynamic>> get users => !_sameViewer ? [] : _users.where((user) =>
      _audience.canViewProfile((user['uid'] ?? '').toString())).toList();
  List<Map<String, dynamic>> get posts => !_sameViewer ? [] : _posts.where((post) =>
      _audience.canViewPost(post, postId: post['postId']?.toString())).toList();
  List<Map<String, dynamic>> get hashtags => _sameViewer ? _hashtags : [];
  List<Map<String, dynamic>> get songs {
    if (!_sameViewer) return [];
    final visible = <Map<String, dynamic>>[];
    for (final song in _songs) {
      final sources = (song['_audienceSources'] as List?) ?? const [];
      for (final source in sources) {
        final post = Map<String, dynamic>.from(source as Map);
        if (!_audience.canViewPost(post, postId: post['postId']?.toString())) continue;
        visible.add({...song, 'cover': post['songCover'], 'source': post['songSource']});
        break;
      }
    }
    return visible;
  }

  // البحث الأخير
  List<String> _recentSearches = [];
  List<String> get recentSearches => _sameViewer ? _recentSearches : [];

  // [جديد - ميزة الوقت] سجل مفصل مع تاريخ لكل بحث
  List<Map<String, dynamic>> _recentSearchesDetailed = [];
  List<Map<String, dynamic>> get recentSearchesDetailed => _sameViewer ? _recentSearchesDetailed : [];

  // بيانات المستخدم الحالي للفلترة
  List<String> _myFollowingList = [];
  List<String> _myFollowersList = [];
  List<String> _myBlockedList = [];
  String _myUid = '';

  // [جديد - Pagination] متغيرات التحميل التدريجي
  DocumentSnapshot? _lastPostDoc;
  bool _hasMorePosts = true;
  bool _isLoadingMore = false;

  bool get hasMorePosts => _hasMorePosts;
  bool get isLoadingMore => _isLoadingMore;

  // تهيئة بيانات الفلترة V6 - بدون followingList + AUDIENCE CONTROL - FIXED V2
  Future<void> _initFilters(int version, String uid) async {
    // ملاحظات الفحص القديم محفوظة؛ استبدلها المصدر الموحد بالتحقق من الميلاد:
    // [إصلاح] 1- اقرا isUserAdult أولاً - اذا موجود اعتمده
    // لا تعتمد عليه مباشرة اذا age موجود، شيك على age أول
    // اذا age = 0 حاول تحسبه من التاريخ قبل ما تعتبره طفل
    // isUserAdult غير موجود - احسب من age او التاريخ
    // قرار العمر من المصدر الموحد؛ غياب التاريخ أو فشل القراءة لا يثبت البلوغ.
    if (uid.isEmpty) return;
    List<String> following = [];
    List<String> followers = [];
    List<String> blocked = [];
    // جلب المتابعة من subcollection
    try {
      final snap = await _firestore.collection('users').doc(uid).collection('following').get();
      following = snap.docs.map((d) => d.id).toList();
    } catch (e) {
      following = [];
    }
    try {
      final snapFollowers = await _firestore.collection('users').doc(uid).collection('followers').get();
      followers = snapFollowers.docs.map((d) => d.id).toList();
    } catch (e) {
      followers = [];
    }
    // [Tini: Phase 4 - نظام الحظر - مركزي]
    try {
      final userDoc2 = await UserDocuments.readable(_firestore, uid).get();
      final List bField = userDoc2.data()?['blockedUsers'] ?? userDoc2.data()?['blocked'] ?? [];
      blocked = bField.map((e) => e.toString()).toSet().toList();
      final blockedSnap = await _firestore.collection('users').doc(uid).collection('blocked').get();
      blocked = {...blocked, ...blockedSnap.docs.map((d) => d.id)}.toList();
    } catch (e) {
      blocked = [];
    }
    if (!_requestIsCurrent(version, uid)) return;
    _myFollowingList = following;
    _myFollowersList = followers;
    _myBlockedList = blocked;
  }

  // البحث الرئيسي الموحد
  Future<void> search(String query) async {
    if (query.trim().isEmpty) {
      clearSearch();
      return;
    }

    final version = ++_searchVersion;
    final uid = _auth.currentUser?.uid ?? '';
    _myUid = uid;
    _isLoading = true;
    _currentQuery = query.trim().toLowerCase();
    final searchQuery = _currentQuery;
    _users = [];
    _posts = [];
    _hashtags = [];
    _songs = [];

    // [جديد] إعادة تعيين Pagination
    _lastPostDoc = null;
    _hasMorePosts = true;
    _isLoadingMore = false;

    notifyListeners();

    try {
      await _initFilters(version, uid);
      if (!_requestIsCurrent(version, uid)) return;
      // تنفيذ 4 بحوث بالتوازي
      final results = await Future.wait([
        _searchUsers(searchQuery),
        _searchPosts(searchQuery, version: version, viewerUid: uid),
        _searchHashtags(searchQuery),
        _searchSongs(searchQuery),
      ]);

      if (!_requestIsCurrent(version, uid)) return;
      _users = results[0];
      _posts = results[1];
      _hashtags = results[2];
      _songs = results[3];

    } catch (e) {
      debugPrint('Search Error: $e');
    }

    if (!_requestIsCurrent(version, uid)) return;
    _isLoading = false;
    notifyListeners();
  }

  // 1. البحث عن أشخاص
  Future<List<Map<String, dynamic>>> _searchUsers(String q) async {
    final List<Map<String, dynamic>> results = [];

    // البحث بـ username_lowercase
    final usernameQuery = await _firestore
.collection('public_profiles')
.where('username_lowercase', isGreaterThanOrEqualTo: q)
.where('username_lowercase', isLessThanOrEqualTo: '$q\uf8ff')
.limit(20)
.get();

    // البحث بـ fullName_lowercase
    final nameQuery = await _firestore
.collection('public_profiles')
.where('fullName_lowercase', isGreaterThanOrEqualTo: q)
.where('fullName_lowercase', isLessThanOrEqualTo: '$q\uf8ff')
.limit(20)
.get();

    final allDocs = [...usernameQuery.docs,...nameQuery.docs];
    final seenIds = <String>{};
    final reverseBlockedIds = _myUid.isEmpty
        ? <String>{}
        : (await _firestore.collection('users').doc(_myUid)
            .collection('blockedBy').get()).docs.map((doc) => doc.id).toSet();

    for (var doc in allDocs) {
      if (seenIds.contains(doc.id)) continue;
      seenIds.add(doc.id);

      // [Phase 4 - HARD BLOCK مركزي] - اخفاء المحظورين من البحث
      if (_myBlockedList.toSet().contains(doc.id)) continue;
      if (doc.id == _myUid) continue;
      final data = doc.data();
      if (reverseBlockedIds.contains(doc.id)) continue;
      // فلترة العمر - AUDIENCE CONTROL: الحساب كله 18+ ما يظهر للقاصر
      // تُطبّق لحظياً في getter بالاعتماد على الحساب الحالي.
      _audience.canViewProfile(doc.id);

      results.add({
        'type': 'user',
   ...data,
        'uid': doc.id,
        'username': data['username']?? '',
        'fullName': data['fullName']?? '',
        'profileImg': data['profileImg']?? '',
        'followers': data['followers']?? 0,
        'isFriend': _myFollowingList.contains(doc.id),
      });
    }

    // ترتيب: الأصدقاء أولاً ثم الأكثر متابعين
    results.sort((a, b) {
      final aFriend = a['isFriend']? 1 : 0;
      final bFriend = b['isFriend']? 1 : 0;
      if (aFriend!= bFriend) return bFriend.compareTo(aFriend);
      return (b['followers']?? 0).compareTo(a['followers']?? 0);
    });

    return results;
  }

  // 2. البحث عن فيديوهات [معدل - Pagination]
  Future<List<Map<String, dynamic>>> _searchPosts(String q, {DocumentSnapshot? startAfter, required int version, required String viewerUid}) async {
    final List<Map<String, dynamic>> results = [];
    final seenIds = <String>{};

    // أ. البحث بالهاشتاق
    var hashtagQueryRef = _firestore
.collection('posts')
.where('hashtags_lowercase', arrayContains: q.replaceAll('#', ''))
.orderBy('views', descending: true)
.limit(30);

    if (startAfter!= null) {
      hashtagQueryRef = hashtagQueryRef.startAfterDocument(startAfter);
    }

    final hashtagQuery = await hashtagQueryRef.get();

    // ب. البحث بالوصف
    var descQueryRef = _firestore
.collection('posts')
.where('description_lowercase', isGreaterThanOrEqualTo: q)
.where('description_lowercase', isLessThanOrEqualTo: '$q\uf8ff')
.limit(30);

    if (startAfter!= null) {
      descQueryRef = descQueryRef.startAfterDocument(startAfter);
    }

    final descQuery = await descQueryRef.get();

    final allDocs = [...hashtagQuery.docs,...descQuery.docs];

    for (var doc in allDocs) {
      if (seenIds.contains(doc.id)) continue;
      seenIds.add(doc.id);

      final data = doc.data();

      // تطبيق الفلاتر
      if (!_passesPostFilters(data)) continue;
      _audience.trackPost(data, postId: doc.id);

      // فحص النص
      final description = (data['description_lowercase']?? '').toString();
      final location = (data['location']?? '').toString().toLowerCase();
      final hashtags = List<String>.from(data['hashtags_lowercase']?? []).join(' ');

      if (description.contains(q) ||
          location.contains(q) ||
          hashtags.contains(q) ||
          hashtagQuery.docs.contains(doc)) {

        results.add({
          'type': 'post',
     ...data,
          'postId': doc.id,
          'username': data['username']?? '',
          'profileImg': data['profileImg']?? '',
          'thumbnailUrl': data['thumbnailUrl']?? '',
          'description': data['description']?? '',
          'views': data['views']?? 0,
          'isFriend': _myFollowingList.contains(data['uid']),
        });
      }
    }

    // ترتيب: أصدقاء أولاً ثم الأكثر مشاهدة
    results.sort((a, b) {
      final aFriend = a['isFriend']? 1 : 0;
      final bFriend = b['isFriend']? 1 : 0;
      if (aFriend!= bFriend) return bFriend.compareTo(aFriend);
      return (b['views']?? 0).compareTo(a['views']?? 0);
    });

    final finalResults = results.take(30).toList();

    // [جديد] حفظ آخر doc للـ pagination
    if (!_requestIsCurrent(version, viewerUid)) return [];
    if (finalResults.isNotEmpty && startAfter == null) {
      // نحفظ آخر doc من الاستعلام الأصلي
      if (allDocs.isNotEmpty) {
        _lastPostDoc = allDocs.last;
      }
    } else if (finalResults.isNotEmpty && startAfter!= null) {
      if (allDocs.isNotEmpty) {
        _lastPostDoc = allDocs.last;
      }
    }

    return finalResults;
  }

  // [جديد] تحميل المزيد من الفيديوهات
  Future<void> loadMorePosts() async {
    if (!_hasMorePosts || _isLoadingMore || _currentQuery.isEmpty || _lastPostDoc == null) return;

    final version = _searchVersion;
    final uid = _auth.currentUser?.uid ?? '';
    _isLoadingMore = true;
    notifyListeners();

    try {
      final moreResults = await _searchPosts(_currentQuery, startAfter: _lastPostDoc,
          version: version, viewerUid: uid);
      if (!_requestIsCurrent(version, uid)) return;

      if (moreResults.isNotEmpty) {
        // منع التكرار
        final existingIds = _posts.map((p) => p['postId']).toSet();
        final newPosts = moreResults.where((p) =>!existingIds.contains(p['postId'])).toList();

        _posts.addAll(newPosts);
        _hasMorePosts = newPosts.length >= 20; // إذا جبنا أقل من 20، غالباً خلصنا
      } else {
        _hasMorePosts = false;
      }

    } catch (e) {
      debugPrint('Load More Error: $e');
      if (!_requestIsCurrent(version, uid)) return;
      _hasMorePosts = false;
    }

    if (!_requestIsCurrent(version, uid)) return;
    _isLoadingMore = false;
    notifyListeners();
  }

  // 3. البحث عن هاشتاقات
  Future<List<Map<String, dynamic>>> _searchHashtags(String q) async {
    final cleanQ = q.replaceAll('#', '');

    final query = await _firestore
.collection('hashtags')
.where('name_lowercase', isGreaterThanOrEqualTo: cleanQ)
.where('name_lowercase', isLessThanOrEqualTo: '$cleanQ\uf8ff')
.orderBy('name_lowercase')
.limit(15)
.get();

    return query.docs.map((doc) => {
      'type': 'hashtag',
      'name': doc['name'],
      'count': doc['count']?? 0,
    }).toList();
  }

  // 4. البحث عن أصوات
  Future<List<Map<String, dynamic>>> _searchSongs(String q) async {
    final query = await _firestore
.collection('posts')
.where('songTitle_lowercase', isGreaterThanOrEqualTo: q)
.where('songTitle_lowercase', isLessThanOrEqualTo: '$q\uf8ff')
.limit(100)
.get();

    final Map<String, Map<String, dynamic>> uniqueSongs = {};

    for (var doc in query.docs) {
      final data = doc.data();
      if (!_passesPostFilters(data)) continue;
      _audience.trackPost(data, postId: doc.id);

      final title = (data['songTitle_lowercase']?? '').toString();
      final artist = (data['songArtist']?? '').toString().toLowerCase();

      if (title.contains(q) || artist.contains(q)) {
        final key = '${data['songTitle']}_${data['songArtist']}';
        if (!uniqueSongs.containsKey(key) && data['songTitle']!= null) {
          uniqueSongs[key] = {
            'type': 'song',
            'title': data['songTitle'],
            'artist': data['songArtist'],
            'cover': data['songCover'],
            'source': data['songSource'],
            'uses': 1,
            '_audienceSources': <Map<String, dynamic>>[],
          };
        }
        if (uniqueSongs.containsKey(key)) {
          (uniqueSongs[key]!['_audienceSources'] as List).add({...data, 'postId': doc.id});
        }
      }
    }

    return uniqueSongs.values.take(15).toList();
  }

  // فلتر البوستات الموحد + HARD BLOCK مركزي
  bool _passesPostFilters(Map<String, dynamic> data) {
    final String postOwner = data['uid']?.toString()?? '';
    if (postOwner.isEmpty) return false;
    if (_myBlockedList.toSet().contains(postOwner)) return false;
    if (postOwner == _myUid) return true; // فيديوهاتي ما تنفلتر
    final String pr = (data['privacy'] ?? 'public').toString().toLowerCase();
    final String privacy = pr == 'everyone' ? 'public' : pr == 'only_me' ? 'private' : pr;
    if (privacy == 'private') return false; // only_me + private
    if (privacy == 'friends') {
      if (data['uid'] != _myUid && (!_myFollowingList.contains(data['uid']) || !_myFollowersList.contains(data['uid']))) {
        return false;
      }
    }

    // العمر يُراجع في getters حتى لا تصبح حالة مالك قديمة مصدراً دائماً للقرار.

    if (data['processingStatus'] == 'processing') return false;

    // [تعديل] اخفاء الصندوق النادر عن الغريب
    final bool isBox = data['isMysteryBox']?? false;
    if (isBox) {
      final String ownerId = data['uid']?? '';
      final String buyerId = data['boxOwnedByUid']?? '';
      if (_myUid!= ownerId && _myUid!= buyerId) {
        return false;
      }
    }
    return true;
  }

  void clearSearch() {
    _searchVersion++;
    _isLoading = false;
    _currentQuery = '';
    _users = [];
    _posts = [];
    _hashtags = [];
    _songs = [];
    _lastPostDoc = null;
    _hasMorePosts = true;
    _isLoadingMore = false;
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> quickHashtagSearch(String q) async {
    if (q.isEmpty) return [];
    return _searchHashtags(q);
  }

  Future<void> loadRecentSearches() async {
    _myUid = _auth.currentUser?.uid?? '';
    if (_myUid.isEmpty) return;

    final uid = _myUid;
    final doc = await UserDocuments.readable(_firestore, uid).get();
    if (uid != (_auth.currentUser?.uid ?? '') || _disposed) return;
    if (doc.exists) {
      final data = doc.data()!;

      // [جديد - ميزة الوقت] حاول تقرأ الجديد أولاً
      if (data['recentSearchesDetailed']!= null) {
        final List detailed = data['recentSearchesDetailed'];
        _recentSearchesDetailed = detailed.map((e) {
          return <String, dynamic>{
            'query': e['query'].toString(),
            'timestamp': e['timestamp'] is Timestamp? e['timestamp'] : Timestamp.now(),
          };
        }).toList();
        // حدث القديم للتوافق
        _recentSearches = _recentSearchesDetailed.map((e) => e['query'] as String).toList();
      } else {
        // fallback للقديم
        _recentSearches = List<String>.from(data['recentSearches']?? []);
        _recentSearchesDetailed = _recentSearches.map((q) => <String, dynamic>{
          'query': q,
          'timestamp': Timestamp.now(),
        }).toList();
      }
    }
    notifyListeners();
  }

  Future<void> addRecentSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;

    _myUid = _auth.currentUser?.uid?? '';
    if (_myUid.isEmpty) return;

    // [قديم] للتوافق
    _recentSearches.remove(q);
    _recentSearches.insert(0, q);
    if (_recentSearches.length > 50) {
      _recentSearches = _recentSearches.take(50).toList();
    }

    // [جديد - ميزة الوقت]
    _recentSearchesDetailed.removeWhere((e) => e['query'] == q);
    _recentSearchesDetailed.insert(0, <String, dynamic>{
      'query': q,
      'timestamp': Timestamp.now(),
    });
    if (_recentSearchesDetailed.length > 50) {
      _recentSearchesDetailed = _recentSearchesDetailed.take(50).toList();
    }

    await _firestore.collection('users').doc(_myUid).set({
      'recentSearches': _recentSearches,
      'recentSearchesDetailed': _recentSearchesDetailed,
      'recentSearchesUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    notifyListeners();
  }

  Future<void> removeRecentSearch(String query) async {
    _myUid = _auth.currentUser?.uid?? '';
    if (_myUid.isEmpty) return;

    _recentSearches.remove(query);
    _recentSearchesDetailed.removeWhere((e) => e['query'] == query);

    await _firestore.collection('users').doc(_myUid).update({
      'recentSearches': _recentSearches,
      'recentSearchesDetailed': _recentSearchesDetailed,
    });

    notifyListeners();
  }

  // [جديد - ميزة الوقت] حذف مجموعة لصفحة السجل
  Future<void> removeRecentSearches(List<String> queries) async {
    _myUid = _auth.currentUser?.uid?? '';
    if (_myUid.isEmpty) return;

    _recentSearches.removeWhere((q) => queries.contains(q));
    _recentSearchesDetailed.removeWhere((e) => queries.contains(e['query']));

    await _firestore.collection('users').doc(_myUid).update({
      'recentSearches': _recentSearches,
      'recentSearchesDetailed': _recentSearchesDetailed,
    });

    notifyListeners();
  }

  Future<void> clearRecentSearches() async {
    _myUid = _auth.currentUser?.uid?? '';
    if (_myUid.isEmpty) return;

    _recentSearches.clear();
    _recentSearchesDetailed.clear();

    await _firestore.collection('users').doc(_myUid).update({
      'recentSearches': [],
      'recentSearchesDetailed': [],
    });

    notifyListeners();
  }
}