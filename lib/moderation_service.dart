import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ModerationResult {
  final bool allowed;
  final bool isAgeRestricted;
  final String reason;
  // A failed/unfinished check is NOT an approval or a content violation.
  final bool isUnavailable;
  ModerationResult({required this.allowed, this.isAgeRestricted = false,
      this.reason = "", this.isUnavailable = false});
}

class ModerationService {
  static ModerationResult _unavailable() => ModerationResult(
    allowed: false, isUnavailable: true,
    reason: 'تعذّر إكمال فحص الأمان. حاول مجدداً.',
  );

  // Retry a temporary outage only; never turn a failed API request into
  // "allowed". Timeout and retry limits also prevent an endless publish job.
  static Future<Map<String, dynamic>?> _requestModeration(Object input) async {
    final key = dotenv.env['OPENAI_API_KEY'];
    if (key == null || key.trim().isEmpty) return null;

    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await http.post(
          Uri.parse('https://api.openai.com/v1/moderations'),
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'model': 'omni-moderation-latest', 'input': input}),
        ).timeout(const Duration(seconds: 12));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data is! Map<String, dynamic> || data['results'] is! List ||
              (data['results'] as List).isEmpty ||
              (data['results'] as List).first is! Map<String, dynamic>) {
            return null;
          }
          return (data['results'] as List).first as Map<String, dynamic>;
        }
        // Invalid credentials/requests cannot be fixed by repeated calls.
        if (response.statusCode != 429 && response.statusCode < 500) return null;
      } catch (_) {
        // Network, timeout, and malformed-response failures are unavailable.
      }
      if (attempt < 2) {
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }
    return null;
  }

  static bool _validCategories(Map<String, dynamic> categories,
      List<String> names) => names.every((name) => categories[name] is bool);

  // --- النص - القديم بقي شغال ---
  static Future<bool> checkText(String text) async {
    final detailed = await checkTextDetailed(text);
    return detailed.allowed;
  }

  // --- النص - الجديد بيمشي على القائمة ---
  static Future<ModerationResult> checkTextDetailed(String text) async {
    if (text.trim().isEmpty) return ModerationResult(allowed: true, reason: "مسموح");

    final result = await _requestModeration(text);
    if (result == null || result['categories'] is! Map<String, dynamic> ||
        result['category_scores'] is! Map<String, dynamic>) {
      return _unavailable();
    }
    final cats = result['categories'] as Map<String, dynamic>;
    final scores = result['category_scores'] as Map<String, dynamic>;
    if (!_validCategories(cats, [
      'sexual/minors', 'violence', 'harassment/threatening', 'illicit',
    ]) || scores['violence'] is! num || scores['illicit'] is! num) {
      return _unavailable();
    }

    // 1. محظور فوراً بالنص حسب قائمتنا
    if (cats['sexual/minors'] == true) {
      return ModerationResult(allowed: false, reason: "محظور: قاصر");
    }
    // تهديد قتل محدد مع سلاح - هاد الوحيد المحظور بالكلام
    if (cats['violence'] == true && (scores['violence'] as num).toDouble() > 0.85) {
      // اذا في تهديد حقيقي وجدي
      if (cats['harassment/threatening'] == true ||
          (scores['violence'] as num).toDouble() > 0.9) {
        return ModerationResult(allowed: false, reason: "محظور: تهديد قتل");
      }
    }
    if (cats['illicit'] == true && (scores['illicit'] as num).toDouble() > 0.85) {
      return ModerationResult(allowed: false, reason: "محظور: تعليم تصنيع مخدرات/سلاح");
    }

    // 2. كلشي تاني مسموح حسب قائمتنا
    // - تحكي عن جريمة صارت = مسموح
    // - تحكي عن سلاح (مواصفات، سعر) = مسموح
    // - سب / شتيمة خفيفة = مسموح
    // OpenAI ممكن يعمل flagged على هدول بس نحنا بدنا نسمحهم
    return ModerationResult(allowed: true, reason: "مسموح");
  }

  static Future<bool> checkImage(String base64Image) async {
    if (base64Image.isEmpty) return false;
    final result = await _requestModeration([
      {'type': 'image_url', 'image_url': {'url': 'data:image/jpeg;base64,$base64Image'}}
    ]);
    // The bool-only API cannot represent "unavailable"; fail closed.
    return result != null && result['flagged'] == false;
  }

  static Future<bool> checkFullVideo(List<String> base64Frames) async {
    final detailed = await checkFullVideoDetailed(base64Frames);
    return detailed.allowed;
  }

  static Future<ModerationResult> checkFullVideoDetailed(List<String> base64Frames) async {
    // No frames means no video safety decision was made.
    if (base64Frames.isEmpty) return _unavailable();

    bool needAgeRestriction = false;
    for (final frame in base64Frames) {
      if (frame.isEmpty) return _unavailable();
      final result = await _requestModeration([
        {'type': 'image_url', 'image_url': {'url': 'data:image/jpeg;base64,$frame'}}
      ]);
      if (result == null || result['categories'] is! Map<String, dynamic> ||
          result['category_scores'] is! Map<String, dynamic>) {
        return _unavailable();
      }
      final cats = result['categories'] as Map<String, dynamic>;
      final scores = result['category_scores'] as Map<String, dynamic>;
      if (!_validCategories(cats, [
        'sexual/minors', 'illicit/violent', 'sexual', 'illicit',
        'violence', 'violence/graphic',
      ]) || scores['sexual'] is! num || scores['illicit'] is! num) {
        return _unavailable();
      }

      if (cats['sexual/minors'] == true ||
          cats['illicit/violent'] == true ||
          (cats['sexual'] == true && (scores['sexual'] as num).toDouble() > 0.85)) {
        return ModerationResult(allowed: false, reason: "محظور: عري صريح/ قاصر");
      }
      if (cats['illicit'] == true && (scores['illicit'] as num).toDouble() > 0.8) {
        return ModerationResult(allowed: false, reason: "محظور: تعليم تصنيع سلاح/مخدرات");
      }
      if ((cats['sexual'] == true && (scores['sexual'] as num).toDouble() > 0.2) ||
          cats['violence'] == true ||
          cats['violence/graphic'] == true) {
        needAgeRestriction = true;
      }
    }
    if (needAgeRestriction) {
      return ModerationResult(allowed: true, isAgeRestricted: true, reason: "مسموح +18");
    }
    return ModerationResult(allowed: true, isAgeRestricted: false, reason: "مسموح");
  }
}