import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';

class LocalStickerManager {
  static const String _favoritesKey = 'favorite_stickers';
  static const String _userStickersKey = 'user_stickers';

  static Future<String?> pickAndSaveImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return null;

    final dir = await getApplicationDocumentsDirectory();
    final stickersDir = Directory('${dir.path}/user_stickers');
    if (!await stickersDir.exists()) {
      await stickersDir.create();
    }

    final fileName = '${DateTime.now().millisecondsSinceEpoch}.png';
    final newPath = '${stickersDir.path}/$fileName';
    await File(image.path).copy(newPath);

    final prefs = await SharedPreferences.getInstance();
    final List<String> stickers = prefs.getStringList(_userStickersKey)?? [];
    stickers.add(newPath);
    await prefs.setStringList(_userStickersKey, stickers);

    return newPath;
  }

  static Future<List<String>> getUserStickers() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_userStickersKey)?? [];
  }

  static Future<List<String>> getFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_favoritesKey)?? [];
  }

  static Future<void> toggleFavorite(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> favorites = prefs.getStringList(_favoritesKey)?? [];
    if (favorites.contains(path)) {
      favorites.remove(path);
    } else {
      favorites.add(path);
    }
    await prefs.setStringList(_favoritesKey, favorites);
  }
}