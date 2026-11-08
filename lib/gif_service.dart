import 'dart:convert';
import 'package:http/http.dart' as http;

class GifService {
  static const String _apiKey = 'Rdwv54hAMzhtKvzW7BPbf3jKgrrCzLdD';
  static const String _baseUrl = 'https://api.giphy.com/v1/stickers/search';

  static Future<List<String>> searchStickers(String query) async {
    if (query.isEmpty) return [];

    final url = Uri.parse(
      '$_baseUrl?api_key=$_apiKey&q=$query&limit=30&rating=g&lang=ar',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List results = data['data'];
        return results.map((gif) => gif['images']['original']['url'] as String).toList();
      }
    } catch (e) {
      print('Giphy Error: $e');
    }
    return [];
  }
}