import 'package:cloud_firestore/cloud_firestore.dart';

/// Shared decisions for the existing audience switch and content moderation.
/// A stored age/adult flag is a hint, never proof of a viewer's birth date.
class AudiencePolicy {
  static bool isTrue(dynamic value) =>
      value == true ||
      value == 1 ||
      (value is String &&
          (value.trim().toLowerCase() == 'true' || value.trim() == '1'));

  static DateTime? birthDate(dynamic value) {
    DateTime? parsed;
    if (value is Timestamp) {
      parsed = value.toDate();
    } else if (value is DateTime) {
      parsed = value;
    } else if (value is String) {
      final raw = value.trim();
      final date = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:$|T| )').firstMatch(raw);
      if (date == null) return null;
      parsed = DateTime.tryParse(raw);
      // DateTime.parse normalizes impossible dates such as February 30.
      if (parsed == null ||
          int.parse(date[2]!) < 1 ||
          int.parse(date[2]!) > 12 ||
          int.parse(date[3]!) < 1 ||
          int.parse(date[3]!) >
              DateTime(int.parse(date[1]!), int.parse(date[2]!) + 1, 0).day) {
        return null;
      }
      return DateTime(
        int.parse(date[1]!),
        int.parse(date[2]!),
        int.parse(date[3]!),
      );
    }
    return parsed == null
        ? null
        : DateTime(parsed.year, parsed.month, parsed.day);
  }

  static int? verifiedAge(Map<String, dynamic> data, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final dates = <DateTime>[];
    for (final key in ['birthDate', 'dob']) {
      final raw = data[key];
      if (raw == null || (raw is String && raw.trim().isEmpty)) continue;
      final date = birthDate(raw);
      if (date == null) return null;
      dates.add(date);
    }
    if (dates.isEmpty || dates.any((date) => date != dates.first)) return null;
    final birth = dates.first;
    if (birth.year < 1900 ||
        birth.isAfter(DateTime(today.year, today.month, today.day))) {
      return null;
    }
    var age = today.year - birth.year;
    if (today.month < birth.month ||
        (today.month == birth.month && today.day < birth.day)) {
      age--;
    }
    return age;
  }

  static bool viewerIsAdult(Map<String, dynamic> data, {DateTime? now}) =>
      (verifiedAge(data, now: now) ?? -1) >= 18;

  static bool isAccountRestricted(Map<String, dynamic> data) {
    // users.isAgeRestricted also historically meant "this user is a minor".
    // It cannot identify the account audience switch.
    final canonical = ['audience_18plus', 'isAdultContent'];
    if (canonical.any(data.containsKey)) {
      return canonical.any(
        (key) =>
            isTrue(data[key]) ||
            (data[key] != null &&
                data[key] != false &&
                data[key] != 0 &&
                data[key] != 'false' &&
                data[key] != '0'),
      );
    }
    return isTrue(data['ownerIsAdultContent']) ||
        isTrue(data['ownerAudience18Plus']);
  }

  static bool isVideoRestricted(Map<String, dynamic> data) {
    // From version 2 onward these flags contain moderation only. Keep every
    // legacy positive: the old toggle overwrote even isAgeRestricted, so its
    // origin cannot safely be reconstructed from a post alone.
    return [
      'isAgeRestricted',
      'isAdultContent',
      'audience_18plus',
      if (data['ageRestrictionVersion'] != 2) ...[
        'ownerIsAdultContent',
        'ownerAudience18Plus',
      ],
    ].any((key) => isTrue(data[key]));
  }

  static String ownerUid(Map<String, dynamic> data) =>
      (data['uid'] ?? data['userId'] ?? data['ownerId'] ?? '').toString();
}