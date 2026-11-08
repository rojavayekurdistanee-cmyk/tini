import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-device progress for per-message delivery/read receipts.
///
/// Kept separately for every authenticated user and room. A checkpoint is
/// advanced only after the complete matching page scan succeeds. Re-scanning
/// the final timestamp is intentional: Firestore may contain ties.
class TiniChatReadCheckpoint {
  static String _key(String kind, String roomId, String userId) =>
      'tini_chat_read_v1:$kind:$userId:$roomId';

  static Future<Timestamp?> get(
      String kind, String roomId, String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final micros = prefs.getInt(_key(kind, roomId, userId));
    if (micros == null) return null;
    return Timestamp.fromDate(DateTime.fromMicrosecondsSinceEpoch(micros));
  }

  static Future<void> save(String kind, String roomId, String userId,
      Timestamp? timestamp) async {
    if (timestamp == null) return;
    final prefs = await SharedPreferences.getInstance();
    final key = _key(kind, roomId, userId);
    final micros = timestamp.toDate().microsecondsSinceEpoch;
    final previous = prefs.getInt(key);
    if (previous != null && previous >= micros) return;
    await prefs.setInt(key, micros);
  }

  static Query<Map<String, dynamic>> since(
      Query<Map<String, dynamic>> query, Timestamp? lastCompleted) {
    if (lastCompleted == null) return query;
    // A one-microsecond overlap avoids missing equal-timestamp messages.
    final start = lastCompleted.toDate()
        .subtract(const Duration(microseconds: 1));
    return query.where('timestamp', isGreaterThan: Timestamp.fromDate(start));
  }
}
