import 'dart:convert';
import 'package:http/http.dart' as http;

class iTunesService {
  static const String _baseUrl = 'https://itunes.apple.com/search';
  static const String _lookupUrl = 'https://itunes.apple.com/lookup'; // الرابط الجديد للـ ID
  
  static const Duration _timeoutDuration = Duration(seconds: 10);

  // دالة لجلب أغنية واحدة محددة بالـ ID
  static Future<Map<String, dynamic>?> getTrackById(String id) async {
    try {
      final url = Uri.parse('$_lookupUrl?id=$id&media=music');
      final response = await http.get(url).timeout(_timeoutDuration);

      if (response.statusCode == 200) {
        final decodedData = json.decode(response.body);
        final List<dynamic> results = decodedData['results'] ?? [];
        if (results.isNotEmpty) {
          final track = results.first;
          return {
            'id': track['trackId']?.toString() ?? '',
            'title': track['trackName'] ?? 'صوت غير مسمى',
            'artist': track['artistName'] ?? 'فنان غير معروف',
            'cover': track['artworkUrl100'] ?? '',
            'url': track['previewUrl'] ?? '',
            'duration': track['trackTimeMillis'] ?? 0,
          };
        }
      }
    } catch (e) {
      print("Error fetching by ID: $e");
    }
    return null;
  }

  static Future<List<Map<String, dynamic>>> getTrendingTracks() async {
    return await _fetchFromiTunes("music");
  }

  static Future<List<Map<String, dynamic>>> searchTracks(String query) async {
    if (query.isEmpty) return await getTrendingTracks();
    return await _fetchFromiTunes(query);
  }

  static Future<List<Map<String, dynamic>>> _fetchFromiTunes(String term) async {
    try {
      final encodedQuery = Uri.encodeComponent(term);
      final url = Uri.parse('$_baseUrl?term=$encodedQuery&media=music&limit=20');
      
      final response = await http.get(url).timeout(_timeoutDuration, onTimeout: () {
        throw Exception("الطلب استغرق وقتاً طويلاً");
      });

      if (response.statusCode == 200) {
        final decodedData = json.decode(response.body);
        final List<dynamic> results = decodedData['results'] ?? [];

        return results.map((track) {
          return {
            'id': track['trackId']?.toString() ?? '',
            'title': track['trackName'] ?? 'صوت غير مسمى',
            'artist': track['artistName'] ?? 'فنان غير معروف',
            'cover': track['artworkUrl100'] ?? '',
            'url': track['previewUrl'] ?? '',
            'duration': track['trackTimeMillis'] ?? 0,
          };
        }).toList();
      }
    } catch (e) {
      print("Error fetching from iTunes: $e");
    }
    return [];
  }
}