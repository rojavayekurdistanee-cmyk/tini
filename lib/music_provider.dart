import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'itunes_service.dart';

class MusicProvider extends ChangeNotifier {
  // --- قوائم البيانات ---
  List<Map<String, dynamic>> _trendingTracks = [];
  List<Map<String, dynamic>> _latestTracks = [];
  List<Map<String, dynamic>> _recommendedTracks = [];
  List<Map<String, dynamic>> _favoriteTracks = [];
  List<Map<String, dynamic>> _searchResults = []; // [إضافة] قائمة نتائج البحث

  // --- حالات التحميل ---
  bool _isLoadingTrending = false;
  bool _isLoadingLatest = false;
  bool _isLoadingRecommended = false;
  bool _isLoadingFavorites = false;
  bool _isLoadingSearch = false; // [إضافة] حالة تحميل البحث

  // --- Getters ---
  List<Map<String, dynamic>> get trendingTracks => _trendingTracks;
  List<Map<String, dynamic>> get latestTracks => _latestTracks;
  List<Map<String, dynamic>> get recommendedTracks => _recommendedTracks;
  List<Map<String, dynamic>> get favoriteTracks => _favoriteTracks;
  List<Map<String, dynamic>> get searchResults => _searchResults; // [إضافة]

  bool get isLoadingTrending => _isLoadingTrending;
  bool get isLoadingLatest => _isLoadingLatest;
  bool get isLoadingRecommended => _isLoadingRecommended;
  bool get isLoadingFavorites => _isLoadingFavorites;
  bool get isLoadingSearch => _isLoadingSearch; // [إضافة]

  // [إضافة] دالة البحث
  Future<void> searchTracks(String query) async {
    if (query.isEmpty) {
      _searchResults = [];
      notifyListeners();
      return;
    }
    _isLoadingSearch = true;
    notifyListeners();
    try {
      _searchResults = await iTunesService.searchTracks(query);
    } catch (e) {
      debugPrint("Error searching tracks: $e");
    }
    _isLoadingSearch = false;
    notifyListeners();
  }

  // 1. جلب المشهور (Trending)
  Future<void> fetchTrending() async {
    _isLoadingTrending = true;
    notifyListeners();
    try {
      _trendingTracks = await iTunesService.getTrendingTracks();
    } catch (e) {
      debugPrint("Error fetching trending: $e");
    }
    _isLoadingTrending = false;
    notifyListeners();
  }

  // 2. جلب الأحدث (Latest)
  Future<void> fetchLatest() async {
    _isLoadingLatest = true;
    notifyListeners();
    try {
      // نستخدم البحث بكلمة عامة أو تصنيف إذا توفر، هنا نستخدم بحث افتراضي كـ Latest
      _latestTracks = await iTunesService.searchTracks("latest");
    } catch (e) {
      debugPrint("Error fetching latest: $e");
    }
    _isLoadingLatest = false;
    notifyListeners();
  }

  // 3. جلب المقترحات (Recommended)
  Future<void> fetchRecommended() async {
    _isLoadingRecommended = true;
    notifyListeners();
    try {
      // يمكن تطويرها لتعتمد على اهتمامات المستخدم لاحقاً
      _recommendedTracks = await iTunesService.searchTracks("trending");
    } catch (e) {
      debugPrint("Error fetching recommended: $e");
    }
    _isLoadingRecommended = false;
    notifyListeners();
  }

  // 4. جلب المفضلات (Favorites) من Firestore [تم التعديل للجلب الدقيق]
  Future<void> fetchFavorites(String uid) async {
    _isLoadingFavorites = true;
    notifyListeners();
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        List<dynamic> favIds = doc.data()?['favorites'] ?? [];
        List<Map<String, dynamic>> tempFavs = [];
        
        // جلب تفاصيل كل أغنية من الـ API بناءً على معرفاتها باستخدام getTrackById
        for (var id in favIds) {
          if (id.toString().isNotEmpty) {
            // التعديل: استخدام دالة الجلب المباشر عبر الـ ID
            var trackData = await iTunesService.getTrackById(id.toString());
            if (trackData != null) {
              tempFavs.add(trackData);
            }
          }
        }
        _favoriteTracks = tempFavs;
      }
    } catch (e) {
      debugPrint("Error fetching favorites: $e");
    }
    _isLoadingFavorites = false;
    notifyListeners();
  }

  // 5. إضافة/حذف مفضلة
  Future<void> toggleFavorite(String uid, Map<String, dynamic> track) async {
    try {
      final docRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final trackId = track['id'];

      if (_favoriteTracks.any((t) => t['id'] == trackId)) {
        await docRef.update({
          'favorites': FieldValue.arrayRemove([trackId])
        });
        _favoriteTracks.removeWhere((t) => t['id'] == trackId);
      } else {
        await docRef.update({
          'favorites': FieldValue.arrayUnion([trackId])
        });
        _favoriteTracks.add(track);
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Error toggling favorite: $e");
    }
  }
}